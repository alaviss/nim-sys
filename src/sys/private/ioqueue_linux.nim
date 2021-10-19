#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import std/[hashes, tables, strutils]
import syscall/linux/epoll except FD, Event
import syscall/posix
import errors

import ioqueue_common

type
  Waiter = object
    ## Represent a continuation waiting for an event
    cont: Continuation
    event: ReadyEvent

  EventQueueImpl = object
    case initialized: bool
    of true:
      epoll: Handle[epoll.FD]
      waiters: Table[FD, Waiter] ##
      ## The table of FDs that were registered for waiting.
      ## These FDs may not be valid as they can be closed by the user and
      ## epoll might not notify us.
      eventBuffer: seq[epoll.Event] ##
      ## A persistent buffer for receiving events from the kernel
    of false:
      discard

proc hash*(fd: FD): Hash {.borrow.}

template initImpl() {.dirty.} =
  if eq.initialized: return

  let epfd = epoll.create(flags = O_CLOEXEC)
  posixChk epfd.cint, $Error.Init

  eq = EventQueueImpl(
    initialized: true,
    epoll: initHandle(epfd)
  )

template runningImpl() {.dirty.} =
  result = eq.initialized and eq.waiters.len > 0

func toEv(sre: set[ReadyEvent]): Ev =
  ## Convert `sre` into bitflags used by `epoll_ctl`
  ##
  ## Additional attributes are added:
  ## - Oneshot mode is enabled
  result = EvOneshot
  for re in sre:
    case re
    of Read:
      result = result or EvIn
    of Write:
      result = result or EvOut
    of PriorityRead:
      result = result or EvPri

func toEvents(ev: Ev): set[Event] =
  ## Convert `epoll` bitflags into a set of `ReadyEvent`
  if ev.has EvIn:
    result.incl Read
  if ev.has EvOut:
    result.incl Write
  if ev.has EvErr:
    result.incl Event.Error
  if ev.has EvHup:
    result.incl Hangup
  if ev.has EvPri:
    result.incl PriorityRead

proc queue(eq: var EventQueueImpl, cont: Continuation, fd: AnyFD, event: ReadyEvent) =
  var epEvent = epoll.Event(events: toEv({event}), data: Data(fd: fd.cint))
  # If adding `fd` to epoll fails
  if eq.epoll.fd.ctl(CtlAdd, fd, epEvent) == -1:
    # In case `fd` was already registered
    if errno == EEXIST:
      # If there is a waiter in the queue
      if fd in eq.waiters:
        # Error out since we don't support more than one waiter
        raise newException(ValueError, $Error.QueuedFD % $fd.cint)

      # Otherwise re-register our event
      posixChk eq.epoll.fd.ctl(CtlMod, fd, epEvent), $Error.Queue
    else:
      posixChk -1, $Error.Queue

  # Since registering `fd` succeed, it's either:
  #   - A FD previously registered but there aren't any waiters (captured above)
  #   - A FD we have never encountered before
  #
  # If the FD was never encountered before by epoll but it's in the queue
  if fd in eq.waiters:
    # Raise a defect.
    #
    # For epoll, this is a preventative measure against potentially cloned
    # FD, which could issue notifications for the closed FD that were
    # registered.
    raise newPrematureCloseDefect(fd.int)

  eq.waiters[fd] = Waiter(cont: cont, event: event)

template pollImpl() {.dirty.} =
  if not running(): return

  let timeout =
    if timeout.isNone:
      -1.cint
    else:
      timeout.get.inMilliseconds.cint

  # Set the buffer length to the amount of waiters
  eq.eventBuffer.setLen eq.waiters.len

  # Obtain the events that are ready
  let selected = eq.epoll.fd.wait(eq.eventBuffer, timeout)
  posixChk selected, $Error.Poll
  # Set the length of the buffer to the amount of events received
  eq.eventBuffer.setLen selected

  for event in eq.eventBuffer:
    let fd = FD event.data.fd
    if fd notin eq.waiters:
      raise newException(Defect):
        "An unknown FD (" & $fd.cint & ") was registered into epoll. This is a nim-sys bug."
    # Obtain the waiting continuation from the waiters list.
    #
    # We move the continuation out since all `wait()` are configured as
    # one-shot.
    let waiter = move eq.waiters[fd]
    eq.waiters.del fd

    let ready = toEvents event.events
    # If the registered event is ready or epoll raised an exceptional event.
    if waiter.event in ready or {Event.Error, Hangup} * ready != {}:
      # Consider the continuation runnable.
      runnable.add waiter.cont
    else:
      raise newException(Defect):
        "epoll signalled for events " & $ready & " but the registered event " & $waiter.event & " is not signalled. This is a nim-sys bug."

template waitEventImpl() {.dirty.} =
  let fd =
    when fd isnot FD:
      fd.FD
    else:
      fd

  eq.queue(c, fd, event)

template unregisterImpl() {.dirty.} =
  if not eq.initialized: return
  let fd = fd.FD # Converts the `fd` parameter to `FD`

  # If the FD is in the waiter list
  if fd in eq.waiters:
    # Deregister it from epoll
    let status = eq.epoll.fd.ctl(CtlDel, fd, nil)
    if status == -1:
      # If the FD is in the waiter list but epoll said that it's never
      # registered or that it's invalid, then its already closed before being
      # unregistered, which is a programming bug.
      if errno == ENOENT or errno == EBADF:
        raise newPrematureCloseDefect(fd.int)
      else:
        posixChk status, $Error.Unregister

    # Then remove the waiter
    eq.waiters.del fd
  else:
    # If the FD is not in the waiter list, then there is no need to do anything
    # as either the FD has never been registered, or it's not being waited for,
    # of which it will already be disabled as all FD are registered as oneshot.
    discard
