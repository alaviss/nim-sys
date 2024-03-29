#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import system except io
import handles, ioqueue
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
  File* = ref FileImpl
    ## An object representing a file. This is an opaque object with
    ## differing implementations depending on the target operating system.

  AsyncFileImpl {.borrow: `.`.} = distinct FileImpl
    ## A distinct type derived from FileImpl so that we can assign a custom
    ## destructor.

  AsyncFile* = ref AsyncFileImpl
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
  result[].initIOError(bytesTransferred, errorCode, additionalInfo)

proc `=copy`*(dest: var FileImpl, src: FileImpl) {.error.}
  ## Copying a `File` is not allowed. If multiple references to the same file
  ## are wanted, consider using `ref File`.

proc close*(f: AnyFile) =
  ## Closes and invalidates the file `f`.
  ##
  ## If `f` is invalid, `ClosedHandleDefect` will be raised.
  ##
  ## If `f` is a AsyncFile, it will be deregistered from the queue before
  ## closing.
  closeImpl()

when declared(destroyFileImpl):
  # XXX: Have to be declared separately due to nim-lang/Nim#16668
  proc `=destroy`(f: var FileImpl) =
    ## Default destructor for all File-derived types.
    ##
    ## Exposing this allows OS-specific implementations to override the default
    ## destructor as needed.
    destroyFileImpl()

  proc `=destroy`(f: var AsyncFileImpl) =
    ## Default destructor for all File-derived types.
    ##
    ## Exposing this allows OS-specific implementations to override the default
    ## destructor as needed.
    destroyFileImpl()

proc newFile*(fd: FD): File =
  ## Creates a new `ref File` from an opened file handle.
  ##
  ## The ownership of the file handle will be transferred to the resulting
  ## `ref File`.
  ##
  ## **Note**: It is assumed that the file handle has been opened in
  ## synchronous mode. Only use this interface if you know what you are doing.
  newFileImpl()

proc newAsyncFile*(fd: FD): AsyncFile =
  ## Creates a new `ref AsyncFile` object from an opened file handle.
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

proc takeFD*(f: AnyFile): FD {.inline.} =
  ## Returns the file handle held by `f` and release ownership to the caller.
  ## `f` will then be invalidated.
  ##
  ## On POSIX systems, the handle will be unregistered from the global
  ## dispatcher if `f` is an `AsyncFile`.
  takeFDImpl()

proc read*[T: byte or char](f: File, b: var openArray[T]): int
                           {.raises: [IOError].} =
  ## Reads up to `b.len` bytes from file `f` into `b`.
  ##
  ## If the file position is at the end-of-file, no data will be read and
  ## no error will be raised.
  ##
  ## If `f` is a pipe and the write end has been closed, no data will be read
  ## and no error will be raised.
  ##
  ## Returns the number of bytes read from `f`.
  ##
  ## **Platform specific details**
  ##
  ## - On POSIX systems, signals will not interrupt the operation if nothing
  ##   was read.
  readImpl()

proc read*(f: AsyncFile, buf: ptr UncheckedArray[byte],
           bufLen: Natural): int {.asyncio.} =
  ## Reads up to `bufLen` bytes from file `f` into `buf`.
  ##
  ## `buf` might be `nil` only if `bufLen` is `0`.
  ##
  ## `buf` must stays alive for the duration of the read. Direct usage of this
  ## interface is discouraged due to its unsafetyness. Users are encouraged to
  ## use high-level overloads that keep buffers alive.
  ##
  ## If the file position is at the end-of-file, no data will be read and
  ## no error will be raised.
  ##
  ## If `f` is a pipe and the write end has been closed, no data will be read
  ## and no error will be raised.
  ##
  ## This function is not thread-safe.
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
  ##   required, it is recommended to use `File` with threads or carefully
  ##   evaluate the limitations.
  ##
  ## - On POSIX systems, disk IOs are **never** asynchronous. This is an
  ##   unfortunate property of the specification. It is recommended to use
  ##   `File` with threads for those use cases. This might change in the future.
  ##
  ## - On POSIX systems, signals will not interrupt the operation.
  ##
  ## .. _article: https://docs.microsoft.com/en-us/troubleshoot/windows/win32/asynchronous-disk-io-synchronous
  if buf == nil and bufLen != 0:
    raise newException(ValueError, "A buffer must be provided for request of size > 0")
  asyncReadImpl()

proc read*(f: AsyncFile, b: ref string): int {.asyncio.} =
  ## Reads up to `b.len` bytes from file `f` into `b`.
  ##
  ## This is an overload of
  ## `read() <#read,AsyncFile,ptr.UncheckedArray[byte],Natural>`_, please refer
  ## to its documentation for more information.
  assert(not b.isNil, "The provided buffer must not be nil")
  if b[].len > 0:
    read(f, cast[ptr UncheckedArray[byte]](addr b[][0]), b[].len)
  else:
    read(f, nil, 0)

proc read*(f: AsyncFile, b: ref seq[byte]): int {.asyncio.} =
  ## Reads up to `b.len` bytes from file `f` into `b`.
  ##
  ## This is an overload of
  ## `read() <#read,AsyncFile,ptr.UncheckedArray[byte],Natural>`_, please refer
  ## to its documentation for more information.
  assert(not b.isNil, "The provided buffer must not be nil")
  if b[].len > 0:
    read(f, cast[ptr UncheckedArray[byte]](addr b[][0]), b[].len)
  else:
    read(f, nil, 0)

proc write*[T: byte or char](f: File, b: openArray[T]): int {.raises: [IOError].} =
  ## Writes the contents of array `b` into file `f`.
  ##
  ## Returns the number of bytes written to `f`.
  ##
  ## **Platform specific details**
  ##
  ## - On POSIX systems, signals will not interrupt the operation if nothing
  ##   was written.
  writeImpl()

proc write*(f: AsyncFile, buf: ptr UncheckedArray[byte],
            bufLen: Natural): int {.asyncio.} =
  ## Writes `bufLen` bytes from the buffer pointed to by `buf` to `f`.
  ##
  ## `buf` might be `nil` only if `bufLen` is `0`.
  ##
  ## `buf` must stays alive for the duration of the read. Direct usage of this
  ## interface is discouraged due to its unsafetyness. Users are encouraged to
  ## use high-level overloads that keep buffers alive.
  ##
  ## This function is not thread-safe.
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
  ##   required, it is recommended to use `File` with threads or carefully
  ##   evaluate the limitations.
  ##
  ## - On POSIX systems, disk IOs are **never** asynchronous. This is an
  ##   unfortunate property of the specification. It is recommended to use
  ##   `File` with threads for those use cases. This might change in the future.
  ##
  ## - On POSIX systems, signals will not interrupt the operation.
  ##
  ## .. _article: https://docs.microsoft.com/en-us/troubleshoot/windows/win32/asynchronous-disk-io-synchronous
  if buf == nil and bufLen != 0:
    raise newException(ValueError, "A buffer must be provided for request of size > 0")

  asyncWriteImpl()

proc write*(f: AsyncFile, b: string): int {.asyncio.} =
  ## Writes the contents of array `b` into file `f`. The contents of `b` will
  ## be copied. Consider the `ref` overload to avoid copies.
  ##
  ## This is an overload of
  ## `write() <#write,AsyncFile,ptr.UncheckedArray[byte],Natural>`_, please
  ## refer to its documentation for more information.
  if b.len > 0:
    write(f, cast[ptr UncheckedArray[byte]](unsafeAddr b[0]), b.len)
  else:
    write(f, nil, 0)

proc write*(f: AsyncFile, b: ref string): int {.asyncio.} =
  ## Writes the contents of array `b` into file `f`.
  ##
  ## This is an overload of
  ## `write() <#write,AsyncFile,ptr.UncheckedArray[byte],Natural>`_, please
  ## refer to its documentation for more information.
  assert(not b.isNil, "The provided buffer must not be nil")
  if b[].len > 0:
    write(f, cast[ptr UncheckedArray[byte]](addr b[][0]), b[].len)
  else:
    write(f, nil, 0)

proc write*(f: AsyncFile, b: seq[byte]): int {.asyncio.} =
  ## Writes the contents of array `b` into file `f`. The contents of `b` will
  ## be copied. Consider the `ref` overload to avoid copies.
  ##
  ## This is an overload of
  ## `write() <#write,AsyncFile,ptr.UncheckedArray[byte],Natural>`_, please
  ## refer to its documentation for more information.
  if b.len > 0:
    write(f, cast[ptr UncheckedArray[byte]](unsafeAddr b[0]), b.len)
  else:
    write(f, nil, 0)

proc write*(f: AsyncFile, b: ref seq[byte]): int {.asyncio.} =
  ## Writes the contents of array `b` into file `f`.
  ##
  ## This is an overload of
  ## `write() <#write,AsyncFile,ptr.UncheckedArray[byte],Natural>`_, please
  ## refer to its documentation for more information.
  assert(not b.isNil, "The provided buffer must not be nil")
  if b[].len > 0:
    write(f, cast[ptr UncheckedArray[byte]](addr b[][0]), b[].len)
  else:
    write(f, nil, 0)
