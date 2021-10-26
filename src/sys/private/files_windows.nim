#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#               (c) Copyright 2015 Dominik Picheta
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

from std/os import OSErrorCode
import syscall/winim/winim/core as wincore except Handle

type
  FileImpl = object
    handle: Handle[FD]

    # Only used for async files
    case seekable: bool
    of true:
      pos: uint64
    of false: discard

template cleanupFile(f: untyped) =
  when f is AsyncFile or f is AsyncFileImpl:
    unregister f.handle

template closeImpl() {.dirty.} =
  cleanupFile f
  close f.handle

template destroyFileImpl() {.dirty.} =
  cleanupFile f
  `=destroy` f.handle

template newFileImpl() {.dirty.} =
  # Seekable is not used for synchronous operations
  result = File(handle: initHandle(fd), seekable: false)

template newAsyncFileImpl() {.dirty.} =
  result = new AsyncFileImpl
  {.warning: "compiler bug workaround, see: https://github.com/nim-lang/Nim/issues/18570".}
  let fileImpl = FileImpl(
    handle: initHandle(fd),
    seekable: GetFileType(wincore.Handle fd) == FileTypeDisk
  )
  result[] = AsyncFileImpl fileImpl

template getFDImpl() {.dirty.} =
  result = get f.handle

template takeFDImpl() {.dirty.} =
  cleanupFile f
  result = take f.handle

proc initOverlapped(f: FileImpl, o: var Overlapped) {.inline.} =
  ## Initialize an overlapped object for I/O operations on `f`
  reset(o)
  if f.seekable:
    o.Offset = DWORD(f.pos and high uint32)
    o.OffsetHigh = DWORD(f.pos shr 32)

func checkedInc(u: var uint64, i: Natural) {.inline.} =
  ## Increment `u` by `i`, raises `OverflowDefect` if `u` overflows.
  ##
  ## As it is made for safe file position increments, the message is
  ## personalized for that purpose.
  {.push checks: on.}
  let orig = u
  u += i.uint64
  if u < orig:
    raise newException(OverflowDefect, "File position overflow")
  {.pop.}

func ioSize(x: int): DWORD {.inline.} =
  ## Limit `x` to the largest size that can be done with a Windows I/O operation
  DWORD min(x, high DWORD)

template handleReadResult(errorCode, bytesRead: DWORD) =
  ## Common bits for handling the result of a ReadFile() operation. This is to
  ## be used after the operation has fully completed.
  ##
  ## Raises if the result is considered an error.
  # In case of a broken pipe (write side closed), treat it as EOF
  if errorCode != ErrorSuccess:
    if errorCode == ErrorBrokenPipe or errorCode == ErrorHandleEof:
      discard "EOF reached"
    else:
      raise newIOError(bytesRead, errorCode, ErrorRead)

template readImpl() {.dirty.} =
  var bytesRead: DWORD

  if ReadFile(
    wincore.Handle(f.fd), addr(b[0]), ioSize(b.len), addr bytesRead, nil
  ) == wincore.FALSE:
    let errorCode = GetLastError()
    handleReadResult(errorCode, bytesRead)

  result = bytesRead

template asyncReadImpl() {.dirty.} =
  let overlapped = new Overlapped

  # Prepare the OVERLAPPED structure
  f.File.initOverlapped(overlapped[])

  var errorCode: DWORD = ErrorSuccess

  if ReadFile(
    wincore.Handle(f.fd), buf, ioSize(bufLen), nil,
    cast[ptr Overlapped](addr overlapped[])
  ) == wincore.FALSE:
    errorCode = GetLastError()

  # If the operation is completing asynchronously
  if errorCode == ErrorIoPending:
    # Wait for it to finish
    wait(f.fd, overlapped)

  # Get the result data from the overlapped object
  errorCode = DWORD overlapped.Internal
  let bytesRead = DWORD overlapped.InternalHigh

  # If `f` is seekable
  if f.seekable:
    # Move the position forward.
    f.pos.checkedInc bytesRead

  handleReadResult(errorCode, bytesRead)

  result = bytesRead

template writeImpl() {.dirty.} =
  var bytesWritten: DWORD

  if WriteFile(
    wincore.Handle(f.fd), unsafeAddr(b[0]), ioSize(b.len), addr bytesWritten, nil
  ) == wincore.FALSE:
    raise newIOError(bytesWritten, GetLastError(), ErrorWrite)

  result = bytesWritten

template asyncWriteImpl() {.dirty.} =
  let overlapped = new Overlapped

  # Prepare the OVERLAPPED structure
  f.File.initOverlapped(overlapped[])

  var errorCode: DWORD = ErrorSuccess

  if WriteFile(
    wincore.Handle(f.fd), buf, ioSize(bufLen), nil,
    cast[ptr Overlapped](addr overlapped[])
  ) == wincore.FALSE:
    errorCode = GetLastError()

  # If the operation is completing asynchronously
  if errorCode == ErrorIoPending:
    # Wait for it to finish
    wait(f.fd, overlapped)

  # Get the result data from the overlapped object
  errorCode = DWORD overlapped.Internal
  let bytesWritten = DWORD overlapped.InternalHigh

  # If `f` is seekable
  if f.seekable:
    # Move the position forward.
    f.pos.checkedInc bytesWritten

  # If the operation failed, raise
  if errorCode != ErrorSuccess:
    raise newIOError(bytesWritten, errorCode, ErrorRead)

  result = bytesWritten
