#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import errors, syscall/posix

proc `=destroy`[T: AnyFD](h: var Handle[T]) {.inline.} =
  # While no conversions are necessary for the case of FD, it is
  # needed for SocketFD, so ignore the hint.
  {.push hint[ConvFromXToItselfNotNeeded]: off.}
  if h.fd.FD != InvalidFD:
    # NOTE: close() can return with an error or be interrupted
    # (EINTR), but in most *nix implementations (sans HP-UX), the
    # file descriptor is guaranteed to have been closed.
    #
    # According to POSIX, errors coming from close() should only be
    # used for diagnostic purposes, so it is discarded here.
    discard close h.fd.cint
    h.fd = InvalidFD
  {.pop.}

proc setInheritable(fd: AnyFD, inheritable: bool) =
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

proc setBlocking(fd: AnyFD, blocking: bool) =
  var flags = fcntl(fd.cint, F_GETFL)
  posixChk flags, ErrorSetBlocking
  if blocking:
    flags = flags and not O_NONBLOCK
  else:
    flags = flags or O_NONBLOCK
  posixChk fcntl(fd.cint, F_SETFL, flags), ErrorSetBlocking

proc duplicate[T: AnyFD](fd: T, inheritable: bool): T =
  if inheritable:
    result = fcntl(fd.cint, F_DUPFD, 0)
  else:
    result = fcntl(fd.cint, F_DUPFD_CLOEXEC, 0)

  posixChk result, ErrorDuplicate

proc duplicateTo[T: AnyFD](fd, target: T, inheritable: bool) =
  if inheritable:
    posixChk dup2(fd, target), ErrorDuplicate
  else:
    when declared(dup3):
      posixChk dup3(fd, target, O_CLOEXEC), ErrorDuplicate
    else:
      posixChk dup2(fd, target), ErrorDuplicate
      target.setInheritable(inheritable)
