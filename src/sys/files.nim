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
import private/[errors, utils]

type
  File* {.requiresInit.} = object
    ## An object representing a file
    fd: Handle[FD] ## The file handle

  AsyncFile* {.borrow: `.`.} = distinct File
    ## The type used for files opened in asynchronous mode

  AnyFile* = File or AsyncFile
    ## Typeclass for all `File` variants

  FileFlag* = enum
    ## Flags that controls file behaviors.
    ffRead         ## Open file for reading
    ffWrite        ## Open file for writing
    ffAppend       ## Append to the end-of-file
    ffTruncate     ## Truncate file when opening
    ffInheritable  ## Allow file handle to be inherited automatically by
                   ## child processes.

  IOError* = object of OSError
    ## Raised if an IO error occurred
    bytesTransferred*: Natural ## Number of bytes transferred before the error

const
  ErrorRead = "Could not read from file"
    ## Error message used when reading fails

  ErrorWrite = "Could not write to file"
    ## Error message used when writing fails

proc initIOError*(e: var IOError, bytesTransferred: Natural, errorCode: int32,
                  additionalInfo = "") {.inline.} =
  ## Initializes an IOError object.
  e.initOSError(errorCode, additionalInfo)
  e.bytesTransferred = bytesTransferred

proc newIOError*(bytesTransferred: Natural, errorCode: int32,
                 additionalInfo = ""): ref IOError =
  result = new IOError
  result.initIOError(bytesTransferred, errorCode, additionalInfo)

proc `=copy`*(dest: var File, src: File) {.error.}
  ## Copying a File is not allowed. If multiple references to the same file
  ## is wanted, consider using `ref File`.

proc initFile*(fd: FD): File {.inline.} =
  ## Creates a new `File` object from an opened file handle.
  ##
  ## The ownership of the file handle will be transferred to the resulting
  ## `File`.
  File(fd: initHandle(fd))

proc newFile*(fd: FD): ref File {.inline.} =
  ## Creates an new `ref File` from an opened file handle.
  ##
  ## The ownership of the file handle will be transferred to the resulting
  ## `ref File`.
  (ref File)(fd: initHandle(fd))

proc `=destroy`(f: var AsyncFile) =
  if f.fd.get != InvalidFD:
    unregister f.fd.get.AsyncFD
    `=destroy` File(f)

proc initAsyncFile*(fd: FD): AsyncFile {.inline.} =
  ## Creates a new `AsyncFile` object from an opened file handle. The file
  ## handle will then be registered with the dispatcher.
  ##
  ## The ownership of the file handle will be transferred to the resulting
  ## `AsyncFile`.
  ##
  ## **Note**: No attempts are made to verify whether the file handle has
  ## been opened in asynchronous mode.
  result = AsyncFile initFile(fd)
  if result.fd.get != InvalidFD:
    register result.fd.get.AsyncFD

proc newAsyncFile*(fd: FD): ref AsyncFile {.inline.} =
  ## Creates a new `ref AsyncFile` object from an opened file handle. The file
  ## handle will then be registered with the dispatcher.
  ##
  ## The ownership of the file handle will be transferred to the resulting
  ## `ref AsyncFile`.
  ##
  ## **Note**: No attempts are made to verify whether the file handle has
  ## been opened in asynchronous mode.
  (ref AsyncFile) newFile(fd)

proc close*(f: var AnyFile) {.inline.} =
  ## Closes and invalidates the file `f`.
  ##
  ## If `f` is invalid, `ClosedHandleDefect` will be raised.
  `=destroy` f

proc fd*(f: AnyFile): FD {.inline.} =
  ## Returns the file handle opened by `f`.
  ##
  ## The returned `FD` will stay alive for the duration of `f`.
  f.fd.get

proc takeFD*(f: var AnyFile): FD {.inline.} =
  ## Release the file handle owned by `f`.
  f.fd.take
  when f is AsyncFile:
    unregister f.fd.AsyncFD

proc read*[T: byte or char](f: File, b: var openArray[T]): int
                           {.docForward, raises: [IOError].} =
  ## Reads `b.len` bytes from file `f` into `b`. Data will be written
  ## into `b` even when an error occurs. The IOError thrown will contain
  ## the number of bytes read then.
  ##
  ## The function shall read until `b` is filled or the end-of-file has
  ## been reached.
  ##
  ## If the file position is at the end-of-file, no data will be written into
  ## `b` and the function returns 0.
  ##
  ## Returns the number of bytes read from `f`.

proc read*[T: string or seq[byte]](f: AsyncFile, b: ref T): Future[int]
                                  {.docForward.} =
  ## Reads `b.len` bytes from file `f` into `b`. Data will be written
  ## into `b` even when an error occurs. The IOError thrown will contain
  ## the number of bytes read then.
  ##
  ## The function shall read until `b.len` bytes has been read or the
  ## end-of-file has been reached.
  ##
  ## If the file position is at the end-of-file, no data will be written into
  ## `b` and the function returns 0.
  ##
  ## Returns the number of bytes read from `f`.

proc write*[T: byte or char](f: File, b: openArray[T])
           {.docForward, raises: [IOError].} =
  ## Writes the contents of array `b` into file `f`.

proc write*[T: string or seq[byte]](f: AsyncFile, b: T): Future[void]
           {.docForward.} =
  ## Writes the contents of array `b` into file `f`.

when defined(nimdoc):
  discard "Hide implementation from nim doc"
elif defined(posix):
  include private/files_posix
else:
  {.error: "This module has not been ported to your operating system.".}
