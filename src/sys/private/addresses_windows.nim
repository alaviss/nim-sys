#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import pkg/winim/core as wincore except Handle

type
  IP4Impl {.borrow: `.`.} = distinct InAddr
  IP6Impl {.borrow: `.`.} = distinct In6Addr

template ip4Word() {.dirty.} =
  result = cast[uint32](ip.S_addr)

template ip4SetWord() {.dirty.} =
  ip.S_addr = cast[int32](w)

type IP4EndpointImpl {.requiresInit, borrow: `.`.} = distinct Sockaddr_in

template ip4InitEndpoint() {.dirty.} =
  result = IP4EndpointImpl:
    sockaddr_in(
      sin_family: AF_INET,
      sin_addr: InAddr(ip),
      sin_port: toBE(port.uint16)
    )

template ip4EndpointAddr() {.dirty.} =
  result = IP4 e.sin_addr

template ip4EndpointPort() {.dirty.} =
  result = Port fromBE(e.sin_port)

template octets(ip: IP6Impl): untyped =
  ip.Byte

type IP6EndpointImpl {.requiresInit, borrow: `.`.} = distinct sockaddr_in6

template ip6InitEndpoint() {.dirty.} =
  result = IP6EndpointImpl:
    Sockaddr_in6(
      sin6_family: AF_INET6,
      sin6_addr: In6Addr(ip),
      sin6_port: toBE(port.uint16),
      sin6_flowinfo: int32(flowId)
    )
  result.union1.sin6_scope_id = int32(scopeId)

template ip6EndpointAddr() {.dirty.} =
  result = IP6 e.sin6_addr

template ip6EndpointPort() {.dirty.} =
  result = Port fromBE(e.sin6_port)

template ip6EndpointFlowId() {.dirty.} =
  result = FlowId e.sin6_flowinfo

template ip6EndpointScopeId() {.dirty.} =
  result = ScopeId e.union1.sin6_scope_id
