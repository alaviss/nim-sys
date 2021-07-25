#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## A mini asyncio library for testing the eventqueue.

import std/posix
import pkg/cps
import sys/[files, handles, ioqueue]

import ".."/helpers/handles as helper_handle

{.experimental: "implicitDeref".}

proc newAsyncPipe*(): tuple[rd, wr: ref Handle[FD]] =
  var (rd, wr) = helper_handle.pipe()

  rd.setBlocking(false)
  wr.setBlocking(false)

  result = (newHandle(rd), newHandle(wr))

proc write*[T: byte or char](fd: Handle[FD], data: openArray[T]) =
  ## Write all bytes in `data` into `fd`.
  var totalWritten = 0
  while totalWritten < data.len:
    let written = write(fd.get.cint, data[totalWritten].unsafeAddr, data.len - totalWritten)
    case written
    of -1:
      raise newIOError(totalWritten, errno.int32)
    else:
      totalWritten += written

proc read*[T: byte or char](fd: Handle[FD], buf: var openArray[T]): int =
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
