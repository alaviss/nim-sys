#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Addresses and related utilities

import pkg/stew/endians2

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
