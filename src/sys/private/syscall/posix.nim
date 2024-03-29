#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

# Seems to be a compiler bug, it shouldn't trigger unused imports for this line.
import std/posix as std_posix
export std_posix except In6Addr, Sockaddr_in6

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
  let SOCK_NONBLOCK* {.importc, header: "<sys/socket.h>".}: cint

  proc dup3*(oldfd, newfd, flags: cint): cint {.importc, header: "<unistd.h>".}
  proc pipe2*(pipefd: var array[2, cint],
              flags: cint): cint {.importc, header: "<unistd.h>".}

type
  # Overrides the std/posix version to fix the type.
  In6Addr* {.importc: "struct in6_addr", pure, final,
             header: "<netinet/in.h>".} = object
    s6_addr*: array[16, byte]

  In6AddrOrig* = std_posix.In6Addr

  # Fix the wrong types in std/posix
  Sockaddr_in6* {.importc: "struct sockaddr_in6", pure,
                  header: "<netinet/in.h>".} = object
    sin6_family*: TSa_Family
    sin6_port*: InPort
    sin6_flowinfo*: uint32
    sin6_addr*: In6Addr
    sin6_scope_id*: uint32

template retryOnEIntr*(op: untyped): untyped =
  ## Given a POSIX operation that returns `-1` on error, automatically retry it
  ## if the error was `EINTR`.
  var result: typeof(op)
  while true:
    result = op

    if cint(result) == -1 and errno == EINTR:
      discard "Got interrupted, try again"
    else:
      break

  result
