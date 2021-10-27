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
    unregister f.handle

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

template getFDImpl() {.dirty.} =
  result = get f.handle

template takeFDImpl() {.dirty.} =
  cleanupFile f
  result = take f.handle

proc commonRead(fd: FD, buf: pointer, len: Natural): int {.inline.} =
  ## A wrapper around posix.read() to retry on EINTR.
  result = retryOnEIntr: read(cint(fd), buf, len)

template readImpl() {.dirty.} =
  let bytesRead =
    if b.len > 0:
      commonRead(f.fd, addr b[0], b.len)
    else:
      commonRead(f.fd, nil, 0)

  # In case of an error, raise
  if bytesRead == -1:
    raise newIOError(0, errno, ErrorRead)

  result = bytesRead

template asyncReadImpl() {.dirty.} =
  while true:
    let bytesRead = commonRead(f.fd, buf, bufLen)

    # In case of an error
    if bytesRead == -1:
      # If the operation can not be done now
      if errno == EAGAIN or errno == EWOULDBLOCK:
        # Wait until it can be done and try again.
        wait f.fd, Read

      else:
        raise newIOError(0, errno, ErrorRead)

    # Otherwise the operation is completed
    else:
      return bytesRead

proc commonWrite(fd: FD, buf: pointer, len: Natural): int {.inline.} =
  ## A wrapper around posix.write() to retry on EINTR.
  result = retryOnEIntr: write(cint(fd), buf, len)

template writeImpl() {.dirty.} =
  let bytesWritten =
    if b.len > 0:
      commonWrite(f.fd, unsafeAddr b[0], b.len)
    else:
      commonWrite(f.fd, nil, 0)

  # In case of an error, raise
  if bytesWritten == -1:
    raise newIOError(0, errno, ErrorWrite)

  result = bytesWritten

template asyncWriteImpl() {.dirty.} =
  while true:
    let bytesWritten = commonWrite(f.fd, buf, bufLen)

    # In case of an error
    if bytesWritten == -1:
      # If the operation can not be done now
      if errno == EAGAIN or errno == EWOULDBLOCK:
        # Wait until it can be done and try again.
        wait f.fd, Write

      else:
        raise newIOError(0, errno, ErrorWrite)

    # Otherwise the operation is completed
    else:
      return bytesWritten
