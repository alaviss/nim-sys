#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Wrappers for Linux-specific epoll.
##
## The `epoll_` and `EPOLL` prefixes are removed.

import ".."/".."/".."/handles

type
  Data* {.bycopy, union.} = object
    `ptr`*: pointer
    fd*: cint
    u32*: uint32
    u64*: uint64

  Ev* = distinct uint32
    ## Type used for `epoll` events.

when defined(amd64):
  type
    Event* {.bycopy, packed.} = object
      events*: Ev
      data*: Data
else:
  type
    Event* {.bycopy.} = object
      events*: Ev
      data*: Data

type
  CtlOp* = distinct cint
    ## Type used for `epoll_ctl` operations.

  FD* = distinct handles.FD
    ## Type used for Epoll FDs

const
  CtlAdd* = 1.CtlOp
  CtlDel* = 2.CtlOp
  CtlMod* = 3.CtlOp

  EvIn* = 0x001.Ev
  EvPri* = 0x002.Ev
  EvOut* = 0x004.Ev
  EvRdNorm* = 0x040.Ev
  EvNVal* = 0x020.Ev
  EvRdBand* = 0x080.Ev
  EvWrNorm* = 0x100.Ev
  EvWrBand* = 0x200.Ev
  EvMsg* = 0x400.Ev
  EvErr* = 0x008.Ev
  EvHup* = 0x010.Ev
  EvRdHup* = 0x2000.Ev
  EvExclusive* = Ev(1u32 shl 28)
  EvWakeUp* = Ev(1u32 shl 29)
  EvOneshot* = Ev(1u32 shl 30)
  EvET* = Ev(1u32 shl 31)

func `or`*(a, b: Ev): Ev {.borrow.}
  ## Bitwise OR operator for Ev

func `and`*(a, b: Ev): Ev {.borrow.}
  ## Bitwise AND operator for Ev

func `not`*(x: Ev): Ev {.borrow.}
  ## Bitwise NOT operator for Ev

func has*(a, b: Ev): bool {.inline.} =
  ## Check if `b` is in `a`
  (a and b).uint32 != 0u32

converter toFD*(epfd: FD): handles.FD =
  ## All epoll fds are valid fds, not the other way around though
  handles.FD epfd

proc close*(epfd: FD) {.borrow.}

proc create*(size: cint): FD {.cdecl, importc: "epoll_create".}
proc create*(flags: cint): FD {.cdecl, importc: "epoll_create1".}

proc ctl*(epfd: FD, op: CtlOp, fd: handles.FD, event: ptr Event): cint
         {.cdecl, importc: "epoll_ctl".}
proc ctl*(epfd: FD, op: CtlOp, fd: handles.FD, event: var Event): cint
         {.cdecl, importc: "epoll_ctl".}

proc wait*(epfd: FD, events: ptr UncheckedArray[Event], maxevents: cint,
           timeout: cint): cint {.cdecl, importc: "epoll_wait".}
proc wait*(epfd: FD, events: var openArray[Event], timeout: cint): cint
          {.inline.} =
  wait(epfd, cast[ptr UncheckedArray[Event]](addr events[0]), events.len.cint,
       timeout)
