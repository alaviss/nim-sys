#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Wrappers for kqueue.
##
## Only the parts common between BSDs implementations are wrapped.
##
## For macOS, we wrap the `kevent64` interface and the `kevent` is a
## compatibility wrapper. This is due to Nim not being able to replicate
## the `kevent` structure accurately (lack a `#pragma pack` equivalent).

import ".."/posix
import ".."/".."/".."/handles

type
  Ident* = distinct (
    when defined(macosx):
      uint64
    else:
      uint
  )
    ## Type used for event identifier

  Filter* = distinct (
    when defined(freebsd) or defined(openbsd) or defined(dragonfly):
      cshort
    elif defined(netbsd):
      uint32
    elif defined(macosx):
      int16
    else:
      {.error: "This module has not been ported to your operating system".}
  )
    ## Type used for kernel event filters

  Ev* = distinct (
    when defined(freebsd) or defined(openbsd) or defined(dragonfly):
      cushort
    elif defined(netbsd):
      uint32
    elif defined(macosx):
      uint16
    else:
      {.error: "This module has not been ported to your operating system".}
  )
    ## Type used for action flags

  FilterFlag* = (
    when defined(freebsd) or defined(openbsd) or defined(dragonfly):
      cuint
    elif defined(netbsd) or defined(macosx):
      uint32
    else:
      {.error: "This module has not been ported to your operating system".}
  )
    ## Type used for filter specific flags

  FilterData* = (
    when defined(dragonfly):
      int
    elif defined(freebsd) or defined(openbsd) or defined(netbsd) or defined(macosx):
      int64
    else:
      {.error: "This module has not been ported to your operating system".}
  )
    ## Type used for filter specific data

  UserData* = distinct (
    when defined(macosx):
      uint64
    else:
      pointer
  )
    ## Type used for user data

  Kevent* {.pure.} = object
    ## The kevent structure
    ##
    ## **Platform-specific details**
    ##
    ## * On macOS, this structure corresponds to `kevent64_s`.
    ##
    ## * On FreeBSD, this structure corresponds to `kevent` on FreeBSD 12 and
    ##   newer and is not compatible with FreeBSD 11 and older.
    ident*: Ident ## Event identifier, interpretation is determined by the filter
    filter*: Filter ## Kernel filter used to process the event
    flags*: Ev ## Actions to perform on the event
    fflags*: FilterFlag ## Filter-specific flags
    data*: FilterData ## Filter-specific data value
    udata*: UserData ## Opaque user-defined value
    when defined(freebsd):
      ext*: array[4, uint64] ## FreeBSD-specific extension data
    elif defined(macosx):
      ext*: array[2, uint64] ## macOS-specific extension data

type
  FD* = distinct handles.FD
    ## Type used for kqueue FDs

const
  EvAdd* = 0x0001.Ev
  EvDelete* = 0x0002.Ev
  EvEnable* = 0x0004.Ev
  EvDisable* = 0x0008.Ev
  EvOneshot* = 0x0010.Ev
  EvClear* = 0x0020.Ev
  EvReceipt* = 0x0040.Ev
  EvDispatch* = 0x0080.Ev
  EvEOF* = 0x8000.Ev
  EvError* = 0x4000.Ev

  FilterRead* =
    when defined(freebsd) or defined(openbsd) or defined(dragonfly) or defined(macosx):
      -1.Filter
    elif defined(netbsd):
      0.Filter
    else:
      {.error: "This module has not been ported to your operating system".}
  FilterWrite* =
    when defined(freebsd) or defined(openbsd) or defined(dragonfly) or defined(macosx):
      -2.Filter
    elif defined(netbsd):
      1.Filter
    else:
      {.error: "This module has not been ported to your operating system".}
  FilterAIO* =
    when defined(freebsd) or defined(openbsd) or defined(dragonfly) or defined(macosx):
      -3.Filter
    elif defined(netbsd):
      2.Filter
    else:
      {.error: "This module has not been ported to your operating system".}
  FilterVNode* =
    when defined(freebsd) or defined(openbsd) or defined(dragonfly) or defined(macosx):
      -4.Filter
    elif defined(netbsd):
      3.Filter
    else:
      {.error: "This module has not been ported to your operating system".}
  FilterProc* =
    when defined(freebsd) or defined(openbsd) or defined(dragonfly) or defined(macosx):
      -5.Filter
    elif defined(netbsd):
      4.Filter
    else:
      {.error: "This module has not been ported to your operating system".}
  FilterSignal* =
    when defined(freebsd) or defined(openbsd) or defined(dragonfly) or defined(macosx):
      -6.Filter
    elif defined(netbsd):
      5.Filter
    else:
      {.error: "This module has not been ported to your operating system".}
  FilterTimer* =
    when defined(freebsd) or defined(openbsd) or defined(dragonfly) or defined(macosx):
      -7.Filter
    elif defined(netbsd):
      6.Filter
    else:
      {.error: "This module has not been ported to your operating system".}

func `or`*(a, b: Ev): Ev {.borrow.}
  ## Bitwise OR operator for Ev

func `and`*(a, b: Ev): Ev {.borrow.}
  ## Bitwise AND operator for Ev

func `not`*(x: Ev): Ev {.borrow.}
  ## Bitwise NOT operator for Ev

func has*(a, b: Ev): bool {.inline.} =
  ## Check if `b` is in `a`
  (a and b).uint32 != 0u32

converter toFD*(kq: FD): handles.FD =
  ## All kqueue fds are valid fds, not the other way around though
  handles.FD kq

proc close*(kq: FD) {.borrow.}

proc kqueue*(): FD {.cdecl, importc, sideEffect.}

type
  ListSize* = (
    when defined(freebsd) or defined(openbsd) or defined(dragonfly) or defined(macosx):
      cint
    elif defined(netbsd):
      csize_t
    else:
      {.error: "This module has not been ported to your operating system".}
  )
  ## The type used for the size of lists passed to kevent

when defined(macosx):
  proc kevent64*(kq: FD, changeList: ptr UncheckedArray[Kevent], nchanges: ListSize,
                 eventList: ptr UncheckedArray[Kevent], nevents: ListSize,
                 flags: cuint,
                 timeout: ptr Timespec): cint {.cdecl, importc, sideEffect.}

  proc kevent*(kq: FD, changeList: ptr UncheckedArray[Kevent], nchanges: ListSize,
               eventList: ptr UncheckedArray[Kevent], nevents: ListSize,
               timeout: ptr Timespec): cint {.inline.} =
     kevent64(kq, changeList, nchanges, eventList, nevents, 0, timeout)

else:
  proc kevent*(kq: FD, changeList: ptr UncheckedArray[Kevent], nchanges: ListSize,
               eventList: ptr UncheckedArray[Kevent], nevents: ListSize,
               timeout: ptr Timespec): cint {.cdecl, importc, sideEffect.}

proc kevent*(kq: FD, changeList: openArray[Kevent],
             eventList: var openArray[Kevent],
             timeout: Timespec): cint {.inline.} =
  kevent(kq, cast[ptr UncheckedArray[Kevent]](unsafeAddr changeList[0]),
         ListSize(changeList.len),
         cast[ptr UncheckedArray[Kevent]](addr eventList[0]),
         ListSize(eventList.len), unsafeAddr timeout)

proc kevent*(kq: FD, changeList: openArray[Kevent]): cint {.inline.} =
  kevent(kq, cast[ptr UncheckedArray[Kevent]](unsafeAddr changeList[0]),
         ListSize(changeList.len), nil, 0, nil)

proc kevent*(kq: FD, eventList: var openArray[Kevent]): cint {.inline.} =
  kevent(kq, nil, 0, cast[ptr UncheckedArray[Kevent]](addr eventList[0]),
         ListSize(eventList.len), nil)

proc kevent*(kq: FD, eventList: var openArray[Kevent],
             timeout: Timespec): cint {.inline.} =
  kevent(kq, nil, 0, cast[ptr UncheckedArray[Kevent]](addr eventList[0]),
         ListSize(eventList.len), unsafeAddr timeout)
