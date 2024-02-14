#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Addresses and related utilities

import pkg/stew/endians2
import strformat

when defined(posix):
  include ".."/private/addresses_posix
elif defined(windows):
  include ".."/private/addresses_windows
else:
  {.error: "This module has not been ported to your operating system.".}

type
  IP4* = IP4Impl
    ## An IPv4 address.

func word(ip: IP4): uint32 {.inline.} =
  ## Obtain the address from `ip` as an integer in big endian.
  ip4Word()

func `word=`(ip: var IP4, w: uint32) {.inline.} =
  ## Set the address referenced to by `ip` to `w`, with `w` in big endian.
  ip4SetWord()

func ip4*(a, b, c, d: byte): IP4 {.inline.} =
  ## Returns the `IP4` object of the IP address `a.b.c.d`.
  result.word = fromBytesBE(uint32, [a, b, c, d]).toBE()

const
  IP4Loopback* = ip4(127, 0, 0, 1)
    ## The IPv4 loopback address.

  IP4Any* = ip4(0, 0, 0, 0)
    ## The IPv4 address used to signify binding to any address.

  IP4Broadcast* = ip4(255, 255, 255, 255)
    ## The IPv4 address used to signify any host.

func `==`*(a, b: IP4): bool {.inline.} =
  ## Returns whether `a` and `b` points to the same address.
  a.word == b.word

func `[]`*(ip: IP4, idx: Natural): byte {.inline.} =
  ## Returns octet at position `idx` of `ip`.
  runnableExamples:
    let ip = ip4(127, 0, 0, 1)
    doAssert ip[0] == 127

  ip.word.fromBE().toBytesBE()[idx]

func `[]=`*(ip: var IP4, idx: Natural, val: byte) {.inline.} =
  ## Set the octet at position `idx` to `val`.
  runnableExamples:
    var ip = ip4(127, 0, 0, 1)
    ip[0] = 10
    doAssert ip == ip4(10, 0, 0, 1)

  var address = ip.word.fromBE().toBytesBE()
  address[idx] = val
  ip.word = fromBytesBE(uint32, address).toBE()

func len*(ip: IP4): int {.inline.} =
  ## Returns the number of octets in `ip`.
  4

func `$`*(ip: IP4): string {.inline.} =
  ## Returns the string representation of `ip`.
  result = $ip[0] & '.' & $ip[1] & '.' & $ip[2] & '.' & $ip[3]

type
  Port* = distinct uint16
    ## The port number type.

  IP4Endpoint* = IP4EndpointImpl
    ## An IPv4 endpoint, which is a combination of an IPv4 address and a port.

const
  PortNone* = 0.Port
    ## The port that means "no port". Different procedures will interpret this
    ## value differently.

func `$`*(p: Port): string {.borrow.}
func `==`*(a, b: Port): bool {.borrow.}

proc initEndpoint*(ip: IP4, port: Port): IP4Endpoint =
  ## Creates an endpoint from an IP address and a port.
  ip4InitEndpoint()

proc ip*(e: IP4Endpoint): IP4 =
  ## Returns the IPv4 address of the endpoint.
  ip4EndpointAddr()

proc port*(e: IP4Endpoint): Port =
  ## Returns the port of the endpoint.
  ip4EndpointPort()

proc `$`*(e: IP4Endpoint): string =
  &"{e.ip}:{e.port}"

type
  IP6* = IP6Impl
    ## An IPv6 address.

func ip6*(a, b, c, d, e, f, g, h: uint16): IP6 =
  ## Creates an `IP4` object of the address `a:b:c:d:e:f:g:h`.
  var idx = 0
  for x in [a, b, c, d, e, f, g, h]:
    let bytes = x.toBytesBE()
    result.octets[idx] = bytes[0]
    result.octets[idx + 1] = bytes[1]
    inc idx, 2

const
  IP6Loopback* = ip6(0, 0, 0, 0, 0, 0, 0, 1)
    ## The IPv6 loopback address.
  IP6Any* = ip6(0, 0, 0, 0, 0, 0, 0, 0)
    ## The IPv6 address used to specify binding to any address.

func `==`*(a, b: IP6): bool =
  ## Returns whether `a` and `b` points to the same address.
  a.octets == b.octets

func `[]`*(ip: IP6, idx: Natural): uint16 {.inline.} =
  ## Returns the `uint16` at position `idx`.
  fromBytesBE(uint16, ip.octets.toOpenArray(idx * 2, idx * 2 + 1))

func `[]=`*(ip: var IP6, idx: Natural, val: uint16) {.inline.} =
  ## Set the `uint16` at position `idx` to `val`.
  let bytes = toBytesBE(val)
  ip.octets[idx * 2] = bytes[0]
  ip.octets[idx * 2 + 1] = bytes[1]

func len*(ip: IP6): int {.inline.} =
  ## Returns the number of `uint16` in `ip`.
  8

func isV4Mapped*(ip: IP6): bool =
  ## Returns whether `ip` is an IPv4-mapped address as described in RFC4291.
  for x in 0 ..< 10:
    if ip.octets[x] != 0:
      return false

  result = ip.octets[10] == 0xff and ip.octets[11] == 0xff

func `$`*(ip: IP6): string =
  ## Returns the string representation of `ip`.
  if ip.isV4Mapped():
    result = "::ffff:" & $ip.octets[12] & '.' & $ip.octets[13] & '.' & $ip.octets[14] & '.' & $ip.octets[15]
  else:
    var zeroSlice = -1 .. -2
    var idx = 0
    while idx < ip.len:
      if ip[idx] == 0:
        let start = idx
        while idx < ip.len and ip[idx] == 0:
          inc idx
        let slice = start ..< idx

        if slice.len > zeroSlice.len:
          zeroSlice = slice
      else:
        inc idx

    func addIp6Slice(s: var string, ip: IP6, slice: Slice[int]) =
      if slice.len > 0:
        var slice = slice
        s.add &"{ip[slice.a]:x}"
        inc slice.a
        for idx in slice:
          s.add &":{ip[idx]:x}"

    if zeroSlice.len > 1:
      result.addIp6Slice(ip, 0 ..< zeroSlice.a)
      result.add "::"
      result.addIp6Slice(ip, zeroSlice.b + 1 ..< ip.len)
    else:
      result.addIp6Slice(ip, 0 ..< ip.len)

type
  IP6Endpoint* = IP6EndpointImpl
    ## An IPv6 endpoint, which is a combination of an IPv4 address, a port, a
    ## flow identifier and a scope identifier.

  FlowId* = distinct uint32
    ## A 20-bit flow identifier. As RFC3493 does not specify an interpretation,
    ## the library treats this type as opaque and does not perform any
    ## byte-ordering conversions.
    ##
    ## From testing, it appears that most operating systems use network byte
    ## ordering for values of this type.

  ScopeId* = distinct uint32
    ## A 32-bit address scope identifier. As RFC3493 does not specify an
    ## interpretation, the library treats this type as opaque and does not
    ## perform any byte-ordering conversions.
    ##
    ## From testing, it appears that most operating systems use host byte
    ## ordering for values of this type.

proc initEndpoint*(ip: IP6, port: Port, flowId = 0.FlowId,
                   scopeId = 0.ScopeId): IP6Endpoint =
  ## Creates an IPv6 endpoint.
  ip6InitEndpoint()

proc ip*(e: IP6Endpoint): IP6 =
  ## Returns the IPv6 address of the endpoint.
  ip6EndpointAddr()

proc port*(e: IP6Endpoint): Port =
  ## Returns the port of the endpoint.
  ip6EndpointPort()

proc flowId*(e: IP6Endpoint): FlowId =
  ## Returns the flow identifier of the endpoint.
  ip6EndpointFlowId()

proc scopeId*(e: IP6Endpoint): ScopeId =
  ## Returns the scope identifier of the endpoint.
  ip6EndpointScopeId()

type
  IPEndpointKind* {.pure.} = enum
    ## The address family of an endpoint.
    V4
    V6

  IPEndpoint* = object
    ## An object containing either IPv4 or IPv6 endpoint.
    case kind*: IPEndpointKind
    of V4: v4*: IP4Endpoint
    of V6: v6*: IP6Endpoint
