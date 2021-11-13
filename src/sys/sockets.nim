#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Abstractions for networking operations over sockets.

{.experimental: "implicitDeref".}

import system except IOError

import std/[genasts, macros, options]
import pkg/stew/endians2
import files, handles, ioqueue

type
  SocketObj = object
    ## An object representing a socket. This is meant to be used as a base to
    ## specialize into other sockets type. Direct usage of this socket type is
    ## discouraged.
    handle: Handle[SocketFD]

  Socket = ref SocketObj
    ## A generic `Socket`.

  AsyncSocketObj {.borrow: `.`.} = distinct SocketObj
    ## A `SocketObj` opened in asynchronous mode.

  AsyncSocket = ref AsyncSocketObj
    ## A `Socket` opened in asynchronous mode.

  AnySocket = AsyncSocket | Socket
    ## A typeclass for the two basic socket types

proc `=copy`(dest: var SocketObj, src: SocketObj) {.error.}

func fd*(s: AnySocket): SocketFD {.inline.} =
  ## Returns the handle held by `s`.
  ##
  ## The returned `SocketFD` will stay valid for the duration of `s`.
  get s.handle

func takeFD*(s: AnySocket): SocketFD {.inline.} =
  ## Returns the file handle held by `s` and release ownership to the caller.
  ## `s` will be invalidated.
  ##
  ## If `s` is asynchronous, it will *not* be unregistered from the queue.
  take s.handle

proc close(s: var SocketObj) {.inline.} =
  ## Closes and invalidates the socket `s`.
  ##
  ## If `s` is invalid, `ClosedHandleDefect` will be raised.
  close s.handle

proc close(s: var AsyncSocketObj) {.inline.}

proc `=destroy`(s: var AsyncSocketObj) =
  ## Destroy the asynchronous socket `s`.
  if s.handle.get != InvalidFD:
    close(s)

proc close(s: var AsyncSocketObj) {.inline.} =
  ## Closes and invalidates the socket `s`.
  ##
  ## If `s` is invalid, `ClosedHandleDefect` will be raised.
  ##
  ## The FD associated with `s` will be deregistered from `ioqueue`.
  unregister s.handle.get
  close SocketObj(s)

proc close*(s: Socket) {.inline.} =
  ## Closes and invalidates the socket `s`.
  ##
  ## If `s` is invalid, `ClosedHandleDefect` will be raised.
  close s[]

proc close*(s: AsyncSocket) {.inline.} =
  ## Closes and invalidates the socket `s`.
  ##
  ## If `s` is invalid, `ClosedHandleDefect` will be raised.
  ##
  ## The FD associated with `s` will be deregistered from `ioqueue`.
  close s[]

# These are used to ensure correct destructor binding
{.warning: "compiler bug workaround; see: https://github.com/nim-lang/Nim/issues/19138".}
func newSocketAs(T: typedesc[not ref], fd: SocketFD): ref T {.inline.} =
  ## Create a ref socket from `fd`, converted to `T`.
  new result
  result[] = T SocketObj(handle: initHandle(fd))

func newSocketAs(T: typedesc[not ref], handle: sink Handle[SocketFD]): ref T {.inline.} =
  ## Create a ref socket from `handle`, converted to `T`.
  new result
  result[] = T SocketObj(handle: handle)

func newSocket*(fd: SocketFD): Socket {.inline.} =
  ## Creates a new `Socket` from an opened socket handle.
  ##
  ## The ownership of the handle will be transferred to the resulting `Socket`.
  ##
  ## **Note**: It is assumed that the handle has been opened in synchronous
  ## mode. Only use this interface if you know what you are doing.
  ##
  ## **Platform specific details**
  ##
  ## - On Windows, sockets created via Winsock `socket()` function are opened
  ##   in overlapped mode and should be passed to `newAsyncSocket
  ##   <#newAsyncSocket.SocketFD>` instead.
  newSocketAs(SocketObj, fd)

func newAsyncSocket*(fd: SocketFD): AsyncSocket {.inline.} =
  ## Creates a new `AsyncSocket` from an opened socket handle.
  ##
  ## The ownership of the handle will be transferred to the resulting `Socket`.
  ##
  ## **Note**: It is assumed that the handle has been opened in asynchronous
  ## mode. Only use this interface if you know what you are doing.
  ##
  ## **Platform specific details**
  ##
  ## - On POSIX, it is assumed that `fd` is opened with `O_NONBLOCK` set.
  ##
  ## - On Windows, it is assumed that `fd` is opened in overlapped mode.
  newSocketAs(AsyncSocketObj, fd)

func newSocket*(handle: sink Handle[SocketFD]): Socket {.inline.} =
  ## Creates a new `Socket` from an opened socket handle.
  ##
  ## The ownership of the handle will be transferred to the resulting `Socket`.
  ##
  ## **Note**: It is assumed that the handle has been opened in synchronous
  ## mode. Only use this interface if you know what you are doing.
  ##
  ## **Platform specific details**
  ##
  ## - On Windows, sockets created via Winsock `socket()` function are opened
  ##   in overlapped mode and should be passed to `newAsyncSocket
  ##   <#newAsyncSocket.SocketFD>` instead.
  newSocketAs(SocketObj, handle)

func newAsyncSocket*(handle: sink Handle[SocketFD]): AsyncSocket {.inline.} =
  ## Creates a new `AsyncSocket` from an opened socket handle.
  ##
  ## The ownership of the handle will be transferred to the resulting `Socket`.
  ##
  ## **Note**: It is assumed that the handle has been opened in asynchronous
  ## mode. Only use this interface if you know what you are doing.
  ##
  ## **Platform specific details**
  ##
  ## - On POSIX, it is assumed that `fd` is opened with `O_NONBLOCK` set.
  ##
  ## - On Windows, it is assumed that `fd` is opened in overlapped mode.
  newSocketAs(AsyncSocketObj, handle)

template derive(T, Base: typedesc): untyped =
  ## Template to mass-borrow socket operations.
  template fd*(s: T): SocketFD =
    Base(s).fd
  template takeFD*(s: T): SocketFD =
    takeFD Base(s)
  template close*(s: T) =
    close Base(s)

type
  Protocol* {.pure.} = enum
    TCP

  Conn*[Protocol: static Protocol] = distinct Socket
    ## A connection with `Protocol`.

  AsyncConn*[Protocol: static Protocol] = distinct AsyncSocket
    ## An asynchronous connection with `Protocol`.

derive Conn, Socket
derive AsyncConn, AsyncSocket

type
  Error {.pure.} = enum
    ## Enum containing error messages for use by this module
    InvalidFamily = "This address family is not supported by the operating system"
    Read = "Could not read from socket"
    Write = "Could not write into socket"
    Resolve = "Could not resolve the given host"
    Connect = "A connection could not be made to the endpoint"
    Listen = "Could not create a listener at the endpoint"
    Accept = "Could not accept any connection from the listener"
    LocalEndpoint = "Could not obtain the local endpoint"

when defined(posix):
  include private/sockets_posix
elif defined(windows):
  include private/sockets_windows
else:
  {.error: "This module has not been ported to your operating system.".}

proc read*[T: byte or char](s: Conn, b: var openArray[T]): int =
  ## Reads up to `b.len` bytes from socket `s` into `b`.
  ##
  ## If the other endpoint is closed, no data will be read and no error will be
  ## raised.
  ##
  ## Returns the number of bytes read from `s`.
  ##
  ## **Platform specific details**
  ##
  ## - On POSIX systems, signals will not interrupt the operation if nothing
  ##   was read.
  readImpl()

proc write*[T: byte or char](s: Conn, b: openArray[T]): int =
  ## Writes the contents of array `b` into socket `s`.
  ##
  ## Returns the number of bytes written to `s`.
  ##
  ## **Platform specific details**
  ##
  ## - On POSIX systems, signals will not interrupt the operation if nothing
  ##   was written.
  writeImpl()

macro implGenericAsyncConn(): untyped =
  ## Implement async operations on the generic type `AsyncConn` by manually
  ## specializing the operations for each `Protocol`.
  ##
  ## TODO: Get CPS generics working and deal with this mess...
  result = newStmtList()

  for proto in Protocol.items:
    result.add:
      genAstOpt({kDirtyTemplate}, proto = newLit(proto)):
        proc read*(s: AsyncConn[proto], buf: ptr UncheckedArray[byte],
                   bufLen: Natural): int {.asyncio.} =
          ## Reads up to `bufLen` bytes from socket `s` into `buf`.
          ##
          ## `buf` must stays alive for the duration of the operation. Direct usage
          ## of this interface is discouraged due to its unsafetyness. Users are
          ## encouraged to use the high-level overloads that keep buffers alive.
          ##
          ## If the other endpoint is closed, no data will be read and no error
          ## will be raised.
          ##
          ## Returns the number of bytes read from `s`.
          ##
          ## **Platform specific details**
          ##
          ## - On POSIX systems, signals will not interrupt the operation.
          if buf == nil and bufLen != 0:
            raise newException(ValueError, "A buffer must be provided for request of size > 0")

          asyncReadImpl()

        proc read*(s: AsyncConn[proto], b: ref string): int {.asyncio.} =
          ## Reads up to `b.len` bytes from socket `s` into `b`.
          ##
          ## This is an overload of read(s, buf, bufLen), plese refer to its
          ## documentation for more information.
          if b.len > 0:
            read(s, cast[ptr UncheckedArray[byte]](addr b[0]), b.len)
          else:
            read(s, nil, 0)

        proc read*(s: AsyncConn[proto], b: ref seq[byte]): int {.asyncio.} =
          ## Reads up to `b.len` bytes from socket `s` into `b`.
          ##
          ## This is an overload of read(s, buf, bufLen), plese refer to its
          ## documentation for more information.
          if b.len > 0:
            read(s, cast[ptr UncheckedArray[byte]](addr b[0]), b.len)
          else:
            read(s, nil, 0)

        proc write*(s: AsyncConn[proto], buf: ptr UncheckedArray[byte],
                    bufLen: Natural): int {.asyncio.} =
          ## Writes up to `bufLen` bytes from `buf` to socket `s`.
          ##
          ## `buf` must stays alive for the duration of the operation. Direct usage
          ## of this interface is discouraged due to its unsafetyness. Users are
          ## encouraged to use the high-level overloads that keep the buffer alive.
          ##
          ## Returns the number of bytes written into `s`.
          ##
          ## **Platform specific details**
          ##
          ## - On POSIX systems, signals will not interrupt the operation.
          if buf == nil and bufLen != 0:
            raise newException(ValueError, "A buffer must be provided for request of size > 0")

          asyncWriteImpl()

        proc write*(s: AsyncConn[proto], b: string): int {.asyncio.} =
          ## Writes up to `b.len` bytes from `b` to socket `s`. The contents of
          ## `b` will be copied prior to the operation. Consider the `ref`
          ## overload to avoid copies.
          ##
          ## This is an overload of write(s, buf, bufLen), plese refer to its
          ## documentation for more information.
          if b.len > 0:
            write(s, cast[ptr UncheckedArray[byte]](unsafeAddr b[0]), b.len)
          else:
            write(s, nil, 0)

        proc write*(s: AsyncConn[proto], b: seq[byte]): int {.asyncio.} =
          ## Writes up to `b.len` bytes from `b` to socket `s`. The contents of
          ## `b` will be copied prior to the operation. Consider the `ref`
          ## overload to avoid copies.
          ##
          ## This is an overload of write(s, buf, bufLen), plese refer to its
          ## documentation for more information.
          if b.len > 0:
            write(s, cast[ptr UncheckedArray[byte]](unsafeAddr b[0]), b.len)
          else:
            write(s, nil, 0)

        proc write*(s: AsyncConn[proto], b: ref string): int {.asyncio.} =
          ## Writes up to `b.len` bytes from `b` to socket `s`.
          ##
          ## This is an overload of write(s, buf, bufLen), plese refer to its
          ## documentation for more information.
          if b.len > 0:
            write(s, cast[ptr UncheckedArray[byte]](unsafeAddr b[0]), b.len)
          else:
            write(s, nil, 0)

        proc write*(s: AsyncConn[proto], b: ref seq[byte]): int {.asyncio.} =
          ## Writes up to `b.len` bytes from `b` into socket `s`.
          ##
          ## This is an overload of write(s, buf, bufLen), plese refer to its
          ## documentation for more information.
          if b.len > 0:
            write(s, cast[ptr UncheckedArray[byte]](unsafeAddr b[0]), b.len)
          else:
            write(s, nil, 0)

implGenericAsyncConn()

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

type
  ResolverResult* = ref ResolverResultImpl
    ## The result of a `resolve()` operation

  ResolverError* = object of CatchableError
    ## The exception type for errors during resolving that is not caused by the OS.
    # TODO: add a way to interpret the error code.
    errorCode*: int32 ## The error code as returned by the resolver. This value is platform-dependant.

proc `=copy`*(dst: var ResolverResultImpl, src: ResolverResultImpl) {.error.}
  ## Copying a `ResolverResult` is prohibited at the moment. This restriction
  ## might be lifted in the future.

proc resolveIP4*(host: string, port: Port = PortNone): ResolverResult
                {.raises: [OSError, ResolverError].} =
  ## Resolve the endpoints of `host` for port `port`.
  ##
  ## `port` will be carried over to the result verbatim.
  ##
  ## On failure, either `OSError` or `ResolverError` will be raised, depending
  ## on whether the error was caused by the operating system or the resolver.
  ##
  ## **Platform specific details**
  ##
  ## - On POSIX, the error code in `ResolverError` will be the error returned via `getaddrinfo()` function.
  ##
  ## - On Windows, the error code in `ResolverError` is one of the errors in this
  ##   `list <https://docs.microsoft.com/en-us/windows/win32/api/ws2tcpip/nf-ws2tcpip-getaddrinfow#return-value>`_.
  ##   Other errors are reported as `OSError`.
  ip4Resolve()

# In the future this should be either generic or use `Endpoint`.
iterator items*(r: ResolverResult): IP4Endpoint =
  ## Yields endpoints from the resolving result
  resolvedItems()

func closureItems(r: ResolverResult): iterator (): IP4Endpoint =
  ## Produce a closure iterator for `r.items`. This is necessary for use in CPS.
  result =
    iterator(): IP4Endpoint =
      for ep in r.items:
        yield ep

type
  IncompatibleEndpointError* = object of CatchableError
    ## Raised when connect or listen is used with `ResolverResult` but there
    ## are no compatible endpoint found.

func newIncompatibleEndpointError*(): ref IncompatibleEndpointError {.inline.} =
  ## Create an instance of `IncompatibleAddressError`.
  newException(IncompatibleEndpointError, "There are no compatible endpoint in the given list")

proc connectTcp*(endpoint: IP4Endpoint): Conn[TCP]
                {.raises: [OSError].} =
  ## Create a TCP connection to `endpoint`.
  tcpConnect()

proc connectTcp*(endpoints: ResolverResult): Conn[TCP]
                {.raises: [OSError, IncompatibleEndpointError].} =
  ## Connects via TCP to one of the compatible endpoint from `endpoints`.
  ##
  ## The first endpoint to connect successfully will be used.
  ##
  ## If there are no compatible addresses in `endpoints`,
  ## `IncompatibleEndpointError` will be raised.
  ##
  ## If connection fails for all `endpoints`, the `OSError` raised will be of
  ## the last endpoint tried.
  var
    attempted = false
    lastError: ref OSError
  for ep in endpoints.items:
    attempted = true
    try:
      result = connectTcp(ep)
    except OSError as e:
      lastError = e
      continue

    # If there are no errors, then we can just return here
    return

  # This should only be reached if either connection failed or it wasn't attempted.
  if not attempted:
    raise newIncompatibleEndpointError()
  else:
    raise lastError

proc connectTcp*(host: IP4, port: Port): Conn[TCP]
                {.inline, raises: [OSError].} =
  ## Create a TCP connection to `host` and `port`.
  connectTcp initEndpoint(host, port)

proc connectTcp*(host: string, port: Port): Conn[TCP]
                {.inline, raises: [OSError, ResolverError, IncompatibleEndpointError].} =
  ## Create a TCP connection to `host` and `port`.
  ##
  ## `host` will be resolved before connection.
  connectTcp resolveIP4(host, port)

proc connectTcpAsync*(endpoint: IP4Endpoint): AsyncConn[TCP]
                     {.asyncio.} =
  ## Create an asynchronous TCP connection to `endpoint`.
  ##
  ## `OSError` is raised if the connection fails.
  tcpAsyncConnect()

proc connectTcpAsync*(endpoints: ResolverResult): AsyncConn[TCP]
                     {.asyncio.} =
  ## Connects via TCP to one of the compatible endpoint from `endpoints`.
  ##
  ## The first endpoint to connect successfully will be used.
  ##
  ## If there are no compatible addresses in `endpoints`,
  ## `IncompatibleEndpointError` will be raised.
  ##
  ## If connection fails for all `endpoints`, the `OSError` raised will be of
  ## the last endpoint tried.
  ##
  ## **Note**: It might be necessary to perform an explicit `move` into this
  ## parameter.
  var
    attempted = false
    lastError: ref OSError
  {.warning: "Workaround for nim-works/cps#185".}
  let next: iterator (): IP4Endpoint = closureItems(endpoints)
  while true:
    attempted = true
    let ep = next()
    # The finished state is evaluated after the call.
    if next.finished: break

    try:
      result = connectTcpAsync(ep)
    except OSError as e:
      lastError = e
      continue

    # If there are no errors, then we can just return here
    return

  # This should only be reached if either connection failed or it wasn't attempted.
  if not attempted:
    raise newIncompatibleEndpointError()
  else:
    raise lastError

proc connectTcpAsync*(host: IP4, port: Port): AsyncConn[TCP]
                     {.asyncio.} =
  ## Create a TCP connection to `host` and `port`.
  connectTcpAsync initEndpoint(host, port)

proc connectTcpAsync*(host: string, port: Port): AsyncConn[TCP]
                     {.asyncio.} =
  ## Create a TCP connection to `host` and `port`.
  ##
  ## `host` will be resolved **synchronously** before connection.
  # A move have to be done or the compiler might think that this is a copy.
  var resolverResult = resolveIP4(host, port)
  connectTcpAsync move(resolverResult)

type
  Listener*[Protocol: static Protocol] = distinct Socket
    ## A listener with `Protocol`.

  AsyncListener*[Protocol: static Protocol] = distinct AsyncSocket
    ## An asynchronous listener with `Protocol`.

derive Listener, Socket
derive AsyncListener, AsyncSocket

proc listenTcp*(endpoint: IP4Endpoint, backlog = none(Natural)): Listener[TCP]
               {.raises: [OSError].} =
  ## Listen at `endpoint` for TCP connections.
  ##
  ## If the port of the endpoint is `PortNone`, an ephemeral port will be
  ## reserved automatically by the operating system. `localEndpoint` can be
  ## used to retrieve the port number.
  ##
  ## The `backlog` parameter defines the maximum amount of pending connections.
  ## If a connection request arrives when the queue is full, the client might
  ## receive a "Connection refused" error or the connection might be silently
  ## dropped. This value is treated by most operating systems as a hint.
  ##
  ## If `backlog` is `None`, the maximum queue length will be selected.
  ##
  ## If `backlog` is `0`, the OS will select a reasonable minimum.
  tcpListen()

proc listenTcp*(endpoints: ResolverResult, backlog = none(Natural)): Listener[TCP]
               {.raises: [OSError, IncompatibleEndpointError].} =
  ## Listen for TCP connections at one of the endpoint in `endpoints`.
  ##
  ## The first endpoint listened to successfully will be used.
  ##
  ## If there are no compatible addresses in `endpoints`,
  ## `IncompatibleEndpointError` will be raised.
  ##
  ## If listening fails for all `endpoints`, the `OSError` raised will be of
  ## the last endpoint tried.
  ##
  ## If the port of the endpoint is `PortNone`, an ephemeral port will be
  ## reserved automatically by the operating system. `localEndpoint` can be
  ## used to retrieve the port number.
  ##
  ## The `backlog` parameter defines the maximum amount of pending connections.
  ## If a connection request arrives when the queue is full, the client might
  ## receive a "Connection refused" error or the connection might be silently
  ## dropped. This value is treated by most operating systems as a hint.
  ##
  ## If `backlog` is `None`, the maximum queue length will be selected.
  ##
  ## If `backlog` is `0`, the OS will select a reasonable minimum.
  var
    attempted = false
    lastError: ref OSError
  for ep in endpoints.items:
    attempted = true
    try:
      result = listenTcp(ep, backlog)
    except OSError as e:
      lastError = e
      continue

    # If there are no errors, then we can just return here
    return

  # This should only be reached if either listening failed or it wasn't attempted.
  if not attempted:
    raise newIncompatibleEndpointError()
  else:
    raise lastError

proc listenTcp*(host: IP4, port: Port, backlog = none(Natural)): Listener[TCP]
               {.inline, raises: [OSError].} =
  ## Listen at `host` and `port` for TCP connections.
  ##
  ## If the port of the endpoint is `PortNone`, an ephemeral port will be
  ## reserved automatically by the operating system. `localEndpoint` can be
  ## used to fetch this data.
  ##
  ## The `backlog` parameter defines the maximum amount of pending connections.
  ## If a connection request arrives when the queue is full, the client might
  ## receive a "Connection refused" error or the connection might be silently
  ## dropped. This value is treated by most operating systems as a hint.
  ##
  ## If `backlog` is `None`, the maximum queue length will be selected.
  ##
  ## If `backlog` is `0`, the OS will select a reasonable minimum.
  listenTcp(initEndpoint(host, port), backlog)

proc listenTcp*(host: string, port: Port, backlog = none(Natural)): Listener[TCP]
               {.inline, raises: [OSError, IncompatibleEndpointError, ResolverError].} =
  ## Listen at `host` and `port` for TCP connections.
  ##
  ## If the port of the endpoint is `PortNone`, an ephemeral port will be
  ## reserved automatically by the operating system. `localEndpoint` can be
  ## used to retrieve the port number.
  ##
  ## The `backlog` parameter defines the maximum amount of pending connections.
  ## If a connection request arrives when the queue is full, the client might
  ## receive a "Connection refused" error or the connection might be silently
  ## dropped. This value is treated by most operating systems as a hint.
  ##
  ## If `backlog` is `None`, the maximum queue length will be selected.
  ##
  ## If `backlog` is `0`, the OS will select a reasonable minimum.
  listenTcp(resolveIP4(host, port), backlog)

{.warning: "Compiler bug workaround, see https://github.com/nim-lang/Nim/issues/19118".}
proc listenTcpAsync*(endpoint: IP4Endpoint, backlog: Option[Natural] = none(Natural)): AsyncListener[TCP]
                    {.asyncio.} =
  ## Listen at `endpoint` for TCP connections asynchronously.
  ##
  ## If the port of the endpoint is `PortNone`, an ephemeral port will be
  ## reserved automatically by the operating system. `localEndpoint` can be
  ## used to retrieve the port number.
  ##
  ## The `backlog` parameter defines the maximum amount of pending connections.
  ## If a connection request arrives when the queue is full, the client might
  ## receive a "Connection refused" error or the connection might be silently
  ## dropped. This value is treated by most operating systems as a hint.
  ##
  ## If `backlog` is `None`, the maximum queue length will be selected.
  ##
  ## If `backlog` is `0`, the OS will select a reasonable minimum.
  tcpAsyncListen()

proc listenTcpAsync*(endpoints: ResolverResult, backlog: Option[Natural] = none(Natural)): AsyncListener[TCP]
                    {.asyncio.} =
  ## Listen for TCP connections at one of the endpoint in `endpoints`.
  ##
  ## The first endpoint listened to successfully will be used.
  ##
  ## If there are no compatible addresses in `endpoints`,
  ## `IncompatibleEndpointError` will be raised.
  ##
  ## If listening fails for all `endpoints`, the `OSError` raised will be of
  ## the last endpoint tried.
  ##
  ## If the port of the endpoint is `PortNone`, an ephemeral port will be
  ## reserved automatically by the operating system. `localEndpoint` can be
  ## used to retrieve the port number.
  ##
  ## **Note**: It might be necessary to perform an explicit `move` into this
  ## parameter.
  var
    attempted = false
    lastError: ref OSError
  {.warning: "Workaround for nim-works/cps#185".}
  let next: iterator (): IP4Endpoint = closureItems(endpoints)
  while true:
    attempted = true
    let ep = next()
    # The finished state is evaluated after the call.
    if next.finished: break

    try:
      result = listenTcpAsync(ep, backlog)
    except OSError as e:
      lastError = e
      continue

    # If there are no errors, then we can just return here
    return

  # This should only be reached if either listening failed or it wasn't attempted.
  if not attempted:
    raise newIncompatibleEndpointError()
  else:
    raise lastError

proc listenTcpAsync*(host: IP4, port: Port, backlog: Option[Natural] = none(Natural)): AsyncListener[TCP]
                    {.asyncio.} =
  ## Listen at `host` and `port` for TCP connections.
  ##
  ## If the port of the endpoint is `PortNone`, an ephemeral port will be
  ## reserved automatically by the operating system. `localEndpoint` can be
  ## used to retrieve the port number.
  ##
  ## The `backlog` parameter defines the maximum amount of pending connections.
  ## If a connection request arrives when the queue is full, the client might
  ## receive a "Connection refused" error or the connection might be silently
  ## dropped. This value is treated by most operating systems as a hint.
  ##
  ## If `backlog` is `None`, the maximum queue length will be selected.
  ##
  ## If `backlog` is `0`, the OS will select a reasonable minimum.
  listenTcpAsync(initEndpoint(host, port), backlog)

proc listenTcpAsync*(host: string, port: Port, backlog: Option[Natural] = none(Natural)): AsyncListener[TCP]
                    {.asyncio.} =
  ## Listen at `host` and `port` for TCP connections.
  ##
  ## If the port of the endpoint is `PortNone`, an ephemeral port will be
  ## reserved automatically by the operating system. `localEndpoint` can be
  ## used to retrieve the port number.
  ##
  ## The `backlog` parameter defines the maximum amount of pending connections.
  ## If a connection request arrives when the queue is full, the client might
  ## receive a "Connection refused" error or the connection might be silently
  ## dropped. This value is treated by most operating systems as a hint.
  ##
  ## If `backlog` is `None`, the maximum queue length will be selected.
  ##
  ## If `backlog` is `0`, the OS will select a reasonable minimum.
  # A move have to be performed due to the compiler thinking that this is a
  # "copy".
  listenTcpAsync(resolveIP4(host, port), backlog)

proc accept*(l: Listener[TCP]): tuple[conn: Conn[TCP], remote: IP4Endpoint] {.raises: [OSError].} =
  ## Get the first connection from the queue of pending connections of `l`.
  ##
  ## Returns the connection and its endpoint.
  tcpAccept()

proc accept*(l: AsyncListener[TCP]): tuple[conn: AsyncConn[TCP], remote: IP4Endpoint] {.asyncio.} =
  ## Get the first connection from the queue of pending connections of `l`.
  ##
  ## Returns the connection and its endpoint.
  tcpAsyncAccept()

proc localEndpoint*(l: AsyncListener[TCP] | Listener[TCP]): IP4Endpoint {.raises: [OSError].} =
  ## Obtain the local endpoint of `l`.
  tcpLocalEndpoint()
