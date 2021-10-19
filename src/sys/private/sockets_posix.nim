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

proc makeSocket(domain, typ, proto: cint, flags: set[SockFlag] = {}): SocketFD =
  var stype = typ

  when not defined(macosx):
    # OSX does not support setting cloexec and nonblock on the same socket
    stype = stype or SOCK_CLOEXEC

    if sfNonBlock in flags:
      stype = stype or SOCK_NONBLOCK

  result = SocketFD socket(domain, stype, proto)
  posixChk cint(result)

  # In the case where any of the following steps fail, we want to close
  # the FD to prevent leaks.
  var success = false
  defer:
    if not success:
      close result

  when defined(macosx):
    setInheritable(result, false)

    if sfNonBlock in flags:
      setBlocking(result, false)

  success = true

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

  # Close the socket if the connection attempt was unsuccessful
  var success = false
  defer:
    if not success:
      close sock

  posixChk connect(
    SocketHandle(sock),
    cast[ptr Sockaddr](unsafeAddr endpoint),
    SockLen sizeof(endpoint)
  ):
    $Error.Connect

  result = Conn[TCP] newSocket(sock)
  success = true

template tcpAsyncConnect() {.dirty.} =
  let sock = makeSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, {sfNonBlock})

  # Close the socket if the connection attempt was unsuccessful
  var success = false
  defer:
    if not success:
      close sock

  if connect(SocketHandle(sock), cast[ptr Sockaddr](unsafeAddr endpoint), SockLen sizeof(endpoint)) == -1:
    # The connection is happening asynchronously
    if errno == EINPROGRESS:
      # Wait until the socket is writable, which is when it is "connected" (see connect(3p)).
      wait(sock, Event.Write)

      # Examine the SO_ERROR in SOL_SOCKET for any error happened during the asynchronous operation.
      var
        error: cint
        errorLen = SockLen sizeof(error)
      posixChk getsockopt(
        SocketHandle(sock), SOL_SOCKET, SO_ERROR, addr error, addr errorLen
      ):
        $Error.Connect

      assert errorLen == SockLen sizeof(error):
        "The length of the error does not match nim-sys assumption. This is a nim-sys bug."

      # Raise the error if any was found.
      if error != 0:
        raise newOSError(error, $Error.Connect)
    else:
      posixChk -1, $Error.Connect

  result = AsyncConn[TCP] newAsyncSocket(sock)
  success = true

template tcpListen() {.dirty.} =
  let sock = makeSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)

  # Close the socket if the attempt was unsuccessful
  var success = false
  defer:
    if not success:
      close sock

  # Bind the address to the socket
  posixChk bindSocket(
    SocketHandle sock, cast[ptr SockAddr](unsafeAddr endpoint), SockLen sizeof(endpoint)
  ):
    $Error.Listen

  # Mark the socket as accepting connections
  posixChk listen(SocketHandle sock, 0), $Error.Listen
  
  result = Listener[TCP] newSocket(sock)
  success = true

template tcpAsyncListen() {.dirty.} =
  let sock = makeSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, {sfNonBlock})

  # Close the socket if the attempt was unsuccessful
  var success = false
  defer:
    if not success:
      close sock

  if bindSocket(
    SocketHandle sock, cast[ptr SockAddr](unsafeAddr endpoint), SockLen sizeof(endpoint)
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
        SocketHandle(sock), SOL_SOCKET, SO_ERROR, addr error, addr errorLen
      ):
        $Error.Connect

      assert errorLen == SockLen sizeof(error):
        "The length of the error does not match nim-sys assumption. This is a nim-sys bug."

      # Raise the error if any was found.
      if error != 0:
        raise newOSError(error, $Error.Listen)

  # Mark the socket as accepting connections
  posixChk listen(SocketHandle sock, 0), $Error.Listen
  
  result = AsyncListener[TCP] newAsyncSocket(sock)
  success = true

template tcpAccept() {.dirty.} =
  var remoteLen = SockLen sizeof(result.remote)

  let conn = SocketFD:
    when not defined(macosx):
      accept4(l.fd.SocketHandle, cast[ptr SockAddr](addr result.remote), addr remoteLen, SOCK_CLOEXEC)
    else:
      accept(l.fd.SocketHandle, cast[ptr SockAddr](addr result.remote), addr remoteLen)

  posixChk cint(conn), $Error.Accept

  # On failure close the connection
  var success = false
  defer:
    if not success:
      close conn

  assert remoteLen == SockLen sizeof(result.remote):
    "The length of the endpoint structure does not match assumption. This is a nim-sys bug."
  assert result.remote.sin_family == AF_INET.TSa_Family:
    "The address is not IPv4. This is a nim-sys bug."

  when defined(macosx):
    # OSX does not support the accept4 interface, so we have to set the
    # properties manually.
    conn.setInheritable(false)

  result.conn = Conn[TCP] newSocket(conn)
  success = true

template tcpAsyncAccept() {.dirty.} =
  var
    conn = SocketFD InvalidFD
    remoteLen: SockLen

  # Loop until we get a connection
  while true:
    remoteLen = SockLen sizeof(result.remote)

    conn = SocketFD:
      when not defined(macosx):
        accept4(l.fd.SocketHandle, cast[ptr SockAddr](addr result.remote), addr remoteLen, SOCK_CLOEXEC or SOCK_NONBLOCK)
      else:
        accept(l.fd.SocketHandle, cast[ptr SockAddr](addr result.remote), addr remoteLen)

    if conn == InvalidFD:
      # If the socket signals that no connections are pending
      if errno == EAGAIN or errno == EWOULDBLOCK:
        # Wait until some shows up then try again
        wait(l.fd, Event.Read)
      else:
        posixChk -1, $Error.Accept
    else:
      # We got a connection
      break

  # On failure close the connection
  var success = false
  defer:
    if not success:
      close conn

  assert remoteLen == SockLen sizeof(result.remote):
    "The length of the endpoint structure does not match assumption. This is a nim-sys bug."
  assert result.remote.sin_family == AF_INET.TSa_Family:
    "The address is not IPv4. This is a nim-sys bug."

  when defined(macosx):
    # OSX does not support the accept4 interface, so we have to set the
    # properties manually.
    conn.setInheritable(false)
    conn.setBlocking(false)

  result.conn = AsyncConn[TCP] newSocket(conn)
  success = true

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
