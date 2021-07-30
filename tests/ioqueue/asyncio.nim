#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## A mini asyncio library for testing the eventqueue.

when defined(posix):
  import sys/private/syscall/posix
  import ".."/helpers/handles as helper_handle
else:
  import sys/private/syscall/winim/winim except Handle

import pkg/cps
import sys/[files, handles, ioqueue]

{.experimental: "implicitDeref".}

proc newAsyncPipe*(): tuple[rd, wr: ref Handle[FD]] =
  when defined(posix):
    var (rd, wr) = helper_handle.pipe()

    rd.setBlocking(false)
    wr.setBlocking(false)

    result = (newHandle(rd), newHandle(wr))
  else:
    let pipeName = r"\\.\pipe\nim-sys-test-" & $GetCurrentProcessID()
    let rd = CreateNamedPipeA(
      cstring(pipeName),
      dwOpenMode = PipeAccessInbound or
        FileFlagFirstPipeInstance or FileFlagOverlapped,
      dwPipeMode = PipeTypeByte or PipeWait or PipeRejectRemoteClients,
      nMaxInstances = 1,
      nOutBufferSize = 0,
      nInBufferSize = 0,
      nDefaultTimeout = 0,
      nil
    )
    doAssert rd != InvalidHandleValue, "pipe creation failed"
    let wr = CreateFileA(
      cstring(pipeName), GenericWrite, dwShareMode = 0, nil, OpenExisting,
      FileFlagOverlapped, winim.Handle(0)
    )
    doAssert wr != InvalidHandleValue, "pipe creation failed"

when defined(windows):
  {.pragma: sync, error: "not supported on this os".}
else:
  {.pragma: sync.}

proc write*[T: byte or char](fd: Handle[FD], data: openArray[T]) {.sync.} =
  ## Write all bytes in `data` into `fd`.
  var totalWritten = 0
  while totalWritten < data.len:
    let written = write(fd.get.cint, data[totalWritten].unsafeAddr, data.len - totalWritten)
    case written
    of -1:
      raise newIOError(totalWritten, errno.int32)
    else:
      totalWritten += written

proc read*[T: byte or char](fd: Handle[FD], buf: var openArray[T]): int {.sync.} =
  ## Read all bytes from `fd` into `buf` until it's filled or there is
  ## nothing left to read
  while result < buf.len:
    let readBytes = read(fd.get.cint, buf[result].addr, buf.len - result)
    case readBytes
    of -1:
      raise newIOError(result, errno.int32)
    of 0:
      break
    else:
      result += readBytes

proc readAsync*(rd: ref Handle[FD], buf: ref string) {.cps: Continuation.} =
  ## Read data from `rd` until `buf` is filled or there is nothing else
  ## to be read, asynchronously.
  ##
  ## After finished, `buf` will be set to the length of the data received.
  ## It is done like this since our dispatcher don't provide tracking
  ## information outside of cps yet
  when defined(windows):
    let overlapped = new Overlapped
    debugEcho "initiating read"
    if ReadFile(
      winim.Handle(rd.get), addr buf[0], DWORD(buf.len), nil,
      addr overlapped[]
    ) == winim.FALSE:
      let errorCode = GetLastError()
      debugEcho "read errored with ", errorCode
      if errorCode == ErrorIoPending:
        wait(rd.get, overlapped)
      else:
        discard "Error handling below"
    debugEcho "read completed"
    let errorCode = DWORD(overlapped.Internal)
    let read = DWORD(overlapped.InternalHigh)
    if errorCode != ErrorSuccess or errorCode != ErrorHandleEof:
      raise newIOError(read, errorCode)

    buf.setLen read
  else:
    var offset = 0
    while offset < buf.len:
      try:
        let read = read(rd, buf.toOpenArray(offset, buf.len - 1))
        buf.setLen offset + read
        break
      except files.IOError as e:
        # Add the offset so we know where exactly we are
        e.bytesTransferred += offset
        if e.errorCode == EAGAIN:
          offset = e.bytesTransferred
          wait rd.get, Read
        else:
          raise e

proc writeAsync*(wr: ref Handle[FD], buf: string) {.cps: Continuation.} =
  ## Write all bytes in `buf` into `wr` asynchronously
  when defined(windows):
    let overlapped = new Overlapped
    if WriteFile(
      winim.Handle(wr.get), unsafeAddr buf[0], DWORD(buf.len), nil,
      addr overlapped[]
    ) == winim.FALSE:
      let errorCode = GetLastError()
      if errorCode == ErrorIoPending:
        wait(wr.get, overlapped)
      else:
        discard "Error handling below"
    let errorCode = DWORD(overlapped.Internal)
    let written = DWORD(overlapped.InternalHigh)
    if errorCode != ErrorSuccess:
      raise newIOError(written, errorCode)
  else:
    var offset = 0
    while offset < buf.len:
      try:
        write(wr, buf.toOpenArray(offset, buf.len - 1))
        break
      except files.IOError as e:
        # Add the offset so we know where exactly we are
        e.bytesTransferred += offset
        if e.errorCode == EAGAIN:
          offset = e.bytesTransferred
          wait wr.get, Write
        else:
          raise e
