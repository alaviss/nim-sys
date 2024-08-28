#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import pkg/balls
import sys/handles
import ".."/helpers/utils
import ".."/helpers/handles as helper_handles

when defined(windows):
  from pkg/winim/inc/windef import MakeWord, LoByte, HiByte
  import pkg/winim/inc/winsock

suite "Test close() and Handle[T] destructions":
  when defined(windows):
    block:
      ## Initialize winsock
      var wsaData: WsaData
      doAssert WsaStartup(MakeWord(2, 2), addr wsaData) == 0,
               "Could not initialize Winsock"
      doAssert LoByte(wsaData.wVersion) == 2 and HiByte(wsaData.wVersion) == 2,
               "Did not get the wanted Winsock version"

  test "Invalid FD raises Defect":
    expectDefect:
      close(FD InvalidFD)

  test "Invalid SocketFD raises Defect":
    expectDefect:
      close(SocketFD InvalidFD)

  test "Handle[T] initializes to invalid":
    var handle: Handle[FD]

    check handle.fd == InvalidFD

  test "Handle[T] can store the highest handle possible correctly":
    const MaxFD =
      when defined(posix):
        FD(high cint)
      elif defined(windows):
        cast[FD](high uint)
      else:
        {.error: "A maximum FD is not defined for this platform".}

    var handle = initHandle(MaxFD)

    try:
      check handle.fd == MaxFD
    finally:
      # This handle is also invalid, so remove it to prevent Handle[T] from
      # trying to close it.
      discard handle.takeFd()

  var
    rd = FD InvalidFD
    wr = FD InvalidFD

  test "Handle[T] is destroyed on scope exit":
    block:
      (rd, wr) = pipe()
      let
        hrd = initHandle(rd)
        hwr = initHandle(wr)
    check not rd.isValid
    check not wr.isValid

  test "Handle[T] is destroyed on collection":
    when not defined(gcDestructors):
      skip("Normal GCs are too picky on when to collect, making them untestable.")

    block:
      (rd, wr) = pipe()
      let
        hrd = newHandle(rd)
        hwr = newHandle(wr)

    check not rd.isValid
    check not wr.isValid

  test "Closing closed handles raises Defect":
    expectDefect:
      close rd
      close wr

  test "Closing closed Handle[T] raises Defect and reset to invalid":
    when defined(nimPanics):
      skip("--panics is enabled")

    var hrd = initHandle(rd)
    expectDefect:
      close hrd

    check hrd.fd == InvalidFD
