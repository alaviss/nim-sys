#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Abstractions for operating system pipes and FIFOs (named pipes).

import system except File
import files

const
  ErrorPipeCreation = "Could not create pipe"
    ## Error message used when pipe creation fails.

when defined(posix):
  include private/pipes_posix
elif defined(windows):
  include private/pipes_windows
else:
  {.error: "This module has not been ported to your operating system.".}

proc newPipe*(Rd: typedesc[AnyFile] = File, Wr: typedesc[AnyFile] = File,
              flags: set[FileFlag] = {}): tuple[rd: Rd, wr: Wr] =
  ## Creates a new anonymous pipe.
  ##
  ## Returns a tuple containing the read and write endpoints of the pipe. The
  ## generic parameters `Rd` and `Wr` dictates the type of the endpoints.
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

proc newAsyncPipe*(flags: set[FileFlag] = {}): tuple[rd, wr: AsyncFile]
                  {.inline.} =
  ## A shortcut for creating an anonymous pipe with both ends being
  ## asynchronous.
  ##
  ## Asynchronous pipe endpoints should only be passed to processes that are
  ## aware of them.
  ##
  ## See `newPipe() <#newPipe,typedesc[AnyFile],typedesc[AnyFile],set[FileFlag]>`_
  ## for more details.
  newPipe(AsyncFile, AsyncFile, flags)
