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
  from sys/private/syscall/winim/winim/inc/windef import MakeWord, LoByte, HiByte
  import sys/private/syscall/winim/winim/inc/winsock

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

  test "Handle[T] not destroyed before construction":
    skip("nim-lang/Nim#16607")

    when not compileOption("assertions"):
      skip("assertions are disabled")

    proc pair(): tuple[a, b: Handle[FD]] =
      result.a = initHandle(FD InvalidFD)
      result.b = initHandle(FD InvalidFD)

    discard pair()

    proc pairRef(): tuple[a, b: ref Handle[FD]] =
      result.a = newHandle(FD InvalidFD)
      result.b = newHandle(FD InvalidFD)

    discard pairRef()
    when declared(GC_fullCollect):
      GC_fullCollect()

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

    check hrd.get == InvalidFD
