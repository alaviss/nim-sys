#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import errors, syscall/posix

type
  FDImpl = cint
    ## The native implementation of FD.

template closeImpl() {.dirty.} =
  # The handle should be closed on any other error for most POSIX systems (sans
  # HP-UX, which leave the handle dangling on EINTR, but it's not supported
  # at the moment).
  if close(fd.cint) == -1 and errno == EBADF:
    raiseClosedHandleDefect()

template setInheritableImpl() {.dirty.} =
  when declared(FIOCLEX) and declared(FIONCLEX):
    if inheritable:
      posixChk ioctl(fd.cint, FIONCLEX), ErrorSetInheritable
    else:
      posixChk ioctl(fd.cint, FIOCLEX), ErrorSetInheritable
  else:
    var fdFlags = fcntl(fd.cint, F_GETFD)
    posixChk fdFlags, ErrorSetInheritable
    if inheritable:
      fdFlags = fdFlags and not FD_CLOEXEC
    else:
      fdFlags = fdFlags or FD_CLOEXEC
    posixChk fcntl(fd.cint, F_SETFD, fdFlags), ErrorSetInheritable

template setBlockingImpl() {.dirty.} =
  var flags = fcntl(fd.cint, F_GETFL)
  posixChk flags, ErrorSetBlocking
  if blocking:
    flags = flags and not O_NONBLOCK
  else:
    flags = flags or O_NONBLOCK
  posixChk fcntl(fd.cint, F_SETFL, flags), ErrorSetBlocking

template getFdImpl() {.dirty.} =
  cast[T](cast[cuint](h.shiftedFd) - 1)

template setFdImpl() {.dirty.} =
  # The FD is casted to unsigned so that `high(cint)` can be mapped forward
  # correctly.
  #
  # As all architectures running Linux uses two's complement, this also handles
  # InvalidFD -> 0 correctly.
  h.shiftedFd = cast[FDImpl](cast[cuint](fd) + 1)

when false:
  # NOTE: Staged until process spawning is added.
  template duplicateImpl() {.dirty.} =
    if inheritable:
      result = fcntl(fd.cint, F_DUPFD, 0)
    else:
      result = fcntl(fd.cint, F_DUPFD_CLOEXEC, 0)

    posixChk result, ErrorDuplicate

  template duplicateToImpl() {.dirty.} =
    if inheritable:
      posixChk dup2(fd, target), ErrorDuplicate
    else:
      when declared(dup3):
        posixChk dup3(fd, target, O_CLOEXEC), ErrorDuplicate
      else:
        posixChk dup2(fd, target), ErrorDuplicate
        target.setInheritable(inheritable)
