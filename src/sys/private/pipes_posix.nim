#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import syscall/posix
import errors, ".." / handles

template commonInit(p, newFileProc: untyped, inheritable, blocking: bool) =
  ## Common implementation for init*Pipe(). Assumes that `p` is empty.
  var handles: array[2, cint]
  when declared(pipe2):
    var flags = 0.cint
    if not inheritable:
      flags = flags or O_CLOEXEC
    if not blocking:
      flags = flags or O_NONBLOCK

    posixChk pipe2(handles, flags), ErrorPipeCreation
  else:
    posixChk pipe(handles), ErrorPipeCreation

    template setFlags(fd: untyped) =
      if not inheritable:
        fd.setInheritable(inheritable)

      if not blocking:
        fd.setBlocking(blocking)

    setFlags(handles[0].FD)
    setFlags(handles[1].FD)

  p.rd = newFileProc(handles[0].FD)
  p.wr = newFileProc(handles[1].FD)

template initPipeImpl() {.dirty.} =
  commonInit(result, initFile,
             inheritable = ffInheritable in flags, blocking = true)

template newPipeImpl() {.dirty.} =
  commonInit(result, newFile,
             inheritable = ffInheritable in flags, blocking = true)

template initAsyncPipeImpl() {.dirty.} =
  commonInit(result, initAsyncFile,
             inheritable = ffInheritable in flags, blocking = false)

template newAsyncPipeImpl() {.dirty.} =
  commonInit(result, newAsyncFile,
             inheritable = ffInheritable in flags, blocking = false)
