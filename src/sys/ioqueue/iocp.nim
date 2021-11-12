#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import std/[tables, hashes, times, options, strutils, packedsets]
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
      registered: PackedSet[FD] ## The set of registered FDs.
      orphans: PackedSet[FD] ## The set of FDs that has been unregistered.
    of false:
      discard

  UnregisteredHandleDefect* = object of Defect
    ## A `wait(fd, overlapped)` was attempted before the fd is registered.
    ##
    ## If an operation is done before the fd is registered into the queue,
    ## the queue might not receive the completion result, causing spontaneous
    ## hangs.
    ##
    ## To avoid this, make sure that the fd is registered before performing
    ## any overlapped operation.

proc newUnregisteredHandleDefect*(): ref UnregisteredHandleDefect =
  newException(UnregisteredHandleDefect):
    "A resource handle was waited for completion before it was registered into the queue."

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
    wincore.Handle(eq.iocp.fd), addr eq.eventBuffer[0], ULONG(eq.eventBuffer.len),
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

proc persist(fd: AnyFD) {.raises: [OSError].} =
  ## See the documentation of `ioqueue.persist()`
  bind init
  init()

  let fd = FD fd

  # Skip the registation check via IOCP on release build as an optimization.
  when defined(release):
    if fd in eq.registered:
      return

  # Register the handle with IOCP
  if CreateIoCompletionPort(
    wincore.Handle(fd), wincore.Handle(eq.iocp.fd), ULongPtr(fd), 0
  ) == wincore.Handle(0):
    let errorCode = GetLastError()

    # If an FD is already registered into IOCP
    if errorCode == ErrorInvalidParameter and (fd in eq.registered or fd in eq.orphans):
      discard "already registered"
    else:
      raise newOSError(errorCode, $Error.Register)

  # If registration success but fd is already registered and was not unregistered
  elif fd in eq.registered:
    # TODO: Find a way to make PrematureCloseDefect accessible from this module...
    raise newException(Defect):
      "Resource id " & $fd.int & " was invalidated before its unregistered"

  # This is the first registration
  else:
    # Set its completion mode to not queue a completion packet on success
    #
    # This only has to be done once
    if SetFileCompletionNotificationModes(
      wincore.Handle(fd), FileSkipCompletionPortOnSuccess
    ) == wincore.FALSE:
      raise newOSError(GetLastError(), $Error.Register)

  # Add FD to the registered set
  eq.registered.incl fd

  # Remove FD from the orphans set
  eq.orphans.excl fd

using c: Continuation

proc wait*(c; fd: AnyFD, overlapped: ref Overlapped): Continuation {.cpsMagic.} =
  ## Wait for the operation associated with `overlapped` to finish.
  ##
  ## The `fd` must be registered via `persist()` with the queue before the
  ## operation associated with `overlapped` is done or there will be a high
  ## chance that the event will never arrive. A limited form of sanity check is
  ## available via `UnregisteredHandleDefect`.
  ##
  ## Only one continuation can be queued for any given `fd`. If more than one
  ## is queued, ValueError will be raised. This limitation might be lifted in
  ## the future.
  ##
  ## **Notes**:
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

  # If the fd is not registered
  if fd notin eq.registered:
    # Raise a defect
    raise newUnregisteredHandleDefect()

  eq.waiters[fd] = Waiter(cont: c, overlapped: overlapped)

proc wait*(c; handle: Handle[AnyFD], overlapped: ref Overlapped): Continuation {.cpsMagic.} =
  ## Wait for the operation associated with `overlapped` to finish.
  ##
  ## This is an overload of `wait <#wait,,AnyFD,ref.OVERLAPPED>`_ for use with
  ## `Handle[T]`.
  wait(c, handle.get, overlapped)

proc unregister(fd: AnyFD) {.used.} =
  ## See the documentation of `ioqueue.unregister()`
  bind running
  if not eq.initialized: return

  let fd =
    when fd is FD:
      fd
    else:
      FD(fd)

  # If fd is registered
  if fd in eq.registered:
    # Remove FD from registered set
    eq.registered.excl fd
    # Add FD to the orphans set instead
    eq.orphans.incl fd

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
