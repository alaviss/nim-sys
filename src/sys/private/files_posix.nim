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

template commonReadImpl(result: var int, fd: cint, buf: ptr UncheckedArray[byte],
                        bufLen: Natural, onNonBlock: untyped) =
  # While the buffer is not filled
  while result < bufLen:
    # Read more into it
    let bytesRead = read(fd, addr buf[result], bufLen - result)
    # If more than 0 bytes is read
    if bytesRead > 0:
      # Add it to the total bytes read and do it again
      result.inc bytesRead

    # If none is read, then the buffer reached EOF, return
    elif bytesRead == 0:
      break

    # If there is an error but it's not due to a signal interruption
    elif errno != EINTR:
      # On the event that the FD is non-blocking and is exhausted
      if errno == EAGAIN or errno == EWOULDBLOCK:
        # Run user's code
        onNonBlock

      # Raise an error if not interrupted
      raise newIOError(result, errno, ErrorRead)

template readImpl() {.dirty.} =
  commonReadImpl(result, cint(f.fd),
                 cast[ptr UncheckedArray[byte]](addr b[0]), b.len):
    discard "blocking read on non-blocking file is a bug"

template asyncReadImpl() {.dirty.} =
  commonReadImpl(result, cint(f.fd), buf, bufLen):
    # Queue a wait on the event that the FD is exhausted.
    wait f.fd, Read
    # Move to the next iteration so that the `raise` won't trigger.
    continue

template commonWriteImpl(fd: cint, buf: ptr UncheckedArray[byte],
                         bufLen: Natural, onNonBlock: untyped) =
  var totalWritten = 0
  # While the entire buffer is not written
  while totalWritten < bufLen:
    # Write it to `f`
    let bytesWritten = write(fd, addr buf[totalWritten],
                             bufLen - totalWritten)
    # If we managed to write some bytes
    if bytesWritten > 0:
      # Add it to the total
      totalWritten.inc bytesWritten

    elif bytesWritten == 0:
      # On POSIX, a non-zero write will never yield 0 as a result, so this
      # is a form of sanity check.
      doAssert false, "write() returned zero for non-zero request"

    # If there is an error that's not due to signal interruption
    elif errno != EINTR:
      # On the event that the FD is non-blocking and is exhausted
      if errno == EAGAIN or errno == EWOULDBLOCK:
        # Run user's code
        onNonBlock

      # Raise an error if not interrupted
      raise newIOError(totalWritten, errno, ErrorWrite)

template writeImpl() {.dirty.} =
  commonWriteImpl(cint(f.fd), cast[ptr UncheckedArray[byte]](unsafeAddr b[0]),
                  b.len):
    discard "blocking write on non-blocking file is a bug"

template asyncWriteImpl() {.dirty.} =
  commonWriteImpl(cint(f.fd), buf, bufLen):
    # Queue a wait on the event that the FD is exhausted.
    wait f.fd, Write
    # Move to the next iteration so that the `raise` won't trigger.
    continue
