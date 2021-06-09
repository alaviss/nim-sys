#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import std/[deques, hashes, tables, times]
import syscall/linux/epoll except FD # we want FD to refer to handles.FD
import syscall/posix
import errors

type
  ContEvent = tuple
    ## Represents a continuation to be trigger on given events
    cont: Continuation
    events: set[ReadyEvent]

  FDQueue = object
    ## Represents a queued FD
    queued: set[ReadyEvent] ## What events the FD was queued for
    queue: Deque[ContEvent]

  EventQueueImpl = object
    case initialized: bool
    of true:
      epoll: Handle[epoll.FD]
      queues: Table[FD, FDQueue]
    of false:
      discard

proc hash*(fd: FD): Hash {.borrow.}

template initImpl() {.dirty.} =
  if eq.initialized: return

  eq = EventQueueImpl(
    initialized: true,
    epoll: initHandle(epoll.create(flags = O_CLOEXEC))
  )
  posixChk eq.epoll.get.cint, InitError

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

func toReadyEvents(ev: Ev): set[ReadyEvent] =
  if ev.has EvIn:
    result.incl Read
  if ev.has EvOut:
    result.incl Write

proc queue(eq: var EventQueueImpl, fd: AnyFD, events: set[ReadyEvent]) =
  ## Queue `fd` for the given events. If `fd` is already in the queue, add
  ## the specified `events` to the list of queued events.
  assert eq.initialized, "queue() called without initialization, this is a nim-sys bug"

  if fd notin eq.queues:
    # make a new queue
    eq.queues[fd] = default FDQueue

  let evUnion = eq.queues[fd].queued + events
  if eq.queues[fd].queued < evUnion:
    var epEvent = Event(events: evUnion.toEv(), data: Data(fd: fd.cint))
    if eq.epoll.get.ctl(CtlAdd, fd, epEvent) == -1:
      if errno == EEXIST:
        posixChk eq.epoll.get.ctl(CtlMod, fd, epEvent), QueueError
      else:
        posixChk -1, QueueError
    eq.queues[fd].queued = evUnion

template pollImpl() {.dirty.} =
  if not eq.initialized: return

  var events = newSeq[Event](eq.queues.len)
  let
    timeout =
      if timeout == DurationZero:
        -1.cint
      else:
        timeout.inMilliseconds.cint

    selected = eq.epoll.get.wait(events, timeout)

  posixChk selected, PollError
  events.setLen selected

  for event in events:
    let fd = FD event.data.fd
    assert eq.queues.hasKey(fd),
           "An unknown FD (" & $fd.cint & ") was registered into epoll"
    # Get what events were last queued for and empty the set. This is because
    # all FDs added to the queue are configured as oneshot, so receiving any
    # events will disable the fd in the queue.
    let lastQueued = move eq.queues[fd].queued
    var
      # The FD readiness
      ready = event.events.toReadyEvents()
      # Stash events that are not fullfilled for re-adding into queue
      stash = initDeque[ContEvent](eq.queues[fd].queue.len)
    assert ready <= lastQueued,
           "Additional unregistered events received, got: " & $ready & ", queued: " & $lastQueued
    # Events that were queued but were not received
    let pending = lastQueued - ready
    try:
      while ready.len > 0 and eq.queues[fd].queue.len > 0:
        # Exclude currently queued events as they are no longer ready
        ready.excl eq.queues[fd].queued
        let (cont, onEvents) = eq.queues[fd].queue.popFirst()
        if onEvents <= ready:
          # We don't care about the continuation returned for now
          discard trampoline(cont)
        else:
          stash.addLast (cont, onEvents)
    finally:
      while stash.len > 0:
        eq.queues[fd].queue.addFirst stash.popLast()
      # Re-queue pending events
      eq.queue(fd, pending)

      if eq.queues[fd].queued.len == 0:
        assert eq.queues[fd].queue.len == 0,
               "No events were queued for FD (" & $fd.cint & ") but there are pending continuations"
        eq.queues.del(fd)
      else:
        assert eq.queues[fd].queue.len > 0,
               "Events were queued for FD (" & $fd.cint & ") but there are no continuations"

template runImpl() {.dirty.} =
  while eq.queues.len > 0:
    poll()

template waitEventImpl() {.dirty.} =
  let fd =
    when fd isnot FD:
      fd.FD
    else:
      fd

  eq.queue(fd, events)
  eq.queues[fd].queued.incl events
  eq.queues[fd].queue.addLast (c, events)
