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
  when f is AsyncFile:
    unregister AsyncFD f.handle.get

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
  if fd != InvalidFD:
    register fd.AsyncFD

template getFDImpl() {.dirty.} =
  result = get f.handle

template takeFDImpl() {.dirty.} =
  cleanupFile f
  result = take f.handle

template readImpl() {.dirty.} =
  while result < b.len:
    var bytesRead: DWORD
    # Windows DWORD is 32 bits, where Nim's int can be 64 bits, so the
    # operation has to be broken down into smaller chunks.
    let
      toRead = DWORD min(b.len - result, high DWORD)
      success = ReadFile(wincore.Handle f.handle.get, addr b[result], toRead,
                         addr bytesRead, nil)

    result.inc bytesRead

    if success == 0:
      let errorCode = GetLastError()
      if errorCode == ErrorBrokenPipe:
        # Treat a closed pipe as EOF
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

proc setPos(overlapped: CustomRef, pos: uint64) {.inline.} =
  overlapped.offset = DWORD(pos and high uint32)
  overlapped.offsetHigh = DWORD(pos shr 32)

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

template asyncReadImpl() {.dirty.} =
  assert b != nil, "The provided buffer is nil"

  result = newFuture[int]("files.read")
  let future = result
  var totalRead: int

  proc doRead() =
    let overlapped = newCustom()
    overlapped.data = CompletionData(fd: AsyncFD f.handle.get)
    overlapped.data.cb =
      proc (fd: AsyncFD, bytesTransferred: DWORD, errcode: OSErrorCode) =
        if not future.finished:
          totalRead.inc bytesTransferred
          if f.File.seekable:
            f.File.pos.checkedInc bytesTransferred

          if errcode.int32 == -1i32:
            # As with the synchronous version, the operation might have been
            # broken down into smaller chunks. In that case it is called again
            # to read the rest of the requested bytes.
            if bytesTransferred == high(DWORD) and totalRead < b.len:
              doRead()
              return
          elif errcode.int32 == ErrorBrokenPipe:
            discard "Treat closed pipe as EOF"
          else:
            future.fail(newIOError(totalRead, errcode.int32, ErrorRead))
            return

          future.complete(totalRead)

    if f.File.seekable:
      overlapped.setPos f.File.pos

    let toRead = DWORD min(b.len - totalRead, high DWORD)
    # TODO: If an operation that can be completed immediately errors, would
    # it be possible that some bytes has been transferred? If so, can be
    # retrieve this number?
    if ReadFile(wincore.Handle f.handle.get, addr b[totalRead], toRead,
                nil, cast[LPOverlapped](addr overlapped[])) == 0:
      let errorCode = GetLastError()
      if errorCode != ErrorIoPending:
        # newCustom() add one reference on creation as the object
        # need to stay alive until asyncdispatch receives it from IOCP.
        #
        # However the object will not be posted on IOCP if the operation fails,
        # so this extra reference has to be removed.
        GcUnref overlapped
        if errorCode == ErrorHandleEof or errorCode == ErrorBrokenPipe:
          # Do not raise any error on end-of-file
          future.complete(totalRead)
        else:
          future.fail(newIOError(totalRead, errorCode, ErrorRead))
    else:
      # The read completed immediately, however it is not possible to safely
      # collect the result early via `GetOverlappedResult()` since an event
      # handle was not employed.
      discard

  doRead()

template writeImpl() {.dirty.} =
  var totalWritten: int
  while totalWritten < b.len:
    var bytesWritten: DWORD
    let
      toWrite = DWORD min(b.len - totalWritten, high DWORD)
      success = WriteFile(wincore.Handle f.handle.get,
                          unsafeAddr b[totalWritten], toWrite,
                          addr bytesWritten, nil)

    totalWritten.inc bytesWritten

    if success == 0:
      raise newIOError(totalWritten, GetLastError(), ErrorWrite)
    elif bytesWritten < high(DWORD):
      # See readImpl() for the rationale. Though, in the case of writes,
      # it is possible for a successful operation to write less than
      # the requested amount, if the handle in question is a PIPE_NOWAIT
      # pipe handle, but that type of handle has been deprecated a long time
      # ago.
      doAssert b.len == totalWritten, "not all of the provided buffer has been written"
      break
    else:
      doAssert false, "unreachable!"

template asyncWriteImpl() {.dirty.} =
  result = newFuture[void]("files.write")
  let future = result
  var totalWritten: int

  proc doWrite() =
    let overlapped = newCustom()
    overlapped.data = CompletionData(fd: AsyncFD f.handle.get)
    overlapped.data.cb =
      proc (fd: AsyncFD, bytesTransferred: DWORD, errcode: OSErrorCode) =
        if not future.finished:
          totalWritten.inc bytesTransferred

          if errcode.int == -1:
            if f.File.seekable:
              f.File.pos.checkedInc bytesTransferred

            # See writeImpl() for more details regarding these conditionals.
            if bytesTransferred == high(DWORD):
              doWrite()
              return

            doAssert b.len == totalWritten, "not all of the provided buffer has been written"
          else:
            future.fail(newIOError(totalWritten, errcode.int32, ErrorWrite))
            return

          future.complete()

    if f.File.seekable:
      overlapped.setPos f.File.pos

    let toWrite = DWORD min(b.len - totalWritten, high DWORD)
    # TODO: see asyncReadImpl() for potential caveats.
    if WriteFile(wincore.Handle f.handle.get, unsafeAddr b[totalWritten],
                 toWrite, nil, cast[LPOverlapped](addr overlapped[])) == 0:
      let errorCode = GetLastError()
      if errorCode != ErrorIoPending:
        GcUnref overlapped
        if errorCode == ErrorHandleEof:
          future.complete()
        else:
          future.fail(newIOError(totalWritten, errorCode, ErrorWrite))
    else:
      discard

  doWrite()
