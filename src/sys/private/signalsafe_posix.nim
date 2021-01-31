#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Async-signal-safe helpers

import syscall/posix

{.push stacktrace: off.} ## Avoid modifying globals

proc setInheritable*(fd: cint, inheritable: bool): bool =
  ## Set `fd` inheritable attribute via `fcntl`.
  ##
  ## Returns `false` on failure.
  var fdFlags = fcntl(fd.cint, F_GETFD)
  if fdFlags == -1:
    return
  if inheritable:
    fdFlags = fdFlags and not FD_CLOEXEC
  else:
    fdFlags = fdFlags or FD_CLOEXEC
  if fcntl(fd.cint, F_SETFD, fdFlags) == -1:
    return
  result = true

proc duplicateTo*(fd: cint, target: cint, inheritable = false): bool =
  ## Duplicate `fd` to `target`.
  ##
  ## Returns `false` on failure.
  if inheritable:
    return dup2(fd, target) != -1
  else:
    when defined(openbsd):
      return dup3(fd, target, O_CLOEXEC)
    else:
      if dup2(fd, target) == -1:
        return false
      return setInheritable(target, inheritable)

{.pop.}
