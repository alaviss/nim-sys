#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

from std/os import osErrorMsg, OSErrorCode
import syscall/winim/winim/core as wincore except Handle
import syscall/winim/winim/winstr
import ".."/ioqueue/iocp
import errors

func ioSize(x: int): ULONG {.inline.} =
  ## Clamp `x` to the IO size supported by Winsock.
  ULONG min(x, high(ULONG))

template readImpl() {.dirty.} =
  var
    buf =
      if b.len > 0:
        WSABuf(
          len: ioSize(b.len),
          buf: cast[ptr char](addr b[0])
        )
      else:
        WSABuf(
          len: 0,
          buf: nil
        )
    bytesRead: DWORD
    flags: DWORD # This is ignored for now

  if WSARecv(
    wincore.Socket(s.fd), addr buf, 1, addr bytesRead, addr flags, nil, nil
  ) == SocketError:
    raise newIOError(bytesRead, WSAGetLastError(), $Error.Read)

  result = bytesRead

template writeImpl() {.dirty.} =
  var
    buf =
      if b.len > 0:
        WSABuf(
          len: ioSize(b.len),
          buf: cast[ptr char](unsafeAddr b[0])
        )
      else:
        WSABuf(
          len: 0,
          buf: nil
        )
    bytesWritten: DWORD

  if WSASend(
    wincore.Socket(s.fd), addr buf, 1, addr bytesWritten, 0, nil, nil
  ) == SocketError:
    raise newIOError(bytesWritten, WSAGetLastError(), $Error.Write)

  result = bytesWritten

template asyncReadImpl() {.dirty.} =
  # Register the FD as persistent. This is required for IOCP operations.
  persist(s.fd)

  let overlapped = new Overlapped
  var
    errorCode: DWORD = ErrorSuccess
    buf = WSABuf(
      len: ioSize(bufLen),
      buf: cast[ptr char](buf)
    )
    bytesRead: DWORD
    flags: DWORD # This is ignored for now

  if WSARecv(
    wincore.Socket(s.fd), addr buf, 1, addr bytesRead, addr flags,
    cast[ptr Overlapped](addr overlapped[]), nil
  ) == SocketError:
    errorCode = WSAGetLastError()

  # If the operation is running in the background
  if errorCode == WSAIoPending:
    # Wait until the operation completes
    wait(s.fd, overlapped)

    # Obtain the result of the operation
    if WSAGetOverlappedResult(
      wincore.Socket(s.fd),
      cast[ptr Overlapped](addr overlapped[]),
      addr bytesRead,
      fWait = wincore.False,
      addr flags
    ) == wincore.False:
      errorCode = WSAGetLastError()
    else:
      errorCode = ErrorSuccess

  # Raise errors on failure.
  if errorCode != ErrorSuccess:
    raise newIOError(bytesRead, errorCode, $Error.Read)

  result = bytesRead

template asyncWriteImpl() {.dirty.} =
  # Register the FD as persistent. This is required for IOCP operations.
  persist(s.fd)

  let overlapped = new Overlapped
  var
    errorCode: DWORD = ErrorSuccess
    buf = WSABuf(
      len: ioSize(bufLen),
      buf: cast[ptr char](buf)
    )
    bytesWritten: DWORD

  if WSASend(
    wincore.Socket(s.fd), addr buf, 1, addr bytesWritten, 0,
    cast[ptr Overlapped](addr overlapped[]), nil
  ) == SocketError:
    errorCode = WSAGetLastError()

  # If the operation is running in the background
  if errorCode == WSAIoPending:
    # Wait until the operation completes
    wait(s.fd, overlapped)

    # This is not used for writes, but WSAGetOverlappedResult demands it
    var flags: DWORD
    # Obtain the result of the operation
    if WSAGetOverlappedResult(
      wincore.Socket(s.fd),
      cast[ptr Overlapped](addr overlapped[]),
      addr bytesWritten,
      fWait = wincore.False,
      addr flags
    ) == wincore.False:
      errorCode = WSAGetLastError()
    else:
      errorCode = ErrorSuccess

  # Raise errors on failure.
  if errorCode != ErrorSuccess:
    raise newIOError(bytesWritten, errorCode, $Error.Write)

  result = bytesWritten

type
  ResolverResultImpl* = object
    info: ptr AddrInfoW

proc `=destroy`(r: var ResolverResultImpl) =
  if r.info != nil:
    FreeAddrInfoW(r.info)
    r.info = nil

template ip4Resolve() {.dirty.} =
  result = new ResolverResultImpl

  let hints = AddrInfoW(
    ai_flags: AI_ADDRCONFIG,
    ai_family: AF_INET
  )

  let err = GetAddrInfoW(
    # Convert host to wide string then pass the pointer
    &L(host),
    &L($port),
    unsafeAddr hints,
    addr result.info
  )

  if err != ErrorSuccess:
    case err
    # Since Windows use the same error namespace for the resolver and system
    # errors, they are distingused by the fact that they are referenced in MS
    # documentation:
    # https://docs.microsoft.com/en-us/windows/win32/api/ws2tcpip/nf-ws2tcpip-getaddrinfow
    of WSANotEnoughMemory, WSAEAFNOSUPPORT, WSAEINVAL, WSAESOCKTNOSUPPORT,
       WSAHostNotFound, WSANoData, WSANoRecovery, WSATryAgain, WSATypeNotFound:
      let ex = newException(ResolverError, "")
      ex.errorCode = err
      ex.msg = osErrorMsg(OSErrorCode err)
      raise ex
    else:
      raise newOSError(err, $Error.Resolve)

template resolvedItems() {.dirty.} =
  var info = r.info
  while info != nil:
    if info.ai_addr != nil:
      if info.ai_addr.sa_family == AF_INET:
        yield cast[ptr IP4Endpoint](info.ai_addr)[]

    info = info.ai_next

const WSAFlagNoHandleInherit = 0x80.DWORD
  ## Create a non-inheritable socket.
  ##
  ## TODO: upstream this into winim.

type
  SockFlag = enum
    sfOverlapped

func toWSAFlags(flags: set[SockFlag]): DWORD {.inline.} =
  ## Turns `flags` into a DWORD value that can be passed to `WSASocket`
  ##
  ## * Handle inheritance is disabled by default
  result = WSAFlagNoHandleInherit
  if sfOverlapped in flags:
    result = result or WSAFlagOverlapped

var ConnectEx: LPFN_CONNECTEX

template tcpConnect() {.dirty.} =
  let sock = initHandle:
    SocketFD:
      WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, toWSAFlags({}))

  if sock.fd == InvalidFD:
    raise newOSError(WSAGetLastError(), $Error.Connect)

  if connect(
    wincore.Socket(sock.fd),
    cast[ptr sockaddr](unsafeAddr endpoint),
    cint sizeof(endpoint)
  ) == SocketError:
    raise newOSError(WSAGetLastError(), $Error.Connect)

  result = Conn[TCP] newSocket(sock)

template tcpAsyncConnect() {.dirty.} =
  # Use a bare AsyncSocket for this, so that on failure the FD is unregistered.
  let sock = newAsyncSocket:
    SocketFD:
      WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, toWSAFlags({sfOverlapped}))

  if sock.fd == InvalidFD:
    raise newOSError(WSAGetLastError(), $Error.Connect)

  # A local endpoint has to be bound into `sock` before ConnectEx can be used.
  #
  # Bind an "any" address to this so that the system can choose the best local
  # address to use.
  var empty = initEndpoint(IP4Any, PortNone)
  if `bind`(
    wincore.Socket(sock.fd),
    cast[ptr sockaddr](addr empty),
    cint sizeof(empty)
  ) == SocketError:
    raise newOSError(WSAGetLastError(), $Error.Connect)

  # Register `sock` into IOCP
  persist(sock.fd)

  let overlapped = new Overlapped
  var errorCode: DWORD = ErrorSuccess
  if ConnectEx(
    wincore.Socket(sock.fd),
    cast[ptr sockaddr](unsafeAddr endpoint),
    cint sizeof(endpoint),
    nil,
    0,
    nil,
    cast[ptr Overlapped](addr overlapped[])
  ) == SocketError:
    errorCode = WSAGetLastError()

  if errorCode == WSAIoPending:
    # Wait for the operation to complete
    wait(sock.fd, overlapped)

    # These are required by WSAGetOverlappedResult(), but unused in this
    # situation.
    var transferred, flags: DWORD
    if WSAGetOverlappedResult(
      wincore.Socket(sock.fd),
      cast[ptr Overlapped](addr overlapped[]),
      addr transferred,
      fWait = wincore.False,
      addr flags
    ) == SocketError:
      errorCode = WSAGetLastError()
    else:
      errorCode = ErrorSuccess

  if errorCode != ErrorSuccess:
    raise newOSError(errorCode, $Error.Connect)

  # After ConnectEx, SO_UPDATE_CONNECT_CONTEXT has to be set for shutdown,
  # getpeername, getsockname to work.
  #
  # https://docs.microsoft.com/en-us/windows/win32/winsock/sol-socket-socket-options
  if setsockopt(
    wincore.Socket(sock.fd),
    SolSocket,
    SoUpdateConnectContext,
    nil,
    0
  ) == SocketError:
    raise newOSError(WSAGetLastError(), $Error.Connect)

  result = AsyncConn[TCP] sock

template tcpListen() {.dirty.} =
  var sock = initHandle:
    SocketFD:
      WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, toWSAFlags({}))

  if sock.fd == InvalidFD:
    raise newOSError(WSAGetLastError(), $Error.Listen)

  # Bind the address to the socket
  if `bind`(
    wincore.Socket(sock.fd),
    cast[ptr sockaddr](unsafeAddr endpoint),
    cint sizeof(endpoint)
  ) == SocketError:
    raise newOSError(WSAGetLastError(), $Error.Listen)

  # Mark the socket as accepting connections
  if listen(
    wincore.Socket(sock.fd), backlog.get(SOMAXCONN).cint
  ) == SocketError:
    raise newOSError(WSAGetLastError(), $Error.Listen)

  result = Listener[TCP] newSocket(sock)

template tcpAsyncListen() {.dirty.} =
  var sock = initHandle:
    SocketFD:
      WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, toWSAFlags({sfOverlapped}))

  if sock.fd == InvalidFD:
    raise newOSError(WSAGetLastError(), $Error.Listen)

  # Bind the address to the socket
  if `bind`(
    wincore.Socket(sock.fd),
    cast[ptr sockaddr](unsafeAddr endpoint),
    cint sizeof(endpoint)
  ) == SocketError:
    raise newOSError(WSAGetLastError(), $Error.Listen)

  # Mark the socket as accepting connections
  if listen(
    wincore.Socket(sock.fd), backlog.get(SOMAXCONN).cint
  ) == SocketError:
    raise newOSError(WSAGetLastError(), $Error.Listen)

  result = AsyncListener[TCP] newAsyncSocket(move sock)

{.warning: "cps issue workaround; see https://github.com/nim-works/cps/issues/260".}
const
  # The extra 16 bytes is required by the API. SockaddrStorage is used
  # because its the largest possible size.
  AcceptExLocalLength = sizeof(SockaddrStorage) + 16
  AcceptExRemoteLength = sizeof(SockaddrStorage) + 16
  AcceptExBufferLength = AcceptExLocalLength + AcceptExRemoteLength

template acceptCommon(listener: SocketFD, conn: var Handle[SocketFD],
                      remote: var IP4Endpoint, overlapped: static bool) =
  # Common parts for dealing with AcceptEx, `overlapped` dictates whether the
  # operation should be done in an overlapped manner and yields an overlapped
  # socket.
  conn = initHandle:
    SocketFD:
      WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0):
        toWSAFlags:
          when overlapped:
            {sfOverlapped}
          else:
            {}

  if conn.fd == InvalidFD:
    raise newOSError(WSAGetLastError(), $Error.Accept)

  var
    buf: array[AcceptExBufferLength, byte]
    # unused since the receive function is not used but is required
    received: DWORD
    overlapObj = new Overlapped

  when overlapped:
    # Register the listener to IOCP so asynchronous operations can be done.
    persist(listener)

  if AcceptEx(
    wincore.Socket(listener),
    wincore.Socket(conn.fd),
    addr buf[0],
    0,
    AcceptExLocalLength,
    AcceptExRemoteLength,
    addr received,
    cast[ptr Overlapped](addr overlapObj[])
  ) == wincore.False:
    var errorCode = WSAGetLastError()

    when overlapped:
      # If the operation is being done asynchronously
      if errorCode == WSAIoPending:
        # Wait for its completion
        wait(listener, overlapObj)

        var flags: DWORD # unused but required
        # Get the operation result
        if WSAGetOverlappedResult(
          wincore.Socket(listener),
          cast[ptr Overlapped](addr overlapObj[]),
          addr received,
          fWait = wincore.False,
          addr flags
        ) == wincore.False:
          errorCode = WSAGetLastError()
        else:
          errorCode = ErrorSuccess

    else:
      assert errorCode != WSAIoPending:
        "AcceptEx yields IO_PENDING for non-overlapped socket, this is a nim-sys bug"

    if errorCode != ErrorSuccess:
      raise newOSError(errorCode, $Error.Accept)

  var
    # We don't use the "local" part but the "remote" part is used
    localAddrLength, remoteAddrLength: cint
    # Slices of the buffer for local and remote addresses
    localAddr, remoteAddr: ptr Sockaddr

  GetAcceptExSockaddrs(
    addr buf[0],
    0, AcceptExLocalLength, AcceptExRemoteLength,
    addr localAddr, addr localAddrLength,
    addr remoteAddr, addr remoteAddrLength
  )

  # TODO: Remove this once IPv6 support lands
  #
  # This is used to verify that we are getting IPv4 address.
  assert remoteAddrLength == sizeof remote:
    "The length of the endpoint structure does not match assumption. This is a nim-sys bug."
  assert remoteAddr.sa_family == AF_INET:
    "The address is not IPv4. This is a nim-sys bug."

  # Copy the remote address
  remote = cast[ptr IP4Endpoint](remoteAddr)[]

  # Update the connection attributes so that other functions can be used on the
  # socket.
  var listenerSock = listener
  if setsockopt(
    wincore.Socket(conn.fd),
    SolSocket,
    SoUpdateAcceptContext,
    cast[cstring](addr listenerSock),
    cint sizeof(listenerSock)
  ) == SocketError:
    raise newOSError(WSAGetLastError(), $Error.Accept)

template tcpAccept() {.dirty.} =
  var conn = initHandle(SocketFD InvalidFD)
  acceptCommon(l.fd, conn, result.remote, overlapped = false)
  result.conn = Conn[TCP] newSocket(conn)

template tcpAsyncAccept() {.dirty.} =
  var conn = initHandle(SocketFD InvalidFD)
  acceptCommon(l.fd, conn, result.remote, overlapped = true)
  result.conn = AsyncConn[TCP] newAsyncSocket(move conn)

template tcpLocalEndpoint() {.dirty.} =
  var endpointLen = cint sizeof(result)

  if getsockname(
    wincore.Socket(l.fd),
    cast[ptr sockaddr](addr result),
    addr endpointLen
  ) == SocketError:
    raise newOSError(WSAGetLastError(), $Error.LocalEndpoint)

  assert endpointLen == sizeof(result):
    "The length of the endpoint structure does not match assumption. This is a nim-sys bug."
  assert result.sin_family == AF_INET:
    "The address is not IPv4. This is a nim-sys bug."

proc initWinsock() =
  ## Initializes winsock for use with sys/sockets
  var data: WSAData
  # Request Windows Sockets version 2.2, which is the latest at the time of
  # writing.
  let errorCode = WSAStartup(MakeWord(2, 2), addr data)

  if errorCode != 0:
    raise newOSError(errorCode, "Unable to initialize Windows Sockets")

  # If the version is older than winsock 2.2 (note: DLLs supporting newer
  # version will still report 2.2 since that's what was requested)
  if data.wVersion != MakeWord(2, 2):
    # Cleanup then raise
    WSACleanup()
    raise newException(CatchableError, "Unable to find an usable Windows Sockets version")

  # Create a dummy socket so we can obtain necessary functions
  let dummy = initHandle:
    SocketFD:
      WSASocketW(AF_INET, SOCK_STREAM, 0, nil, 0, toWSAFlags({}))

  if dummy.fd == InvalidFD:
    raise newOSError(WSAGetLastError(), "Could not initialize sys/sockets")

  # Obtain the function pointer for ConnectEx
  var
    fnGuid = WSAID_CONNECTEX
    bytesReturned: DWORD
  if WSAIoctl(
    wincore.Socket(dummy.fd),
    SIO_GET_EXTENSION_FUNCTION_POINTER,
    addr fnGuid,
    DWORD sizeof(fnGuid),
    addr ConnectEx,
    DWORD sizeof(ConnectEx),
    addr bytesReturned,
    nil,
    nil
  ) == SocketError:
    raise newOSError(WSAGetLastError(), "Could not get pointer to ConnectEx")

  assert bytesReturned == sizeof(ConnectEx):
    "Wrong size returned for function pointer. This is a nim-sys bug."

# Initialize winsock on program startup.
initWinsock()
