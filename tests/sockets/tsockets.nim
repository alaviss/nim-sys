import std/[locks, strutils, options]
import pkg/balls
import sys/[files, ioqueue, sockets]
import ".."/helpers/io

makeAccRead(AsyncConn[TCP])
makeAccWrite(AsyncConn[TCP])
makeDelimRead(AsyncConn[TCP])

when defined(posix):
  from std/tempfiles import genTempPath
  from std/posix import unlink
  makeAccRead(AsyncConn[Unix])
  makeAccWrite(AsyncConn[Unix])
  makeDelimRead(AsyncConn[Unix])

proc getEphemeralPort(kind: IPEndpointKind): Port =
  let endpoint =
    case kind
    of V4: IPEndpoint(kind: V4, v4: initEndpoint(IP4Any, PortNone))
    of V6: IPEndpoint(kind: V6, v6: initEndpoint(IP6Any, PortNone))

  let listener = listenTcp(endpoint, some(1.Natural))
  defer: close listener # to appease refc
  let lendpoint = listener.localEndpoint

  result =
    case lendpoint.kind
    of V4: lendpoint.v4.port
    of V6: lendpoint.v6.port

suite "TCP sockets":
  test "Listening on TCP port 0 will create a random port":
    let server = listenTcp(IP4Loopback, PortNone)
    check server.localEndpoint.v4.port != PortNone

    proc checkAsync() {.asyncio.} =
      let asyncServer = listenTcpAsync(IP4Loopback, PortNone)
      check asyncServer.localEndpoint.v4.port != PortNone
      check asyncServer.localEndpoint.v4.port != server.localEndpoint.v4.port

    checkAsync()
    run()

  test "Listening on an explicit TCP port":
    let port = getEphemeralPort(V4)

    let server = listenTcp(IP4Loopback, port)
    check server.localEndpoint.v4.port == port
    close server

    proc checkAsync() {.asyncio.} =
      let asyncServer = listenTcpAsync(IP4Loopback, port)
      check asyncServer.localEndpoint.v4.port == port

    checkAsync()
    run()

  test "Listening on an explicit TCP port with IPv6":
    let port = getEphemeralPort(V6)

    let server = listenTcp(IP6Loopback, port)
    check server.localEndpoint.v6.port == port
    close server

    proc checkAsync() {.asyncio.} =
      let asyncServer = listenTcpAsync(IP6Loopback, port)
      check asyncServer.localEndpoint.v6.port == port

    checkAsync()
    run()

  test "Listening/connecting on/to localhost":
    # The main point of this test is to make sure that the name-based API works.
    proc acceptWorker(s: ptr Listener[TCP]) {.thread.} =
      {.gcsafe.}:
        # Accept then close connection immediately
        close s[].accept().conn

    var server = listenTcp("localhost", PortNone, kind = some(V4))
    check server.localEndpoint.v4.port != PortNone
    var thr: Thread[ptr Listener[TCP]]
    thr.createThread(acceptWorker, addr server)

    # Connect then disconnect immediately
    close connectTcp("localhost", server.localEndpoint.v4.port)

    # Close the thread
    joinThread thr

    proc acceptWorker(s: AsyncListener[TCP]) {.asyncio.} =
      # Accept then close connection immediately
      close s.accept().conn

    proc checkAsync() {.asyncio.} =
      let asyncServer = listenTcpAsync("localhost", PortNone, kind = some(V4))
      # Run until the worker dismisses to the background
      discard trampoline:
        whelp acceptWorker(asyncServer)

      check asyncServer.localEndpoint.v4.port != PortNone
      check asyncServer.localEndpoint.v4.port != server.localEndpoint.v4.port
      # Connect then disconnect immediately
      close connectTcpAsync("localhost", asyncServer.localEndpoint.v4.port)

    checkAsync()
    run()

  test "Listening/connecting on/to localhost with set port":
    var port = getEphemeralPort(V4)
    # The main point of this test is to make sure that the name-based API works.
    proc acceptWorker(s: ptr Listener[TCP]) {.thread.} =
      {.gcsafe.}:
        # Accept then close connection immediately
        close s[].accept().conn

    var server = listenTcp("localhost", port, kind = some(V4))
    defer: close server
    check server.localEndpoint.v4.port == port
    var thr: Thread[ptr Listener[TCP]]
    thr.createThread(acceptWorker, addr server)

    # Connect then disconnect immediately
    close connectTcp("localhost", port)

    # Close the thread
    joinThread thr

    # Get a new port because macOS TIME_WAIT is too long
    port = getEphemeralPort(V4)
    proc acceptWorker(s: AsyncListener[TCP]) {.asyncio.} =
      # Accept then close connection immediately
      close s.accept().conn

    proc checkAsync() {.asyncio.} =
      let asyncServer = listenTcpAsync("localhost", port, kind = some(V4))
      # Run until the worker dismisses to the background
      discard trampoline:
        whelp acceptWorker(asyncServer)

      check asyncServer.localEndpoint.v4.port == port
      # Connect then disconnect immediately
      close connectTcpAsync("localhost", port)

    checkAsync()
    run()

  test "Listening/connecting on/to localhost with IPv6":
    # The main point of this test is to make sure that the name-based API works.
    proc acceptWorker(s: ptr Listener[TCP]) {.thread.} =
      {.gcsafe.}:
        # Accept then close connection immediately
        close s[].accept().conn

    var server = listenTcp("localhost", PortNone, kind = some(V6))
    check server.localEndpoint.v6.port != PortNone
    var thr: Thread[ptr Listener[TCP]]
    thr.createThread(acceptWorker, addr server)

    # Connect then disconnect immediately
    close connectTcp("localhost", server.localEndpoint.v6.port)

    # Close the thread
    joinThread thr

    proc acceptWorker(s: AsyncListener[TCP]) {.asyncio.} =
      # Accept then close connection immediately
      close s.accept().conn

    proc checkAsync() {.asyncio.} =
      let asyncServer = listenTcpAsync("localhost", PortNone, kind = some(V6))
      # Run until the worker dismisses to the background
      discard trampoline:
        whelp acceptWorker(asyncServer)

      check asyncServer.localEndpoint.v6.port != PortNone
      check asyncServer.localEndpoint.v6.port != server.localEndpoint.v6.port
      # Connect then disconnect immediately
      close connectTcpAsync("localhost", asyncServer.localEndpoint.v6.port)

    checkAsync()
    run()

  test "Listening/connecting on/to localhost with set port on IPv6":
    var port = getEphemeralPort(V6)

    # The main point of this test is to make sure that the name-based API works.
    proc acceptWorker(s: ptr Listener[TCP]) {.thread.} =
      {.gcsafe.}:
        # Accept then close connection immediately
        close s[].accept().conn

    var server = listenTcp("localhost", port, kind = some(V6))
    defer: close server
    check server.localEndpoint.v6.port == port
    var thr: Thread[ptr Listener[TCP]]
    thr.createThread(acceptWorker, addr server)

    # Connect then disconnect immediately
    close connectTcp("localhost", port)

    # Close the thread
    joinThread thr

    # Get a new port because macOS TIME_WAIT is too long
    port = getEphemeralPort(V6)
    proc acceptWorker(s: AsyncListener[TCP]) {.asyncio.} =
      # Accept then close connection immediately
      close s.accept().conn

    proc checkAsync() {.asyncio.} =
      let asyncServer = listenTcpAsync("localhost", port, kind = some(V6))
      # Run until the worker dismisses to the background
      discard trampoline:
        whelp acceptWorker(asyncServer)

      check asyncServer.localEndpoint.v6.port == port
      # Connect then disconnect immediately
      close connectTcpAsync("localhost", port)

    checkAsync()
    run()

  test "Listener[TCP] listening on same endpoint error":
    let server = listenTcp(IP4Loopback, PortNone)

    expect OSError:
      discard listenTcp(server.localEndpoint)

  test "AsyncListener[TCP] listening on same endpoint error":
    proc runner() {.asyncio.} =
      let server = listenTcpAsync(IP4Loopback, PortNone)

      expect OSError:
        discard listenTcpAsync(server.localEndpoint)

    runner()
    run()

  test "Conn[TCP] EOF read":
    proc acceptWorker(srv: ptr Listener[TCP]) {.thread.} =
      ## A server that accept a connection then drops it
      ## immediately
      {.gcsafe.}:
        close srv[].accept().conn

    var server = listenTcp(IP4Loopback, PortNone)
    var thr: Thread[ptr Listener[TCP]]
    # Launch a thread to act as the server accepting connections.
    thr.createThread(acceptWorker, addr server)

    # Connect to the server
    let client = connectTcp(server.localEndpoint)
    # Wait until the worker stops
    joinThread(thr)

    # Our connection should be dropped and reading should yields nothing.
    var str = newString(10)
    check client.read(str) == 0

  test "Conn[TCP] EOF write with big buffers":
    proc acceptWorker(srv: ptr Listener[TCP]) {.thread.} =
      ## A server that accept a connection then drops it
      ## immediately
      {.gcsafe.}:
        close srv[].accept().conn

    var server = listenTcp(IP4Loopback, PortNone)
    var thr: Thread[ptr Listener[TCP]]
    # Launch a thread to act as the server accepting connections.
    thr.createThread(acceptWorker, addr server)

    # Connect to the server
    let client = connectTcp(server.localEndpoint)
    # Wait until the worker stops
    joinThread(thr)

    # Our connection should be dropped and writing should error.
    #
    # It is expected that there might be some data written due
    # to operating system maintaining a local buffer.
    expect files.IOError:
      # Some repeats will be necessary as some operating systems buffers data
      # and won't trigger a send immediately, thus not raising the error.
      for _ in 1 .. 10:
        discard client.write(TestBufferedData)

  test "Conn[TCP] zero read":
    var l: Lock
    initLock(l)

    proc acceptWorker(srv: ptr Listener[TCP]) {.thread.} =
      ## A server that accept a connection then write some small data into it.
      {.gcsafe.}:
        let (conn, _) = srv[].accept()
        # Write something to not cause a block
        discard conn.write("  ")
        # Wait until the caller is done with their work
        withLock(l):
          discard

    var server = listenTcp(IP4Loopback, PortNone)
    var thr: Thread[ptr Listener[TCP]]
    # Hold the lock so the worker won't terminate
    withLock l:
      # Launch a thread to act as the server accepting connections.
      thr.createThread(acceptWorker, addr server)

      # Connect to the server
      let client = connectTcp(server.localEndpoint)

      var str = newString(0)
      check client.read(str) == 0

    # Wait until the worker stops
    joinThread(thr)
    deinitLock(l)

  test "Conn[TCP] zero write":
    var l: Lock
    initLock(l)

    proc acceptWorker(srv: ptr Listener[TCP]) {.thread.} =
      ## A server that accept a connection then write some small data into it.
      {.gcsafe.}:
        let (conn, _) = srv[].accept()
        # Wait until the caller is done with their work
        withLock l:
          discard

    var server = listenTcp(IP4Loopback, PortNone)
    var thr: Thread[ptr Listener[TCP]]
    # Hold the lock so the worker won't terminate
    withLock l:
      # Launch a thread to act as the server accepting connections.
      thr.createThread(acceptWorker, addr server)

      # Connect to the server
      let client = connectTcp(server.localEndpoint)

      check client.write("") == 0

    # Wait until the worker stops
    joinThread(thr)
    deinitLock(l)

  test "Conn[TCP] long read/write":
    proc writeWorker(server: ptr Listener[TCP]) {.thread.} =
      ## Accepts a connection then write test data to it, closing it afterwards
      {.gcsafe.}:
        let (conn, _) = server[].accept()
        # Send the sample data
        conn.accumlatedWrite TestBufferedData
        # Shutdown the connection to signal completion
        close conn

    # Creates the server
    var server = listenTcp(IP4Loopback, PortNone)
    var thr: Thread[ptr Listener[TCP]]
    thr.createThread(writeWorker, addr server)

    # Connect to the server
    let conn = connectTcp(server.localEndpoint)

    # Retrieve the data
    check conn.accumlatedRead(TestBufferedData.len + 1024) == TestBufferedData

    # Wait for the worker to terminate
    thr.joinThread()

  test "Conn[TCP] delimited read/write":
    proc writeWorker(server: ptr Listener[TCP]) {.thread.} =
      ## Accepts a connection then write test data to it, closing it afterwards
      {.gcsafe.}:
        let (conn, _) = server[].accept()
        # Send the sample data
        conn.accumlatedWrite TestDelimitedData

    var server = listenTcp(IP4Loopback, PortNone)
    var thr: Thread[ptr Listener[TCP]]
    thr.createThread(writeWorker, addr server)

    # Connect to the server
    let conn = connectTcp(server.localEndpoint)

    # Read from the server and verify the data
    check conn.delimitedRead(Delimiter) == TestDelimitedData

    # Collect the writer
    joinThread thr

  test "AsyncConn[TCP] EOF read":
    proc acceptWorker(server: AsyncListener[TCP]) {.asyncio.} =
      ## A server that accept a connection then drops it
      ## immediately
      close server.accept().conn

    proc runner() {.asyncio.} =
      let server = listenTcpAsync(IP4Loopback, PortNone)
      # Run the worker until it is dismissed
      discard trampoline:
        whelp acceptWorker(server)

      # Connect to the server
      let client = connectTcpAsync(server.localEndpoint)

      # Our connection should be dropped and reading should yields nothing.
      var str = new string
      str[] = newString(10)
      check client.read(str) == 0

    # Start the test
    runner()
    # Run the IO queue to completion
    run()

  test "AsyncConn[TCP] EOF write with big buffers":
    proc acceptWorker(server: AsyncListener[TCP]) {.asyncio.} =
      ## A server that accept a connection then drops it
      ## immediately
      close server.accept().conn

    proc runner() {.asyncio.} =
      var server = listenTcpAsync(IP4Loopback, PortNone)
      # Run the worker until it is dismissed
      discard trampoline:
        whelp acceptWorker(server)

      # Connect to the server
      let client = connectTcpAsync(server.localEndpoint)

      # Our connection should be dropped and writing should error.
      #
      # It is expected that there might be some data written due
      # to operating system maintaining a local buffer.
      expect files.IOError:
        # Some repeats will be necessary as some operating systems buffers
        # data and won't trigger a send immediately, thus not raising the
        # error.
        var i = 0
        while i < 10:
          discard client.write(TestBufferedData)
          inc i

    # Start the test
    runner()
    # Run the IO queue to completion
    run()

  test "AsyncConn[TCP] zero read":
    proc acceptWorker(server: AsyncListener[TCP]) {.asyncio.} =
      ## A server that accept a connection then drops it
      ## immediately
      close server.accept().conn

    proc runner() {.asyncio.} =
      let server = listenTcpAsync(IP4Loopback, PortNone)
      # Run the worker until it is dismissed
      discard trampoline:
        whelp acceptWorker(server)

      # Connect to the server
      let client = connectTcpAsync(server.localEndpoint)

      var str = new string
      check client.read(str) == 0

      var sq = new string
      check client.read(sq) == 0

      check client.read(nil, 0) == 0

    # Start the test
    runner()
    # Run the IO queue to completion
    run()

  test "AsyncConn[TCP] zero write":
    proc acceptWorker(server: AsyncListener[TCP]): AsyncConn[TCP] {.asyncio.} =
      ## A server that accept a connection
      # Return it so it won't get closed immediately
      result = server.accept().conn

    proc runner() {.asyncio.} =
      let server = listenTcpAsync(IP4Loopback, PortNone)
      # Keep a reference to the worker so we can keep the connection alive
      let worker = whelp acceptWorker(server)
      # Tramp it
      discard trampoline worker

      # Connect to the server
      let client = connectTcpAsync(server.localEndpoint)

      check client.write("") == 0
      check client.write(default seq[byte]) == 0

      var str = new string
      check client.write(str) == 0

      var sq = new seq[byte]
      check client.write(sq) == 0

      check client.write(nil, 0) == 0

    # Start the test
    runner()
    # Run the IO queue to completion
    run()

  test "AsyncConn[TCP] read/write":
    proc writeWorker(server: AsyncListener[TCP]) {.asyncio.} =
      ## Accepts a connection then write test data to it, closing it afterwards
      let (conn, _) = server.accept()
      # Send the sample data
      conn.accumlatedWrite TestBufferedData

      # Close to signal completion
      close conn

    proc runner() {.asyncio.} =
      # Creates the server
      var server = listenTcpAsync(IP4Loopback, PortNone)
      # Run the worker until it is dismissed
      discard trampoline:
        whelp writeWorker(server)

      # Connect to the server
      let conn = connectTcpAsync(server.localEndpoint)

      # Retrieve the data
      check conn.accumlatedRead(TestBufferedData.len + 1024) == TestBufferedData

    # Run the test
    runner()
    # Run the IO queue to completion
    run()

  test "AsyncConn[TCP] delimited read / write":
    proc writeWorker(server: AsyncListener[TCP]) {.asyncio.} =
      ## Accepts a connection then write test data to it, closing it afterwards
      let (conn, _) = server.accept()
      # Send the sample data
      conn.accumlatedWrite TestDelimitedData

      # Close to signal completion
      close conn

    proc runner() {.asyncio.} =
      # Creates the server
      var server = listenTcpAsync(IP4Loopback, PortNone)
      # Run the worker until it is dismissed
      discard trampoline:
        whelp writeWorker(server)

      # Connect to the server
      let conn = connectTcpAsync(server.localEndpoint)

      # Retrieve the data
      check conn.delimitedRead(Delimiter) == TestDelimitedData

    # Run the test
    runner()
    # Run the IO queue to completion
    run()

when defined(posix):
  suite "Unix sockets":

    test "Conn[Unix] delimited read/write":
      let path = genTempPath("tsockets", "unix")
      defer: discard unlink(path)
        # Remove the temporary socket on completion.

      proc writeWorker(server: ptr Listener[Unix]) {.thread.} =
        ## Accepts a connection then write test data to it, closing it afterwards
        {.gcsafe.}:
          let conn = server[].accept()
          # Send the sample data
          conn.accumlatedWrite TestDelimitedData

      var server = listenUnix(path)
      var thr: Thread[ptr Listener[Unix]]
      thr.createThread(writeWorker, addr server)

      # Connect to the server
      let conn = connectUnix(path)

      # Read from the server and verify the data
      check conn.delimitedRead(Delimiter) == TestDelimitedData

      # Collect the writer
      joinThread thr

    test "AsyncConn[Unix] read/write":
      let path = genTempPath("tsockets", "unix")
      defer:
        discard unlink(path)

      proc writeWorker(server: AsyncListener[Unix]) {.asyncio.} =
        ## Accepts a connection then write test data to it, closing it afterwards

        let conn = server.accept()
        # Send the sample data
        conn.accumlatedWrite TestBufferedData

        # Close to signal completion
        close conn

      proc runner() {.asyncio.} =
        # Creates the server
        var server = listenUnixAsync(path)
        # Run the worker until it is dismissed
        discard trampoline:
          whelp writeWorker(server)

        # Connect to the server
        let conn = connectUnixAsync(path)

        # Retrieve the data
        check conn.accumlatedRead(TestBufferedData.len + 1024) == TestBufferedData

      # Run the test
      runner()
      # Run the IO queue to completion
      run()
