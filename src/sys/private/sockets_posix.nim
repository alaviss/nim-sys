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
  if sock.fd == InvalidFD:
    raise newOSError(errno)

  when defined(macosx):
    # OSX does not support setting cloexec and nonblock on socket creation, so
    # it has to be done here.
    setInheritable(sock.fd, false)

    if sfNonBlock in flags:
      setBlocking(sock.fd, false)

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
  ResolverResultImpl* = object
    info: ptr AddrInfo

proc `=destroy`(r: var ResolverResultImpl) =
  if r.info != nil:
    freeaddrinfo(r.info)
    r.info = nil

template ipResolve() {.dirty.} =
  result = new ResolverResultImpl

  let
    hints = AddrInfo(
      ai_family:
        if isNone(kind):
          AF_UNSPEC
        else:
          case kind.get
          of V4: AF_INET
          of V6: AF_INET6,
      ai_flags: AI_NUMERICSERV
    )
    portStr = if port == PortNone: "" else: $port

  let err = getaddrinfo(
    cstring(host),
    cstring(portStr),
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
        yield IPEndpoint(kind: V4, v4: cast[ptr IP4Endpoint](info.ai_addr)[])
      elif info.ai_addr.sa_family == AF_INET6.TSa_Family:
        yield IPEndpoint(kind: V6, v6: cast[ptr IP6Endpoint](info.ai_addr)[])
      else:
        discard "Should not be possible, but harmless even if it is"

    info = info.ai_next

proc handleAsyncConnectResult(fd: SocketFD) {.raises: [OSError].} =
  ## Raise errors from an asynchronous connection on `fd`, if any.
  # Examine the SO_ERROR in SOL_SOCKET for any error happened during the asynchronous operation.
  var
    error: cint
    errorLen = SockLen sizeof(error)
  posixChk getsockopt(
    SocketHandle(fd), SOL_SOCKET, SO_ERROR, addr error, addr errorLen
  ):
    $Error.Connect

  assert errorLen == SockLen sizeof(error):
    "The length of the error does not match nim-sys assumption. This is a nim-sys bug."

  # Raise the error if any was found.
  if error != 0:
    raise newOSError(error, $Error.Connect)

template socketConnect(endpoint: untyped; sock: Handle[SocketFD]) =
  if connect(
    SocketHandle(sock.fd),
    cast[ptr Sockaddr](unsafeAddr endpoint),
    SockLen sizeof(endpoint)
  ) == -1:
    # On EINTR, the connection will be done asynchronously
    if errno == EINTR:
      # Block until its done
      var pollfd = TPollfd(fd: sock.fd.cint, events: PollOut)
      let pollRet = retryOnEIntr: poll(addr pollfd, 1, -1)
      if pollRet == -1:
        raise newOSError(errno, $Error.Connect)

      handleAsyncConnectResult(sock.fd)
    else:
      raise newOSError(errno, $Error.Connect)

template tcpConnect() {.dirty.} =
  let addressFamily =
    when endpoint is IP4Endpoint:
      AF_INET
    elif endpoint is IP6Endpoint:
      AF_INET6
  let sock = makeSocket(addressFamily, SOCK_STREAM, IPPROTO_TCP)
  socketConnect(endpoint, sock)

  # Take ownership of the socket from the handle
  result = Conn[TCP] newSocket(sock)

template socketAsyncConnect(endpoint: untyped; sock: Handle[SocketFD]) =
  if connect(
    SocketHandle(sock.fd),
    cast[ptr Sockaddr](unsafeAddr endpoint),
    SockLen sizeof(endpoint)
  ) == -1:
    # If the connection is happening asynchronously
    if errno == EINPROGRESS or errno == EINTR:
      # Wait until the socket is writable, which is when it is "connected" (see connect(3p)).
      wait(sock, Event.Write)

      handleAsyncConnectResult(sock.fd)
    else:
      raise newOSError(errno, $Error.Connect)

template tcpAsyncConnect() {.dirty.} =
  let addressFamily =
    when endpoint is IP4Endpoint:
      AF_INET
    elif endpoint is IP6Endpoint:
      AF_INET6
  var sock = makeSocket(addressFamily, SOCK_STREAM, IPPROTO_TCP, {sfNonBlock})
  socketAsyncConnect(endpoint, sock)

  # A move has to be done in CPS
  result = AsyncConn[TCP] newAsyncSocket(move sock)

func maxBacklog(): Natural =
  ## Retrieve the maximum backlog value for the target OS
  when defined(linux) or defined(macosx) or defined(bsd):
    # There operating systems will automatically clamp the value to the system
    # maximum.
    high(cint)
  else:
    # For others, use SOMAXCONN.
    #
    # Mark as noSideEffect since this is a C constant but declared in Nim as a
    # variable.
    {.noSideEffect.}:
      SOMAXCONN

template socketListen() {.dirty.} =
  # Bind the address to the socket
  posixChk bindSocket(
    SocketHandle(sock.fd),
    cast[ptr SockAddr](unsafeAddr endpoint),
    SockLen sizeof(endpoint)
  ):
    $Error.Listen

  # Mark the socket as accepting connections
  posixChk listen(SocketHandle(sock.fd), backlog.get(maxBacklog()).cint):
    $Error.Listen

template tcpListen() {.dirty.} =
  let addressFamily =
    when endpoint is IP4Endpoint:
      AF_INET
    elif endpoint is IP6Endpoint:
      AF_INET6

  var sock = makeSocket(addressFamily, SOCK_STREAM, IPPROTO_TCP)

  socketListen()

  result = Listener[TCP] newSocket(sock)

template socketAsyncListen() {.dirty.} =
  if bindSocket(
    SocketHandle(sock.fd),
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
        SocketHandle(sock.fd), SOL_SOCKET, SO_ERROR, addr error, addr errorLen
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
  posixChk listen(SocketHandle(sock.fd), backlog.get(maxBacklog()).cint):
    $Error.Listen

template tcpAsyncListen() {.dirty.} =
  let addressFamily =
    when endpoint is IP4Endpoint:
      AF_INET
    elif endpoint is IP6Endpoint:
      AF_INET6

  var sock = makeSocket(addressFamily, SOCK_STREAM, IPPROTO_TCP, {sfNonBlock})

  socketAsyncListen()

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
      retryOnEIntr:
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
  if conn.fd == InvalidFD:
    return

  assert remoteLen <= SockLen(sizeof remoteAddr):
    "The length of the endpoint structure is bigger than expected size. This is a nim-sys bug."

  when not declared(accept4):
    # On systems without accept4, flags have to be set manually.
    conn.fd.setInheritable(false)

    if sfNonBlock in flags:
      conn.fd.setBlocking(false)

  # Return the connection
  result = conn

template tcpAccept() {.dirty.} =
  var saddr: SockaddrStorage
  let conn = commonAccept(l.fd, saddr)
  if conn.fd == InvalidFD:
    raise newOSError(errno, $Error.Accept)

  result.conn = Conn[TCP] newSocket(conn)
  if saddr.ss_family == AF_INET.TSa_Family:
    result.remote = IPEndpoint(kind: V4, v4: cast[IP4Endpoint](saddr))
  elif saddr.ss_family == AF_INET6.TSa_Family:
    result.remote = IPEndpoint(kind: V6, v6: cast[IP6Endpoint](saddr))
  else:
    doAssert false, "Unexpected remote address family: " & $saddr.ss_family

template tcpAsyncAccept() {.dirty.} =
  # Loop until we get a connection
  while true:
    var saddr: SockaddrStorage
    var conn = commonAccept(l.fd, saddr, {sfNonBlock})

    if conn.fd == InvalidFD:
      # If the socket signals that no connections are pending
      if errno == EAGAIN or errno == EWOULDBLOCK:
        # Wait until some shows up then try again
        wait(l.fd, Event.Read)
      else:
        raise newOSError(errno, $Error.Accept)
    else:
      # We got a connection
      result.conn = AsyncConn[TCP] newAsyncSocket(move conn)
      if saddr.ss_family == AF_INET.TSa_Family:
        result.remote = IPEndpoint(kind: V4, v4: cast[IP4Endpoint](saddr))
      elif saddr.ss_family == AF_INET6.TSa_Family:
        result.remote = IPEndpoint(kind: V6, v6: cast[IP6Endpoint](saddr))
      else:
        doAssert false, "Unexpected remote address family: " & $saddr.ss_family
      return

template tcpLocalEndpoint() {.dirty.} =
  var
    saddr: SockaddrStorage
    endpointLen = SockLen sizeof(saddr)

  posixChk getsockname(
    SocketHandle l.fd,
    cast[ptr SockAddr](addr saddr),
    addr endpointLen
  ):
    $Error.LocalEndpoint

  assert endpointLen <= SockLen(sizeof saddr):
    "The length of the endpoint structure is bigger than expected size. This is a nim-sys bug."

  if saddr.ss_family == TSa_Family(AF_INET):
    result = IPEndpoint(kind: V4, v4: cast[IP4Endpoint](saddr))
  elif saddr.ss_family == TSa_Family(AF_INET6):
    result = IPEndpoint(kind: V6, v6: cast[IP6Endpoint](saddr))
  else:
    doAssert false, "Unexpected remote address family: " & $saddr.ss_family

proc makeUnixSockaddr(path: string): Sockaddr_un =
  result.sun_family = AF_UNIX.TSa_Family
  if path.len >= Sockaddr_un_path_length:
    raise newOSError(ENAMETOOLONG, "socket path too long")
  copyMem(addr result.sun_path[0], addr path[0], path.len)

template unixConnect() {.dirty.} =
  var
    sock = makeSocket(AF_UNIX, SOCK_STREAM, 0)
    endpoint = makeUnixSockaddr(path)
  socketConnect(endpoint, sock)
  # A move has to be done in CPS
  result = Conn[Unix] newAsyncSocket(move sock)

template unixAsyncConnect() {.dirty.} =
  var
    endpoint = makeUnixSockaddr(path)
    sock = makeSocket(AF_UNIX, SOCK_STREAM, 0, {sfNonBlock})
  socketAsyncConnect(endpoint, sock)

  # A move has to be done in CPS
  result = AsyncConn[Unix] newAsyncSocket(move sock)

template unixListen() {.dirty.} =
  var
    endpoint = makeUnixSockaddr(path)
    sock = makeSocket(AF_UNIX, SOCK_STREAM, 0)
  socketListen()
  result = Listener[Unix] newSocket(sock)

template unixAsyncListen() {.dirty.} =
  var
    endpoint = makeUnixSockaddr(path)
    sock = makeSocket(AF_UNIX, SOCK_STREAM, 0, {sfNonBlock})
  socketAsyncListen()
  # An explicit move has to be done in CPS
  result = AsyncListener[Unix] newAsyncSocket(move sock)

template unixAccept() {.dirty.} =
  var handle = initHandle:
    SocketFD:
      retryOnEIntr:
        when declared(accept4):
          let flags = SOCK_CLOEXEC
          accept4(l.fd.SocketHandle, nil, nil, flags)
        else:
          accept(l.fd.SocketHandle, nil, nil)
  if handle.fd == InvalidFD:
    raise newOSError(errno, $Error.Accept)
  when not declared(accept4):
    handle.fd.setInheritable(false)
  result = Conn[Unix] newSocket(handle)

template unixAsyncAccept() {.dirty.} =
  while true:
    var handle = initHandle:
      SocketFD:
        retryOnEIntr:
          when declared(accept4):
            let flags = SOCK_CLOEXEC or SOCK_NONBLOCK
            accept4(l.fd.SocketHandle, nil, nil, flags)
          else:
            accept(l.fd.SocketHandle, nil, nil)
    if handle.fd == InvalidFD:
      if errno == EAGAIN or errno == EWOULDBLOCK:
        wait(l.fd, Event.Read)
      else:
        raise newOSError(errno, $Error.Accept)
    else:
      when not declared(accept4):
        handle.fd.setInheritable(false)
        handle.fd.setBlocking(false)
      result = AsyncConn[Unix] newAsyncSocket(move handle)
      return
