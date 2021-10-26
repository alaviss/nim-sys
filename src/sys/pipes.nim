#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Abstractions for operating system pipes and FIFOs (named pipes).

import system except File
import std/typetraits
import files

const
  ErrorPipeCreation = "Could not create pipe"
    ## Error message used when pipe creation fails.

type
  AsyncReadPipe* = distinct AsyncFile
    ## The type used for the asynchronous read end of the pipe.

  ReadPipe* = distinct File
    ## The type used for the synchronous read end of the pipe.

  AsyncWritePipe* = distinct AsyncFile
    ## The type used for the asynchronous write end of the pipe.

  WritePipe* = distinct File
    ## The type used for the synchronous write end of the pipe.

  AnyReadPipe* = AsyncReadPipe or ReadPipe
    ## Typeclass for all `ReadPipe` variants.

  AnyWritePipe* = AsyncWritePipe or WritePipe
    ## Typeclass for all `WritePipe` variants.

  AnyPipe* = AnyReadPipe or AnyWritePipe
    ## Typeclass for all `Pipe` variants.

when defined(posix):
  include private/pipes_posix
elif defined(windows):
  include private/pipes_windows
else:
  {.error: "This module has not been ported to your operating system.".}

proc newPipe*(Rd: typedesc[AnyReadPipe] = ReadPipe,
              Wr: typedesc[AnyWritePipe] = WritePipe,
              flags: set[FileFlag] = {}): tuple[rd: Rd, wr: Wr] =
  ## Creates a new anonymous pipe.
  ##
  ## Returns a tuple containing the read and write endpoints of the pipe. The
  ## generic parameters `Rd` and `Wr` dictate the type of the endpoints.
  ##
  ## For usage as standard input/output for child processes, it is recommended
  ## to use a synchronous pipe endpoint. The parent may use either an
  ## asynchronous or synchronous endpoint at their discretion. See the section
  ## below for more details.
  ##
  ## Only the flag `ffInheritable` is supported.
  ##
  ## **Platform specific details**
  ##
  ## - On Windows, this function is implemented using an uniquely named pipe,
  ##   where the server handle is always the read handle, and the write
  ##   handle is always the client. The server-client distinction doesn't
  ##   matter for most usage, however.
  ##
  ## - On Windows, the asynchronous handles are created with
  ##   `FILE_FLAG_OVERLAPPED` set, which require "overlapped" operations to be
  ##   done on them (it is possible to perform "non-overlapped" I/O on them,
  ##   but it is dangerous_). Passing them to a process not expecting
  ##   asynchronous I/O is discouraged.
  ##
  ## - On POSIX, while the asynchronous handles can always be used
  ##   synchronously in certain programs (ie. by loop on `EAGAIN`), it is
  ##   at the cost of multiple syscalls instead of one single blocking syscall.
  ##   Passing them to a process not expecting asynchronous I/O will result in
  ##   reduced performance.
  ##
  ## .. _dangerous: https://devblogs.microsoft.com/oldnewthing/20121012-00/?p=6343
  newPipeImpl()

proc newAsyncPipe*(flags: set[FileFlag] = {}): tuple[rd: AsyncReadPipe,
                                                     wr: AsyncWritePipe]
                  {.inline.} =
  ## A shortcut for creating an anonymous pipe with both ends being
  ## asynchronous.
  ##
  ## Asynchronous pipe endpoints should only be passed to processes that are
  ## aware of them.
  ##
  ## See
  ## `newPipe() <#newPipe,typedesc[AnyReadPipe],typedesc[AnyWritePipe],set[FileFlag]>`_
  ## for more details.
  newPipe(AsyncReadPipe, AsyncWritePipe, flags)

template close*(p: AnyPipe) =
  ## Closes and invalidates the pipe endpoint `p`.
  ##
  ## This procedure is borrowed from
  ## `files.close() <files.html#close,AnyFile>`_. See the borrowed symbol's
  ## documentation for more details.
  close distinctBase(typeof p) p

template fd*(p: AnyPipe): FD =
  ## Returns the file handle held by `p`.
  ##
  ## This procedure is borrowed from `files.fd() <files.html#fd,AnyFile>`_.
  ## See the borrowed symbol's documentation for more details.
  fd distinctBase(typeof p) p

template takeFD*(p: AnyPipe): FD =
  ## Returns the file handle held by `p` and release ownership to the caller.
  ## `p` will then be invalidated.
  ##
  ## This procedure is borrowed from
  ## `files.takeFD() <files.html#takeFD,AnyFile>`_. See the borrowed symbol's
  ## documentation for more details.
  takeFd distinctBase(typeof p) p

template read*[T: byte or char](rp: ReadPipe, b: var openArray[T]): int =
  ## Reads up to `b.len` bytes from pipe `rp` into `b`.
  ##
  ## This procedure is borrowed from
  ## `files.read() <files.html#read,File,openArray[T]>`_. See the borrowed
  ## symbol's documentation for more details.
  read distinctBase(typeof rp) rp, b

template read*(rp: AsyncReadPipe, buf: ptr UncheckedArray[byte],
               bufLen: Natural): int =
  ## Reads up to `bufLen` bytes from pipe `rp` into `buf`.
  ##
  ## This procedure is borrowed from
  ## `files.read() <files.html#read,AsyncFile,ptr.UncheckedArray[byte],Natural>`_.
  ## See the borrowed symbol's documentation for more details.
  read distinctBase(typeof rp) rp, buf, bufLen

template read*[T: string or seq[byte]](rp: AsyncReadPipe, b: ref T): int =
  ## Reads up to `b.len` bytes from pipe `rp` into `b`.
  ##
  ## This procedure is borrowed from
  ## `files.read() <files.html#read,AsyncFile,ref.string>`_. See the borrowed
  ## symbol's documentation for more details.
  read distinctBase(typeof rp) rp, b

template write*[T: byte or char](wp: WritePipe, b: openArray[T]): int =
  ## Writes the contents of array `b` into the pipe `wp`.
  ##
  ## This procedure is borrowed from
  ## `files.write() <files.html#write,File,openArray[T]>`_. See the borrowed
  ## symbol's documentation for more details.
  write distinctBase(typeof wp) wp, b

template write*(wp: AsyncWritePipe, buf: ptr UncheckedArray[byte],
                bufLen: Natural): int =
  ## Writes `bufLen` bytes from the buffer pointed to by `buf` into the pipe
  ## `wp`.
  ##
  ## This procedure is borrowed from
  ## `files.write() <files.html#write,AsyncFile,ptr.UncheckedArray[byte],Natural>`_.
  ## See the borrowed symbol's documentation for more details.
  write distinctBase(typeof wp) wp, buf, bufLen

template write*[T: string or seq[byte]](wp: AsyncWritePipe, b: T): int =
  ## Writes the contents of array `b` into the pipe `wp`. `b` will be copied.
  ##
  ## This procedure is borrowed from
  ## `files.write() <files.html#write,AsyncFile,string>`_. See the borrowed
  ## symbol's documentation for more details.
  write distinctBase(typeof wp) wp, b

template write*[T: string or seq[byte]](wp: AsyncWritePipe, b: ref T): int =
  ## Writes the contents of array `b` into the pipe `wp`.
  ##
  ## This procedure is borrowed from
  ## `files.write() <files.html#write,AsyncFile,ref.string>`_. See the borrowed
  ## symbol's documentation for more details.
  write distinctBase(typeof wp) wp, b
