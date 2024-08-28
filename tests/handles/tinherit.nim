import std/[os, osproc, strutils]
import pkg/balls
import sys/handles
import ".."/helpers/handles as helpers_handles

when defined(windows):
  from pkg/winim/core as wincore import nil

  proc CompareObjectHandles(hFirstObjectHandle,
                            hSecondObjectHandle: wincore.Handle): wincore.WinBool
                           {.importc, stdcall, dynlib: "kernelbase.dll".}

proc testInheritance(fd: FD, expected: bool) =
  let reference = duplicate fd
  defer:
    close reference
  let p = startProcess(
    getAppFilename(),
    args = [$expected, $cast[uint](fd), $cast[uint](reference)],
    options = {poParentStreams}
  )
  defer:
    close p
  check p.waitForExit() == 0

proc runner() =
  suite "Test setInheritable":
    test "setInheritable(true)":
      let (rd, wr) = pipe()
      defer:
        close rd
        close wr
      rd.setInheritable(true)
      wr.setInheritable(true)
      testInheritance(rd, true)
      testInheritance(wr, true)
    test "setInheritable(false)":
      let (rd, wr) = pipe()
      defer:
        close rd
        close wr
      rd.setInheritable(false)
      wr.setInheritable(false)
      testInheritance(rd, false)
      testInheritance(wr, false)

proc inheritanceTester() =
  suite "Test inheritance":
    let
      expected = parseBool(paramStr 1)
      fd = cast[FD](parseBiggestUInt(paramStr 2))
      reference = cast[FD](parseBiggestUInt(paramStr 3))
      inheritMsg = if not expected: "inheritable" else: "not inheritable"
    test "Making sure that FD inheritability is correct":
      when not defined(windows):
        check fd.isValid() == expected
      else:
        check (CompareObjectHandles(
          cast[wincore.Handle](fd),
          cast[wincore.Handle](reference)
        ) != 0) == expected, "FD " & $cast[uint](fd) & " is " & inheritMsg

proc main() =
  if paramCount() == 0:
    runner()
  elif paramCount() >= 3:
    inheritanceTester()

main()
