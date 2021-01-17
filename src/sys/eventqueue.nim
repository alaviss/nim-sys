#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#              Copyright (c) 2020-2021 Andy Davidoff
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## An event queue and dispatcher for use with CPS.

import pkg/cps

const
  InitError = "Could not initialize the event queue"
    ## Used when initialization failed.

  QueueError = "Could not queue event"
    ## Used when queuing for events failed.

  PollError = "Could not poll the operating system for events"
    ## Used when poll() failed.

type
  Cont* = ref object of RootObj
    ## A continuation
    fn*: proc (c: Cont): Cont {.nimcall.}

  ReadyEvent* = enum
    reRead,
    reWrite

proc trampoline*(c: Cont) =
  ## Run a continuation until it completes
  var c = c
  while c != nil and c.fn != nil:
    c = c.fn(c)

when defined(linux):
  include private/eventqueue_linux
else:
  {.error: "This module has not been ported to your operating system".}

type
  EventQueue = EventQueueImpl

var eq {.threadvar.}: EventQueue

proc init() =
  ## Initializes the event queue for processing.
  initImpl()

proc poll*(timeout = DurationZero) =
  ## Poll the operating system for events and run associated continuations.
  ##
  ## If `timeout` is `DurationZero`, block until an event occurs.
  ##
  ## If any unhandled exceptions are raised by continuations, the exception will
  ## be passed to the caller and the continuation will be removed from the
  ## queue. The caller may call `poll()` again to process the remaining
  ## continuations.
  pollImpl()

proc run*() =
  ## Run `poll()` until there are no continuations left in the queue.
  runImpl()

using c: Cont

when not declared(waitEventImpl):
  template waitEventImpl() {.dirty.} =
    {.error: "This operation is not available for your target platform".}

proc wait*(c; fd: AnyFD, events: set[ReadyEvent]): Cont {.cpsMagic.} =
  ## Wait for the specified `fd` to be ready for the given events.
  ##
  ## For higher efficiency, only wait for ready state when the `fd` signalled
  ## that it is not ready.
  if events == {}:
    raise newException(ValueError, "List of events must not be empty")

  init()
  waitEventImpl()

when not declared(waitSignalImpl):
  template waitSignalImpl() {.dirty.} =
    {.error: "This operation is not available for your target platform".}

proc wait*(c; obj: AnyFD): Cont {.cpsMagic.} =
  ## Wait for the specified `obj` to be signaled.
  init()
  waitSignalImpl()

# TODO: wait() overload for "completion"
