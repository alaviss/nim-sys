#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import syscall/posix
import errors, ".." / handles

template newPipeImpl() {.dirty.} =
  var handles: array[2, cint]
  let inheritable = ffInheritable in flags
  when declared(pipe2):
    var flags = 0.cint
    if not inheritable:
      flags = flags or O_CLOEXEC

    posixChk pipe2(handles, flags), ErrorPipeCreation
  else:
    posixChk pipe(handles), ErrorPipeCreation

    setInheritable FD(handles[0]), inheritable
    setInheritable FD(handles[1]), inheritable

  when Rd is AsyncReadPipe:
    setBlocking FD(handles[0]), false

  when Wr is AsyncWritePipe:
    setBlocking FD(handles[1]), false

  result.rd =
    when Rd is ReadPipe:
      ReadPipe newFile(FD handles[0])
    else:
      AsyncReadPipe newAsyncFile(FD handles[0])
  result.wr =
    when Wr is WritePipe:
      WritePipe newFile(FD handles[1])
    else:
      AsyncWritePipe newAsyncFile(FD handles[1])
