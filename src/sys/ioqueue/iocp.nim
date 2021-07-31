#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import std/[tables, hashes, times, options, strutils]
import pkg/cps
import ".."/handles

import ".."/private/[ioqueue_common, errors]
import ".."/private/syscall/winim/winim/core as wincore except Handle, Error

## Windows-specific implementation of `ioqueue`.
##
## Shares the same queue and interface with `ioqueue`. Most users
## do not need to import this module as it is exported by `ioqueue`.

type
  Waiter = object
    ## Represent a continuation waiting for the completion event
    cont: Continuation
    overlapped: ref Overlapped ##
    ## The overlapped structure submitted to the kernel

  EventQueue = object
    case initialized: bool
    of true:
      iocp: Handle[FD] ## The IOCP handle.
      waiters: Table[FD, Waiter] ##
      ## The table of FDs that were registered for waiting.
      ## These FDs may not be valid as they can be closed by the user and
      ## IOCP will not notify us.
      cancelled: Table[ptr Overlapped, Waiter] ##
      ## The table of cancelled overlapped operations.
      ## This is meant to keep the related buffers alive until the kernel
      ## signified cancellation.
      eventBuffer: seq[OverlappedEntry] ##
      ## A persistent buffer for receiving events from the kernel.
    of false:
      discard

var eq {.threadvar.}: EventQueue

proc hash(fd: FD): Hash {.borrow.}

proc init() =
  ## Initializes the queue for processing
  if eq.initialized: return

  let iocp = CreateIoCompletionPort(
    wincore.Handle(InvalidFD),
    wincore.Handle(0),
    0,
    1 # Access from a single thread only
  )

  if iocp == wincore.Handle(0):
    raise newOSError(GetLastError(), $Error.Init)

  eq = EventQueue(
    initialized: true,
    iocp: initHandle(iocp.FD)
  )

proc running(): bool =
  ## See the documentation of `ioqueue.running()`
  eq.initialized and eq.waiters.len > 0

proc poll(runnable: var seq[Continuation], timeout = none(Duration)) {.used.} =
  ## See the documentation of `ioqueue.poll()`
  init()
  if not running(): return

  let timeout =
    if timeout.isNone:
      Infinite
    else:
      DWORD(timeout.get.inMilliseconds)

  # Set the buffer length to the amount of waiters
  eq.eventBuffer.setLen eq.waiters.len

  # Obtain completion events
  var selected: ULONG
  if GetQueuedCompletionStatusEx(
    wincore.Handle(eq.iocp.get), addr eq.eventBuffer[0], ULONG(eq.eventBuffer.len),
    addr selected, timeout, wincore.FALSE
  ) == wincore.FALSE:
    let errorCode = GetLastError()
    if errorCode == WaitTimeout:
      discard "timed out without any event removed"
    else:
      raise newOSError(errorCode, $Error.Poll)

  # Set the buffer length to the amount received
  eq.eventBuffer.setLen selected

  for event in eq.eventBuffer:
    let fd = FD event.lpCompletionKey

    # This operation was cancelled
    if event.lpOverlapped in eq.cancelled:
      # Release the resource associated with operation
      eq.cancelled.del event.lpOverlapped
    elif fd notin eq.waiters or event.lpOverlapped != addr(eq.waiters[fd].overlapped[]):
      # The event might have been emitted by an usage of the handle for
      # overlapped operations outside of this queue or was emitted by
      # the use of a duplicate of the handle.
      #
      # Luckily, since IOCP is indexed by operations, we have a pretty solid
      # chance of not having a false positive (our queue holds the memory of
      # any registered operation, so they can't be emitted by anything else),
      # however lower throughput (due to interrupts from stray handles) will
      # happen as a result.
      discard
    else:
      # This is the operation we were waiting for, add its continuation to
      # runnable then remove it from the queue.
      runnable.add eq.waiters[fd].cont
      eq.waiters.del fd

using c: Continuation

proc wait*(c; fd: AnyFD, overlapped: ref Overlapped): Continuation {.cpsMagic.} =
  ## Wait for the operation associated with `overlapped` to finish.
  ##
  ## Only one continuation can be queued for any given `fd` per thread. If more
  ## than one is queued, ValueError will be raised. This limitation is temporary
  ## and will be lifted in the future.
  ##
  ## **Notes**:
  ## - The `fd` passed will be registered into IOCP and will cause interrupts
  ##   even if `wait` is not used for further usage of the `fd`. Therefore it is
  ##   advised to only use this procedure if all overlapped operations on this
  ##   `fd` will be done via the queue.
  ##
  ## - The `fd` should be unregistered before closing so that resources associated
  ##   with any pending operations are released.
  ##
  ## **Tips**: For submitting the `Overlapped` structure via an operation in
  ## the first place, just create a `ref Overlapped`, fill it with information
  ## as needed, then passes its address as the `lpOverlapped` parameter.
  bind init
  init()

  let fd =
    when fd is FD:
      fd
    else:
      FD(fd)

  # If the fd is already registered for an another operation
  if fd in eq.waiters:
    # Raise an error
    #
    # This will be temporary until we drafted out the semantics for these.
    raise newException(ValueError, $Error.QueuedFD % $fd.int)

  # Register the handle with IOCP
  if CreateIoCompletionPort(
    wincore.Handle(fd), wincore.Handle(eq.iocp.get), ULongPtr(fd), 0
  ) == wincore.Handle(0):
    raise newOSError(GetLastError(), $Error.Queue)

  eq.waiters[fd] = Waiter(cont: c, overlapped: overlapped)

proc unregister(fd: AnyFD) {.used.} =
  ## See the documentation of `ioqueue.unregister()`
  bind running
  if not running(): return

  let fd =
    when fd is FD:
      fd
    else:
      FD(fd)

  if fd in eq.waiters:
    let overlappedAddr = addr eq.waiters[fd].overlapped[]

    # Cancel the pending IO request
    if CancelIoEx(wincore.Handle(fd), overlappedAddr) == 0:
      let errorCode = GetLastError()
      # If cancel said the request cannot be found, then it's probably finished
      # and will be collected by the next poll()
      if errorCode == ErrorNotFound:
        discard
      else:
        raise newOSError(errorCode, $Error.Unregister)

    # Move the waiter to cancel queue. We index this queue with the pointer so
    # that we can safely index it with arbitrary `ptr Overlapped` coming from
    # the kernel.
    eq.cancelled[overlappedAddr] = move eq.waiters[fd]
    eq.waiters.del fd
