#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## This module contains abstractions for testing plain handles/fds.
##
## Unlike other abstractions provided by the project, these procs have no
## behavioral guarantees, and will die of fatal error if the OS decides that
## it doesn't want to cooperate.

when defined(posix):
  import sys/private/syscall/posix
else:
  import pkg/winim/lean

from sys/handles as sys_handles import FD

proc pipe*(): (FD, FD) =
  ## Create a pipe pair, useful for testing auto close as they don't require
  ## temporary files.
  when defined(posix):
    var handles: array[2, cint]
    doAssert pipe(handles) != -1, "pipe creation failed"
    result = (FD handles[0], FD handles[1])
  else:
    var rd, wr: Handle
    doAssert CreatePipe(addr rd, addr wr, nil, 0) != 0, "pipe creation failed"
    result = (FD rd, FD wr)

proc isValid*(fd: FD): bool =
  ## Check if FD is still valid
  when defined(posix):
    fcntl(fd.cint, F_GETFD) != -1
  else:
    var flags: DWORD
    GetHandleInformation(fd.Handle, addr flags) != 0

proc duplicate*(fd: FD): FD =
  when defined(posix):
    result = FD dup(fd.cint)
    doAssert result.cint != -1, "duplicating fd failed"
  else:
    let currentProcess = GetCurrentProcess()
    doAssert DuplicateHandle(
      currentProcess, fd.Handle, currentProcess, cast[ptr Handle](addr result),
      dwDesiredAccess = 0, bInheritHandle = 1, DuplicateSameAccess
    ) != 0, "duplicating fd failed"
