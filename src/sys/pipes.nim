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

proc newPipe*(flags: set[FileFlag] = {}): tuple[rd, wr: File] =
  ## Creates a new anonymous pipe as references.
  ##
  ## Returns a tuple containing the read and write endpoints of the pipe.
  ##
  ## Only the flag `ffInheritable` is supported.
  newPipeImpl()

proc newAsyncPipe*(flags: set[FileFlag] = {}): tuple[rd, wr: AsyncFile] =
  ## Creates a new asynchrounous anonymous pipe as references.
  ##
  ## Returns a tuple containing the read and write endpoints of the pipe.
  ##
  ## Only the flag `ffInheritable` is supported.
  ##
  ## **Note**: The returned handles are not recommended for use as standard
  ## input, output or error for child processes. See the following section
  ## for more details.
  ##
  ## **Platform specific details**
  ##
  ## - On Windows, this function is implemented using an uniquely named pipe,
  ##   where the server handle is always the read handle, and the write
  ##   handle is always the client. The server-client distinction doesn't
  ##   matter for most usage, however.
  ##
  ## - On Windows, the handles are created with `FILE_FLAG_OVERLAPPED` set,
  ##   which require "overlapped" operations to be done on them (it is possible
  ##   to perform "non-overlapped" I/O on them, but it is dangerous_).
  ##   Passing them to a process not expecting asynchronous I/O is
  ##   discouraged.
  ##
  ## - On POSIX, the handles can be used synchronously for correctly written
  ##   programs, at the cost of multiple syscalls instead of a single blocking
  ##   syscall.
  ##
  ## .. _dangerous: https://devblogs.microsoft.com/oldnewthing/20121012-00/?p=6343
  newAsyncPipeImpl()
