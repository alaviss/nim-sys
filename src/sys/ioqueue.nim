#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#              Copyright (c) 2020-2021 Andy Davidoff
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

when defined(nimdoc) and (NimMajor, NimMinor) < (1, 5):
  discard "You can't use it so docgen can't either"
else:
  ## A per-thread eventqueue for dispatching over I/O
  ##
  ## This is not meant to be a full-fledged eventqueue but rather a
  ## supplementary for other queues implementation.

  import handles
  import std/[options, times]
  import pkg/cps

  type
    Event* {.pure.} = enum
      ## Events that the operating system can signal.
      Read ## The resource is ready to be read from.
      Write ## The resource is ready to be written to.
      PriorityRead ## The resource has high-priority data available to be read.

      Error ## There is an error associated with the resource.
      Hangup ## The resource has been hung up, usually this means
             ## a peer has closed its end of the channel.

    ReadyEvent* = range[Read..PriorityRead]
      ## Events that can be registered to be waited for

    PrematureCloseDefect* = object of Defect
      ## A defect raised when a resource was invalidated while there is a
      ## waiter for it in the queue.
      ##
      ## This is considered a programming error due to the fact that some
      ## operating system might keep reporting events for the "closed" resource
      ## since it might be kept alive by other hidden references (ie. `dup` on
      ## a fd will cause epoll to keep reporting event for the original even
      ## if the original is closed).
      ##
      ## To avoid this, unregister the resource from the queue before invalidating
      ## it.
      id*: int ## The unique ID of the resource, typically the resource handle,
               ## but is dependant on the target operating system.

  func newPrematureCloseDefect*(id: int): ref PrematureCloseDefect =
    ## Creates a `PrematureCloseDefect`
    result = newException(PrematureCloseDefect):
      "Resource id " & $id & " was invalidated before its waiter could execute"
    result.id = id

  when defined(linux):
    include private/ioqueue_linux
  elif defined(macosx) or defined(bsd):
    include private/ioqueue_bsd
  elif defined(windows):
    include private/ioqueue_windows

    import ioqueue/iocp {.all.}
    export iocp
  else:
    {.error: "This module has not been ported to your operating system".}

  type
    EventQueue = EventQueueImpl

  var eq {.threadvar, used.}: EventQueue

  proc init() =
    ## Initializes the event queue for processing.
    initImpl()

  template asyncio*(prc: typed): untyped =
    ## Convenience alias to `{.cps: Continuation.}` for procedures wishing
    ## to use ioqueue.
    cps(Continuation, prc)

  proc running*(): bool =
    ## Whether there are any continuations within the queue
    runningImpl()

  proc poll*(runnable: var seq[Continuation], timeout = none(Duration)) =
    ## Poll the operating system for events and add continuations of which the
    ## resources they are waiting for are ready to `runnable`.
    ##
    ## If `timeout` is `none(Duration)`, wait indefinitely until the operating
    ## system signals an event.
    ## If `timeout` is `DurationZero`, returns immediately iff there aren't any
    ## continuations ready to be run.
    ##
    ## `timeout` is not precise, and the actual wait time depends on the target
    ## operating system.
    ##
    ## If the queue is empty, returns immediately.
    pollImpl()

  proc run*() =
    ## Wait for events and run all pending continuations in the queue. Stops
    ## when the queue is empty.
    var runnable: seq[Continuation]
    while running():
      # Get the continuations that are ready to be run.
      poll(runnable)
      # Run until the list is empty.
      while runnable.len > 0:
        discard trampoline runnable.pop()

  using c: Continuation

  when not declared(waitEventImpl):
    template waitEventImpl() {.dirty.} =
      {.error: "This operation is not available for your target platform".}

  proc wait*(c; fd: AnyFD, event: ReadyEvent): Continuation {.cpsMagic.} =
    ## Wait for the specified `fd` to be ready for the given `event`.
    ##
    ## For higher efficiency, only wait for ready state when the `fd` signalled
    ## that it is not ready.
    ##
    ## Only one continuation can be queued for any given `fd` per thread. If
    ## more than one is queued, ValueError will be raised.
    ##
    ## **Note**: Any `fd` registered into the queue (via this procedure) should be
    ## unregistered before it is closed as the semantics differs between operating
    ## system for when an FD is closed while in the queue. If such scenario is
    ## detected, `PrematureCloseDefect` will be raised.
    ##
    ## **Platform specific details**
    ##
    ## - This interface is not implemented on Windows since IOCP can be used to cover
    ##   every use cases of this interface.
    init()
    waitEventImpl()

  proc wait*(c; fd: Handle[AnyFD], event: ReadyEvent): Continuation {.cpsMagic.} =
    ## An overload of `wait` for `Handle`.
    ioqueue.wait(c, fd.get, event)

  when not declared(unregisterImpl):
    template unregisterImpl() {.dirty.} =
      {.error: "This operation is not available for your target platform".}

  proc unregister*(fd: AnyFD) =
    ## If `fd` was registered in the queue, remove it alongside its
    ## continuation.
    ##
    ## Does nothing if the `fd` is not in the queue.
    ##
    ## **Platform specific details**
    ##
    ## - On Windows, `unregister` will abort all ongoing IO in `fd` and its
    ##   resources will only be collected in the next `poll()` iff the
    ##   queue is still running.
    ##
    ## - On Windows, `poll()` might still be interrupted by activities on `fd`
    ##   even after unregistration since `fd` will only be detached from IOCP
    ##   *after* it and its duplicates are closed.
    unregisterImpl()

  proc unregister*(fd: Handle[AnyFD]) =
    ## An overload of `unregister` for `Handle`
    ioqueue.unregister(fd.get)
