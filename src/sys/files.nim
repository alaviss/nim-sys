#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

{.experimental: "implicitDeref".}

import system except io
import std/asyncdispatch
import handles
import private/errors

const
  ErrorRead = "Could not read from file"
    ## Error message used when reading fails.

  ErrorWrite = "Could not write to file"
    ## Error message used when writing fails.

when defined(posix):
  include private/files_posix
elif defined(windows):
  include private/files_windows
else:
  {.error: "This module has not been ported to your operating system.".}

type
  File* {.requiresInit.} = FileImpl
    ## An object representing a file. This is an opaque object with
    ## differing implementations depending on the target operating system.

  AsyncFile* {.borrow: `.`.} = distinct File
    ## The type used for files opened in asynchronous mode.

  AnyFile* = File or AsyncFile
    ## Typeclass for all `File` variants.

  FileFlag* = enum
    ## Flags that control file behaviors.
    ffRead         ## Open file for reading.
    ffWrite        ## Open file for writing.
    ffAppend       ## When writing, append data to end-of-file.
    ffTruncate     ## Truncate file when opening.
    ffInheritable  ## Allow file handle to be inherited automatically by
                   ## child processes.

  IOError* = object of OSError
    ## Raised if an IO error occurred.
    bytesTransferred*: Natural ## Number of bytes transferred before the error.

proc initIOError*(e: var IOError, bytesTransferred: Natural, errorCode: int32,
                  additionalInfo = "") {.inline.} =
  ## Initializes an IOError object.
  e.initOSError(errorCode, additionalInfo)
  e.bytesTransferred = bytesTransferred

proc newIOError*(bytesTransferred: Natural, errorCode: int32,
                 additionalInfo = ""): ref IOError =
  ## Creates a new `ref IOError`.
  result = new IOError
  result.initIOError(bytesTransferred, errorCode, additionalInfo)

proc `=copy`*(dest: var FileImpl, src: FileImpl) {.error.}
  ## Copying a `File` is not allowed. If multiple references to the same file
  ## are wanted, consider using `ref File`.

proc close*(f: var AnyFile) =
  ## Closes and invalidates the file `f`.
  ##
  ## If `f` is invalid, `ClosedHandleDefect` will be raised.
  closeImpl()

when declared(destroyFileImpl):
  # XXX: Have to be declared separately due to nim-lang/Nim#16668
  proc `=destroy`(f: var FileImpl) =
    ## Default destructor for all File-derived types.
    ##
    ## Exposing this allows OS-specific implementations to override the default
    ## destructor as needed.
    destroyFileImpl()

  proc `=destroy`(f: var AsyncFile) =
    ## Default destructor for all File-derived types.
    ##
    ## Exposing this allows OS-specific implementations to override the default
    ## destructor as needed.
    destroyFileImpl()

proc initFile*(fd: FD): File =
  ## Creates a new `File` object from an opened file handle.
  ##
  ## The ownership of the file handle will be transferred to the resulting
  ## `File`.
  ##
  ## **Note**: Only use this interface if you know what you are doing.
  initFileImpl()

proc newFile*(fd: FD): ref File =
  ## Creates a new `ref File` from an opened file handle.
  ##
  ## The ownership of the file handle will be transferred to the resulting
  ## `ref File`.
  ##
  ## **Note**: Only use this interface if you know what you are doing.
  newFileImpl()

proc initAsyncFile*(fd: FD): AsyncFile =
  ## Creates a new `AsyncFile` object from an opened file handle. `fd` will be
  ## registered with the global dispatcher.
  ##
  ## The ownership of the file handle will be transferred to the resulting
  ## `AsyncFile`.
  ##
  ## **Note**: It is assumed that the file handle has been opened in
  ## asynchronous mode. Only use this interface if you know what you are doing.
  ##
  ## **Platform specific details**
  ##
  ## - On Windows, the file position will always start at the beginning of the
  ##   file if the file is seekable.
  initAsyncFileImpl()

proc newAsyncFile*(fd: FD): ref AsyncFile =
  ## Creates a new `ref AsyncFile` object from an opened file handle.
  ##
  ## On POSIX systems, `fd` will be registered with the global dispatcher.
  ##
  ## The ownership of the file handle will be transferred to the resulting
  ## `ref AsyncFile`.
  ##
  ## **Note**: It is assumed that the file handle has been opened in
  ## asynchronous mode. Only use this interface if you know what you are doing.
  ##
  ## **Platform specific details**
  ##
  ## - On Windows, the file position will always start at the beginning of the
  ##   file if the file is seekable.
  newAsyncFileImpl()

func fd*(f: AnyFile): FD {.inline.} =
  ## Returns the file handle held by `f`.
  ##
  ## The returned `FD` will stay valid for the duration of `f`.
  getFDImpl()

proc takeFD*(f: var AnyFile): FD {.inline.} =
  ## Returns the file handle held by `f` and release ownership to the caller.
  ## `f` will then be invalidated.
  ##
  ## On POSIX systems, the handle will be unregistered from the global
  ## dispatcher if `f` is an `AsyncFile`.
  takeFDImpl()

proc read*[T: byte or char](f: File, b: var openArray[T]): int
                           {.raises: [IOError].} =
  ## Reads `b.len` bytes from file `f` into `b`. Data may be written
  ## into `b` even when an error occurs. The IOError thrown will contain
  ## the number of bytes read thus far.
  ##
  ## This function will read until `b` is filled or the end-of-file has
  ## been reached.
  ##
  ## If the file position is at the end-of-file, no data will be read and
  ## no error will be raised.
  ##
  ## This function is not thread-safe.
  ##
  ## Returns the number of bytes read from `f`.
  readImpl()

proc read*[T: string or seq[byte]](f: AsyncFile, b: ref T): Future[int] =
  ## Reads `b.len` bytes from file `f` into `b`. Data may be written
  ## into `b` even when an error occurs. The IOError thrown will contain
  ## the number of bytes read thus far.
  ##
  ## This function will read until `b` is filled or the end-of-file has
  ## been reached.
  ##
  ## If the file position is at the end-of-file, no data will be read and
  ## no error will be raised.
  ##
  ## This function is not thread-safe, and the ordering of two concurrent async
  ## operations on the same file is undefined.
  ##
  ## Returns the number of bytes read from `f`.
  ##
  ## **Platform specific details**
  ##
  ## - On Windows, for seekable files, the file position is implemented by the
  ##   library and may overflow, though it is unlikely for that to happen due
  ##   to most file system having a maximum file size of 2^64.
  ##
  ##   If you have to deal with file systems where the maximum file size
  ##   exceeds that of conventional file systems, it is recommended to use
  ##   `File` with threads for asynchronous operations.
  ##
  ## - On Windows, most disk IOs are not asynchronous, see this article_
  ##   from Microsoft for more details. If asynchronous disk operations are
  ##   required, it is recommended to use `File` with threads.
  ##
  ## .. _article: https://docs.microsoft.com/en-us/troubleshoot/windows/win32/asynchronous-disk-io-synchronous
  asyncReadImpl()

proc write*[T: byte or char](f: File, b: openArray[T]) {.raises: [IOError].} =
  ## Writes the contents of array `b` into file `f`.
  ##
  ## This function is not thread-safe.
  writeImpl()

proc write*[T: string or seq[byte]](f: AsyncFile, b: T): Future[void] =
  ## Writes the contents of array `b` into file `f`.
  ##
  ## This function is not thread-safe, and the ordering of two concurrent async
  ## operations on the same file is undefined.
  ##
  ## **Platform specific details**
  ##
  ## - On Windows, for seekable files, the file position is implemented by the
  ##   library and may overflow, though it is unlikely for that to happen due
  ##   to most file system having a maximum file size of 2^64.
  ##
  ##   If you have to deal with file systems where the maximum file size
  ##   exceeds that of conventional file systems, it is recommended to use
  ##   `File` with threads for asynchronous operations.
  ##
  ## - On Windows, most disk IOs are not asynchronous, see this article_
  ##   from Microsoft for more details. If asynchronous disk operations are
  ##   required, it is recommended to use `File` with threads.
  ##
  ## .. _article: https://docs.microsoft.com/en-us/troubleshoot/windows/win32/asynchronous-disk-io-synchronous
  asyncWriteImpl()
