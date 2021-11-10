#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import syscall/posix
import errors

type
  SockFlag = enum
    ## Flags used for makeSocket
    sfNonBlock

proc makeSocket(domain, typ, proto: cint, flags: set[SockFlag] = {}): Handle[SocketFD] =
  var stype = typ

  when not defined(macosx):
    # OSX does not support setting cloexec and nonblock on the sock type parameter
    stype = stype or SOCK_CLOEXEC

    if sfNonBlock in flags:
      stype = stype or SOCK_NONBLOCK

  let sock = initHandle: SocketFD socket(domain, stype, proto)
  if sock.get == InvalidFD:
    raise newOSError(errno)

  when defined(macosx):
    # OSX does not support setting cloexec and nonblock on socket creation, so
    # it has to be done here.
    setInheritable(result, false)

    if sfNonBlock in flags:
      setBlocking(result, false)

  result = sock

template readImpl() {.dirty.} =
  let bytesRead = retryOnEIntr:
    if b.len > 0:
      read(s.fd.cint, addr b[0], b.len)
    else:
      read(s.fd.cint, nil, 0)

  if bytesRead == -1:
    raise newIOError(0, errno, $Error.Read)

  result = bytesRead

template writeImpl() {.dirty.} =
  let written = retryOnEIntr:
    if b.len > 0:
      write(s.fd.cint, cast[ptr UncheckedArray[byte]](unsafeAddr b[0]), b.len)
    else:
      write(s.fd.cint, nil, 0)

  if written == -1:
    raise newIOError(0, errno, $Error.Write)

  result = written

template asyncReadImpl() {.dirty.} =
  while true:
    let bytesRead = retryOnEIntr: read(s.fd.cint, buf, bufLen)

    if bytesRead == -1:
      # On "no data yet" signal
      if errno == EAGAIN or errno == EWOULDBLOCK:
        # Wait until there is data
        wait(s.fd, Event.Read)
      else:
        raise newIOError(0, errno, $Error.Read)
    else:
      # Done
      return bytesRead

template asyncWriteImpl() {.dirty.} =
  while true:
    let written = retryOnEIntr: write(s.fd.cint, buf, bufLen)

    if written == -1:
      # On "no buffer space yet" signal
      if errno == EAGAIN or errno == EWOULDBLOCK:
        # Wait until there is space
        wait(s.fd, Event.Write)
      else:
        raise newIOError(0, errno, $Error.Write)
    else:
      # Done
      return written

type
  IP4Impl {.borrow: `.`.} = distinct InAddr
  IP6Impl {.borrow: `.`.} = distinct In6Addr

template ip4Word() {.dirty.} =
  result = ip.s_addr

template ip4SetWord() {.dirty.} =
  ip.s_addr = w

type IP4EndpointImpl {.borrow: `.`.} = distinct Sockaddr_in

template ip4InitEndpoint() {.dirty.} =
  result = IP4EndpointImpl:
    Sockaddr_in(
      sin_family: AF_INET.TSa_Family,
      sin_addr: InAddr(ip),
      sin_port: toBE(port.uint16)
    )

template ip4EndpointAddr() {.dirty.} =
  result = IP4 e.sin_addr

template ip4EndpointPort() {.dirty.} =
  result = Port fromBE(e.sin_port)

type
  ResolverResultImpl* = object
    info: ptr AddrInfo

proc `=destroy`(r: var ResolverResultImpl) =
  if r.info != nil:
    freeaddrinfo(r.info)
    r.info = nil

template ip4Resolve() {.dirty.} =
  result = new ResolverResultImpl

  let hints = AddrInfo(
    ai_family: AF_INET,
    ai_flags: AI_NUMERICSERV or AI_ADDRCONFIG
  )

  let err = getaddrinfo(
    cstring(host),
    if port == PortNone: nil else: cstring($port),
    unsafeAddr hints,
    result.info
  )
   
  if err != 0:
    if err == EAI_SYSTEM:
      raise newOSError(errno, $Error.Resolve)
    else:
      let ex = newException(ResolverError, "")
      ex.errorCode = err
      ex.msg = $gai_strerror(err)
      raise ex

template resolvedItems() {.dirty.} =
  var info = r.info
  while info != nil:
    if info.ai_addr != nil:
      if info.ai_addr.sa_family == AF_INET.TSa_Family:
        yield cast[ptr IP4Endpoint](info.ai_addr)[]

    info = info.ai_next

template tcpConnect() {.dirty.} =
  let sock = makeSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)

  posixChk connect(
    SocketHandle(sock.get),
    cast[ptr Sockaddr](unsafeAddr endpoint),
    SockLen sizeof(endpoint)
  ):
    $Error.Connect

  # Take ownership of the socket from the handle
  result = Conn[TCP] newSocket(sock)

template tcpAsyncConnect() {.dirty.} =
  var sock = makeSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, {sfNonBlock})

  if connect(
    SocketHandle(sock.get),
    cast[ptr Sockaddr](unsafeAddr endpoint),
    SockLen sizeof(endpoint)
  ) == -1:
    # If the connection is happening asynchronously
    if errno == EINPROGRESS:
      # Wait until the socket is writable, which is when it is "connected" (see connect(3p)).
      wait(sock, Event.Write)

      # Examine the SO_ERROR in SOL_SOCKET for any error happened during the asynchronous operation.
      var
        error: cint
        errorLen = SockLen sizeof(error)
      posixChk getsockopt(
        SocketHandle(sock.get), SOL_SOCKET, SO_ERROR, addr error, addr errorLen
      ):
        $Error.Connect

      assert errorLen == SockLen sizeof(error):
        "The length of the error does not match nim-sys assumption. This is a nim-sys bug."

      # Raise the error if any was found.
      if error != 0:
        raise newOSError(error, $Error.Connect)

    else:
      raise newOSError(errno, $Error.Connect)

  # A move has to be done in CPS
  result = AsyncConn[TCP] newAsyncSocket(move sock)

template tcpListen() {.dirty.} =
  let sock = makeSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)

  # Bind the address to the socket
  posixChk bindSocket(
    SocketHandle(sock.get),
    cast[ptr SockAddr](unsafeAddr endpoint),
    SockLen sizeof(endpoint)
  ):
    $Error.Listen

  # Mark the socket as accepting connections
  posixChk listen(SocketHandle(sock.get), 0), $Error.Listen
  
  result = Listener[TCP] newSocket(sock)

template tcpAsyncListen() {.dirty.} =
  var sock = makeSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, {sfNonBlock})

  if bindSocket(
    SocketHandle(sock.get),
    cast[ptr SockAddr](unsafeAddr endpoint),
    SockLen sizeof(endpoint)
  ) == -1:
    # While this is shown in the POSIX manual to be a possible error value, in
    # practice it appears that not many (if any) OS actually implements bind
    # this way (judging from their manuals).
    if errno == EINPROGRESS:
      # Wait until the socket is readable, which is when it is "bound" (see bind(3p)).
      wait(sock, Event.Read)

      # Examine the SO_ERROR in SOL_SOCKET for any error happened during the asynchronous operation.
      var
        error: cint
        errorLen = SockLen sizeof(error)
      posixChk getsockopt(
        SocketHandle(sock.get), SOL_SOCKET, SO_ERROR, addr error, addr errorLen
      ):
        $Error.Connect

      assert errorLen == SockLen sizeof(error):
        "The length of the error does not match nim-sys assumption. This is a nim-sys bug."

      # Raise the error if any was found.
      if error != 0:
        raise newOSError(error, $Error.Listen)
    else:
      raise newOSError(errno, $Error.Listen)

  # Mark the socket as accepting connections
  posixChk listen(SocketHandle(sock.get), 0), $Error.Listen
  
  # An explicit move has to be done in CPS
  result = AsyncListener[TCP] newAsyncSocket(move sock)

proc commonAccept[T](fd: SocketFD, remoteAddr: var T,
                     flags: set[SockFlag] = {}): Handle[SocketFD] =
  ## Light wrapper over `accept` for constructing new sockets.
  ##
  ## Yields handle with InvalidFD on failure in `accept` syscall, raises
  ## otherwise. Check errno for more details.
  result = initHandle(SocketFD InvalidFD)

  when declared(accept4):
    # Extra flags to pass to accept4
    var extraFlags = SOCK_CLOEXEC # disable inheritance by default

    if sfNonBlock in flags:
      extraFlags = extraFlags or SOCK_NONBLOCK

  var remoteLen = SockLen(sizeof remoteAddr)
  let conn = initHandle:
    SocketFD:
      when declared(accept4):
        accept4(
          fd.SocketHandle,
          cast[ptr SockAddr](addr remoteAddr),
          addr remoteLen,
          extraFlags
        )
      else:
        accept(
          fd.SocketHandle,
          cast[ptr SockAddr](addr remoteAddr),
          addr remoteLen
        )

  # Exit if accept failed
  if conn.get == InvalidFD:
    return

  # TODO: Remove this once IPv6 support lands
  #
  # This is used to verify that we are getting IPv4 address.
  assert remoteLen == SockLen(sizeof remoteAddr):
    "The length of the endpoint structure does not match assumption. This is a nim-sys bug."
  assert remoteAddr.sin_family == AF_INET.TSa_Family:
    "The address is not IPv4. This is a nim-sys bug."

  when not declared(accept4):
    # On systems without accept4, flags have to be set manually.
    conn.get.setInheritable(false)

    if sfNonBlock in flags:
      conn.get.setBlocking(false)

  # Return the connection
  result = conn

template tcpAccept() {.dirty.} =
  let conn = commonAccept[IP4Endpoint](l.fd, result.remote)
  if conn.get == InvalidFD:
    raise newOSError(errno, $Error.Accept)

  result.conn = Conn[TCP] newSocket(conn)

template tcpAsyncAccept() {.dirty.} =
  # Loop until we get a connection
  while true:
    var conn = commonAccept[IP4Endpoint](l.fd, result.remote, {sfNonBlock})

    if conn.get == InvalidFD:
      # If the socket signals that no connections are pending
      if errno == EAGAIN or errno == EWOULDBLOCK:
        # Wait until some shows up then try again
        wait(l.fd, Event.Read)
      else:
        raise newOSError(errno, $Error.Accept)
    else:
      # We got a connection
      result.conn = AsyncConn[TCP] newAsyncSocket(move conn)
      return

template tcpLocalEndpoint() {.dirty.} =
  var endpointLen = SockLen sizeof(result)

  posixChk getsockname(
    SocketHandle l.fd,
    cast[ptr SockAddr](addr result),
    addr endpointLen
  ):
    $Error.LocalEndpoint

  assert endpointLen == SockLen sizeof(result):
    "The length of the endpoint structure does not match assumption. This is a nim-sys bug."
  assert result.sin_family == TSa_Family(AF_INET):
    "The address is not IPv4. This is a nim-sys bug."
