#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import std/[hashes, tables]
import syscall/bsd/kqueue except FD
import syscall/posix
import errors

type
  Waiter = object
    ## Represent a continuation waiting for an event
    cont: Continuation
    event: ReadyEvent

  EventQueueImpl = object
    case initialized: bool
    of true:
      kqueue: Handle[kqueue.FD]
      waiters: Table[FD, Waiter] ##
      ## The table of FDs that were registered for waiting.
      ## These FDs may not be valid as they can be closed by the user and
      ## kqueue will not notify us.
      eventBuffer: seq[Kevent] ##
      ## A persistent buffer for receiving/sending events from/to the kernel
    of false:
      discard

proc hash*(fd: FD): Hash {.borrow.}

template initImpl() {.dirty.} =
  if eq.initialized: return

  let kqfd = kqueue()
  posixChk kqfd.cint, InitError

  eq = EventQueueImpl(
    initialized: true,
    kqueue: initHandle(kqfd)
  )

template runningImpl() {.dirty.} =
  result = eq.initialized and eq.waiters.len > 0

func toFilter(re: ReadyEvent): Filter =
  ## Convert `re` into a kqueue filter
  case re
  of Read:
    FilterRead
  of Write:
    FilterWrite
  of PriorityRead:
    raise newException(ValueError, "This event is not supported by the target platform")

func toEvents(kev: Kevent): set[Event] =
  ## Convert `kev` into `set[Event]`
  func `$`(f: Filter): string {.borrow.}

  case kev.filter
  of FilterRead:
    result.incl Read
  of FilterWrite:
    result.incl Write
  else:
    raise newException(ValueError, "Unsupported event filter: " & $kev.filter)

  if kev.flags.has EvError:
    result.incl Error
  if kev.flags.has EvEOF:
    result.incl Hangup

proc queue(eq: var EventQueueImpl, cont: Continuation, fd: FD, event: ReadyEvent) =
  if fd in eq.waiters:
    # Error out since we don't support more than one waiter
    raise newException(ValueError, QueuedFDError % $fd.cint)

  let kevent = Kevent(
    ident: Ident(fd),
    filter: event.toFilter,
    # Use dispatch so we don't have to unregister the fd later
    flags: EvAdd or EvDispatch
  )

  posixChk eq.kqueue.get.kevent(changeList = [kevent]), QueueError
  eq.waiters[fd] = Waiter(cont: cont, event: event)

func toTimespec(d: Duration): Timespec =
  ## Convert a Duration to Timespec
  Timespec(
    tv_sec: posix.Time(d.inSeconds),
    tv_nsec: int(d.inNanoseconds - convert(Seconds, Nanoseconds, d.inSeconds))
  )

template pollImpl() {.dirty.} =
  if not running(): return

  # Set the buffer length to the amount of waiters
  eq.eventBuffer.setLen eq.waiters.len

  # Obtain events from kevent
  let nevents =
    if timeout.isNone:
      eq.kqueue.get.kevent(eventList = eq.eventBuffer)
    else:
      eq.kqueue.get.kevent(
        eventList = eq.eventBuffer,
        timeout = toTimespec(timeout.get)
      )
  posixChk nevents, PollError
  # Set the length of the buffer to the amount of events received
  eq.eventBuffer.setLen nevents

  for event in eq.eventBuffer:
    let fd = FD event.ident
    if fd notin eq.waiters:
      raise newException(Defect):
        "An unknown FD (" & $fd.cint & ") was registered into kqueue. This is a nim-sys bug."
    # Obtain the waiting continuation from the waiters list.
    #
    # We move the continuation out since all `wait()` are configured as
    # one-shot.
    let waiter = move eq.waiters[fd]
    eq.waiters.del fd

    let ready = toEvents event
    # If the registered even is ready
    if waiter.event in ready:
      # Consider the continuation runnable.
      runnable.add waiter.cont
    else:
      raise newException(Defect):
        "kqueue signalled for events " & $ready & " but the registered event " & $waiter.event & " is not signalled. This is a nim-sys bug."

template waitEventImpl() {.dirty.} =
  let fd =
    when fd isnot FD:
      fd.FD
    else:
      fd

  eq.queue(c, fd, event)

template unregisterImpl() {.dirty.} =
  if not eq.initialized: return

  # If the FD is in the waiter list
  if fd in eq.waiters:
    # Deregister it from kqueue
    let status = eq.kqueue.get.kevent([
      # kqueue map events using a tuple of filter & identifier, so we
      # need to reproduce both to delete the event that we want.
      Kevent(ident: Ident(fd), filter: toFilter(eq.waiters[fd].event),
             flags: EvDelete)
    ])
    if status == -1:
      # If the FD is in waiter list but kevent reported that its not
      # registered or that its invalid, then the FD was closed before
      # being unregistered, which is a programming bug.
      #
      # While this issue doesn't affect kqueue, it has implications on
      # other OS like Linux.
      if errno == ENOENT or errno == EBADF:
        raise newPrematureCloseDefect(fd.int)
      else:
        posixChk status, UnregisterError

    # Then remove the waiter
    eq.waiters.del fd
  else:
    # If the FD is not in the waiter list, then there is no need to do anything
    # as either the FD has never been registered, or it's not being waited for,
    # of which it will have already been disabled as all FD are registered as
    # oneshot.
    discard
