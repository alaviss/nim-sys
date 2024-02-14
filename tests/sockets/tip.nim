import std/options
import pkg/balls
import sys/sockets

suite "IP address testing":
  test "IPv4 to string":
    check $ip4(127, 0, 0, 1) == "127.0.0.1"
    check $ip4(1, 1, 1, 1) == "1.1.1.1"

  test "Resolving localhost works":
    var
      foundV4 = false
      foundV6 = false
    for ep in resolveIP("localhost").items:
      if ep.kind == V4 and ep.v4.ip == ip4(127, 0, 0, 1):
        foundV4 = true
        check ep.v4.port == PortNone
      elif ep.kind == V6 and ep.v6.ip == ip6(0, 0, 0, 0, 0, 0, 0, 1):
        foundV6 = true
        check ep.v6.port == PortNone

    check foundV4, "did not find 127.0.0.1 when resolving for localhost"
    check foundV6, "did not find ::1 when resolving for localhost"

  test "Scoped resolve for localhost":
    var foundV4 = false
    for ep in resolveIP("localhost", kind = some(V4)).items:
      if ep.kind == V4 and ep.v4.ip == ip4(127, 0, 0, 1):
        foundV4 = true
        check ep.v4.port == PortNone
      elif ep.kind == V6:
        check false, "found IPv6 for localhost but configured to resolve only IPv4 addresses"

    check foundV4, "did not find 127.0.0.1 when resolving for localhost"

    var foundV6 = false
    for ep in resolveIP("localhost", kind = some(V6)).items:
      if ep.kind == V6 and ep.v6.ip == ip6(0, 0, 0, 0, 0, 0, 0, 1):
        foundV6 = true
        check ep.v6.port == PortNone
      elif ep.kind == V4:
        check false, "found IPv4 for localhost but configured to resolve only IPv6 addresses"

    check foundV6, "did not find ::1 when resolving for localhost"

  test "Resolve for localhost with port":
    const port = 8080.Port
    var foundV4 = false
    for ep in resolveIP("localhost", port, kind = some(V4)).items:
      if ep.kind == V4 and ep.v4.ip == ip4(127, 0, 0, 1):
        foundV4 = true
        check ep.v4.port == port
      elif ep.kind == V6:
        check false, "found IPv6 for localhost but configured to resolve only IPv4 addresses"

    check foundV4, "did not find 127.0.0.1 when resolving for localhost"

    var foundV6 = false
    for ep in resolveIP("localhost", port, kind = some(V6)).items:
      if ep.kind == V6 and ep.v6.ip == ip6(0, 0, 0, 0, 0, 0, 0, 1):
        foundV6 = true
        check ep.v6.port == port
      elif ep.kind == V4:
        check false, "found IPv4 for localhost but configured to resolve only IPv6 addresses"

    check foundV6, "did not find ::1 when resolving for localhost"

  test "IPv6 to string":
    check $ip6(0, 0, 0, 0, 0, 0, 0, 0) == "::"
    check $ip6(0, 0, 0, 0, 0, 0, 0, 1) == "::1"
    check $ip6(0x2001, 0xdb8, 0, 0, 0, 0, 0, 0) == "2001:db8::"
    check $ip6(0x2001, 0xdb8, 0x1b, 0, 0x2, 0, 0, 0) == "2001:db8:1b:0:2::"
    check $ip6(0x2001, 0xdb8, 0x1b, 0, 0, 0, 0, 0xfd) == "2001:db8:1b::fd"
    check $ip6(0x2001, 0xdb8, 0, 0x3, 0x2, 0x4d, 0x5c, 0x6d) == "2001:db8:0:3:2:4d:5c:6d"
    check $ip6(0x2001, 0xdb8, 0x1b, 0x3, 0x2, 0x4d, 0x5c, 0x6d) == "2001:db8:1b:3:2:4d:5c:6d"

  test "IPv4-mapped IPv6 to string":
    check $ip6(0, 0, 0, 0, 0, 0xffff, 0x7f00, 1) == "::ffff:127.0.0.1"
    check $ip6(0, 0, 0, 0, 0, 0xffff, 0xc000, 0x2a0) == "::ffff:192.0.2.160"
    check $ip6(0xfe80, 0, 0, 0, 0, 0xffff, 0xc000, 0x2a0) == "fe80::ffff:c000:2a0"
