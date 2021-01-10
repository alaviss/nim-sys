#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import syscall/posix

proc read[T: byte or char](f: File, b: var openArray[T]): int =
  while result < b.len:
    let bytesRead = read(f.fd.get.cint, addr b[result], b.len - result)
    if bytesRead > 0:
      result.inc bytesRead
    elif bytesRead == 0:
      break
    elif errno != EINTR and errno != EAGAIN:
      raise newIOError(result, errno, ErrorRead)

proc read*[T: string or seq[byte]](f: AsyncFile, b: ref T): Future[int] =
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

  if not f.fd.get.AsyncFD.doRead():
    f.fd.get.AsyncFD.addRead doRead

proc write[T: byte or char](f: File, b: openArray[T]) =
  var totalWritten = 0
  while totalWritten < b.len:
    let bytesWritten = write(f.fd.get.cint, unsafeAddr b[totalWritten],
                             b.len - totalWritten)
    if bytesWritten > 0:
      totalWritten.inc bytesWritten
    elif bytesWritten == 0:
      doAssert false, "write() returned zero for non-zero request"
    elif errno != EINTR and errno != EAGAIN:
      raise newIOError(totalWritten, errno, ErrorWrite)

proc write[T: string or seq[byte]](f: AsyncFile, b: T): Future[void] =
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

  if not f.fd.get.AsyncFD.doWrite():
    f.fd.get.AsyncFD.addWrite doWrite
