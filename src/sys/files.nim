#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import system except io
import handles

type
  File* {.requiresInit.} = object
    ## An object representing a file
    fd: Handle[FD] ## The file handle

  AsyncFile* {.borrow: `.`.} = distinct File
    ## The type used for files opened in asynchronous mode

  FileFlag* = enum
    ## Flags that controls file behaviors.
    ffRead         ## Open file for reading
    ffWrite        ## Open file for writing
    ffAppend       ## Append to the end-of-file
    ffTruncate     ## Truncate file when opening
    ffInheritable  ## Allow file handle to be inherited automatically by
                   ## child processes.

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

proc initAsyncFile*(fd: FD): AsyncFile {.inline.} =
  ## Creates a new `AsyncFile` object from an opened file handle.
  ##
  ## The ownership of the file handle will be transferred to the resulting
  ## `AsyncFile`.
  ##
  ## **Note**: No attempts are made to verify whether the file handle has
  ## been opened in asynchronous mode.
  AsyncFile initFile(fd)

proc newAsyncFile*(fd: FD): ref AsyncFile {.inline.} =
  ## Creates a new `ref AsyncFile` object from an opened file handle.
  ##
  ## The ownership of the file handle will be transferred to the resulting
  ## `ref AsyncFile`.
  ##
  ## **Note**: No attempts are made to verify whether the file handle has
  ## been opened in asynchronous mode.
  (ref AsyncFile) newFile(fd)
