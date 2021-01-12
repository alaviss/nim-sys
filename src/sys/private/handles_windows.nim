#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import syscall/winim/winim/core as wincore except Handle

type FDImpl = wincore.Handle

template closeImpl() {.dirty.} =
  when fd is SocketFD:
    closesocket wincore.Handle(fd)
  else:
    CloseHandle wincore.Handle(fd)

template setInheritableImpl() {.dirty.} =
  when fd is FD:
    if not SetHandleInformation(fd.FDImpl, HandleFlagInherit, 0):
      raise newOsError(GetLastError().int32, ErrorSetInheritable)
  else:
    {.error: "setInheritable is not available for this variant of FD".}
