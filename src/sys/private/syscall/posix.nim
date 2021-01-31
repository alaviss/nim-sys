#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

# Seems to be a compiler bug, it shouldn't trigger unused imports for this line.
import std/posix as std_posix
export std_posix

# XXX: Remove when we fully replace std/posix
{.used.}

## This module provides additional declaration not available in stdlib posix
## module.
##
## Most of these declarations are OS-specific. Use `when declared()` to check
## whether the symbol is available on the target operating system.

when defined(bsd) or defined(linux) or defined(macosx):
  let FIOCLEX* {.importc, header: "<sys/ioctl.h>".}: culong
  let FIONCLEX* {.importc, header: "<sys/ioctl.h>".}: culong

when defined(bsd) or defined(linux):
  proc dup3*(oldfd, newfd, flags: cint): cint {.importc, header: "<unistd.h>".}
  proc pipe2*(pipefd: var array[2, cint],
              flags: cint): cint {.importc, header: "<unistd.h>".}

when defined(linux):
  const
    CLONE_VM* = 0x100
    CLONE_VFORK* = 0x4000

  proc clone*(fn: proc (arg: pointer): cint {.cdecl.}, stack: pointer,
              flags: cint, arg: pointer): cint
             {.varargs, importc, header: "<sched.h>".}
