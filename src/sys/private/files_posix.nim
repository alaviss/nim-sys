#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import syscall/posix

type
  FileImpl = object
    handle: Handle[FD]

template cleanupFile(f: untyped) =
  when f is AsyncFileImpl or f is AsyncFile:
    # XXX: `!=` doesn't work here, probably a compiler bug
    if not (f.handle.get == InvalidFD):
      unregister AsyncFD f.handle.get

template closeImpl() {.dirty.} =
  cleanupFile f
  close f.handle

template destroyFileImpl() {.dirty.} =
  cleanupFile f
  `=destroy` f.handle

template newFileImpl() {.dirty.} =
  result = File(handle: initHandle(fd))

template newAsyncFileImpl() {.dirty.} =
  result = AsyncFile newFile(fd)
  if result.handle.get != InvalidFD:
    register result.handle.get.AsyncFD

template getFDImpl() {.dirty.} =
  result = get f.handle

template takeFDImpl() {.dirty.} =
  cleanupFile f
  result = take f.handle

template readImpl() {.dirty.} =
  while result < b.len:
    let bytesRead = read(f.handle.get.cint, addr b[result],
                         b.len - result)
    if bytesRead > 0:
      result.inc bytesRead
    elif bytesRead == 0:
      break
    elif errno != EINTR and errno != EAGAIN:
      raise newIOError(result, errno, ErrorRead)

template asyncReadImpl() {.dirty.} =
  assert b != nil, "The provided buffer is nil"

  result = newFuture[int]("files.read")

  let future = result
  var totalRead = 0

  proc doRead(fd: AsyncFD): bool =
    while totalRead < b.len:
      let bytesRead = read(fd.cint, addr b[totalRead], b.len - totalRead)
      if bytesRead > 0:
        totalRead.inc bytesRead
      elif bytesRead == 0:
        break
      elif errno == EAGAIN or errno == EINTR:
        return false
      else:
        future.fail newIOError(totalRead, errno, ErrorRead)
        break

    result = true
    if not future.finished:
      future.complete totalRead

  if not f.handle.get.AsyncFD.doRead():
    f.handle.get.AsyncFD.addRead doRead

template writeImpl() {.dirty.} =
  var totalWritten = 0
  while totalWritten < b.len:
    let bytesWritten = write(f.handle.get.cint, unsafeAddr b[totalWritten],
                             b.len - totalWritten)
    if bytesWritten > 0:
      totalWritten.inc bytesWritten
    elif bytesWritten == 0:
      doAssert false, "write() returned zero for non-zero request"
    elif errno != EINTR and errno != EAGAIN:
      raise newIOError(totalWritten, errno, ErrorWrite)

template asyncWriteImpl() {.dirty.} =
  result = newFuture[void]("files.write")
  let future = result
  var totalWritten = 0

  proc doWrite(fd: AsyncFD): bool =
    while totalWritten < b.len:
      let bytesWritten = write(fd.cint, unsafeAddr b[totalWritten],
                               b.len - totalWritten)
      if bytesWritten > 0:
        totalWritten.inc bytesWritten
      elif bytesWritten == 0:
        doAssert false, "write() returned zero for non-zero request"
      elif errno == EAGAIN or errno == EINTR:
        return false
      else:
        future.fail newIOError(totalWritten, errno, ErrorWrite)
        break

    result = true
    if not future.finished:
      complete future

  if not f.handle.get.AsyncFD.doWrite():
    f.handle.get.AsyncFD.addWrite doWrite
