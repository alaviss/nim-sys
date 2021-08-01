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

template commonReadImpl(result: var int, fd: FD,
                        buf: ptr UncheckedArray[byte], bufLen: Natural,
                        async: static[bool] = false) =
  # The overlapped pointer, we only set this if we are doing async
  let overlapped: ref Overlapped =
    when async:
      new Overlapped
    else:
      nil

  while result < bufLen:
    # Windows DWORD is 32 bits, where Nim's int can be 64 bits, so the
    # operation has to be broken down into smaller chunks.
    let toRead = DWORD min(bufLen - result, high DWORD)

    when async:
      # Initialize the overlapped object for I/O.
      f.File.initOverlapped(overlapped[])

    var
      # The amount read by the operation.
      bytesRead: DWORD
      # The error code from the operation.
      errorCode: DWORD

    if ReadFile(
      wincore.Handle(fd), addr buf[result], toRead, addr bytesRead,
      cast[ptr Overlapped](overlapped)
    ) == wincore.FALSE:
      # The operation failed, set the error code.
      errorCode = GetLastError()

    when async:
      # If the operation is executing asynchronously.
      if errorCode == ErrorIoPending:
        # Wait for it to finish.
        wait(fd, overlapped)
        # Fill the correct data from the overlapped object.
        errorCode = DWORD overlapped.Internal
        bytesRead = DWORD overlapped.InternalHigh

      # If `f` is seekable, it means we are tracking the position data ourselves.
      if f.seekable:
        # Move the position forward.
        f.pos.checkedInc bytesRead

    # Increase total number of bytes read.
    result.inc bytesRead

    if errorCode != ErrorSuccess:
      # If the pipe is broken (for read it means the write end is closed) or
      # if EOF is returned.
      if errorCode == ErrorBrokenPipe or errorCode == ErrorHandleEof:
        # We can stop here.
        break
      else:
        raise newIOError(result, errorCode, ErrorRead)
    elif bytesRead < high(DWORD):
      # As ReadFile() only return true when either EOF happened or all
      # requested bytes has been read, if the amount of bytes read did not
      # reach the upper boundary (which would signify a broken down
      # operation), there is no need for retries.
      break
    else:
      doAssert false, "unreachable!"

template readImpl() {.dirty.} =
  commonReadImpl(result, f.fd, cast[ptr UncheckedArray[byte]](addr b[0]),
                 b.len, async = false)

template asyncReadImpl() {.dirty.} =
  commonReadImpl(result, f.fd, buf, bufLen, async = true)

template commonWriteImpl(fd: FD, buf: ptr UncheckedArray[byte], bufLen: Natural,
                         async: static[bool] = false) =
  # The overlapped pointer, we only set this if we are doing async
  let overlapped: ref Overlapped =
    when async:
      new Overlapped
    else:
      nil

  var totalWritten: int
  while totalWritten < bufLen:
    # Windows DWORD is 32 bits, where Nim's int can be 64 bits, so the
    # operation has to be broken down into smaller chunks.
    let toWrite = DWORD min(bufLen - totalWritten, high DWORD)

    when async:
      # Initialize the overlapped object for I/O.
      f.File.initOverlapped(overlapped[])

    var
      # The amount read by the operation.
      bytesWritten: DWORD
      # The error code from the operation.
      errorCode: DWORD

    if WriteFile(
      wincore.Handle(fd), addr buf[totalWritten], toWrite, addr bytesWritten,
      cast[ptr Overlapped](overlapped)
    ) == wincore.FALSE:
      # The operation failed, set the error code.
      errorCode = GetLastError()

    when async:
      # If the operation is executing asynchronously.
      if errorCode == ErrorIoPending:
        # Wait for it to finish.
        wait(fd, overlapped)
        # Fill the correct data from the overlapped object.
        errorCode = DWORD overlapped.Internal
        bytesWritten = DWORD overlapped.InternalHigh

      # If `f` is seekable, it means we are tracking the position data ourselves.
      if f.seekable:
        # Move the position forward.
        f.pos.checkedInc bytesWritten

    # Increase total number of bytes written.
    totalWritten.inc bytesWritten

    if errorCode != ErrorSuccess:
      raise newIOError(totalWritten, errorCode, ErrorWrite)
    elif bytesWritten < high(DWORD):
      # See readImpl() for the rationale. Though, in the case of writes,
      # it is possible for a successful operation to write less than
      # the requested amount, if the handle in question is a PIPE_NOWAIT
      # pipe handle, but that type of handle has been deprecated a long time
      # ago.
      doAssert bufLen == totalWritten, "not all of the provided buffer has been written"
      break
    else:
      doAssert false, "unreachable!"

template writeImpl() {.dirty.} =
  commonWriteImpl(f.fd, cast[ptr UncheckedArray[byte]](unsafeAddr b[0]), b.len,
                  async = false)

template asyncWriteImpl() {.dirty.} =
  commonWriteImpl(f.fd, buf, bufLen, async = true)
