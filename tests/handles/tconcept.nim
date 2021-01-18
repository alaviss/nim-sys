import pkg/balls
import sys/handles

suite "Concept matching":
  test "FD is AnyFD":
    check FD is AnyFD

  test "SocketFD is AnyFD":
    check SocketFD is AnyFD
