import system except File, IOError
import std/strutils
import pkg/balls
import sys/[pipes, files, private/syscall/posix, ioqueue]

{.experimental: "implicitDeref".}

let TestBufferedData = "!@#$%^TEST%$#@!\n".repeat(10_000_000)
  ## A decently sized buffer that surpasses most OS pipe buffer size, which
  ## is usually in the range of 4-8MiB.
  ##
  ## Declared as a `let` to avoid binary size being inflated by the inlining.

suite "Test Pipe read/write behaviors":
  when defined(posix):
    ## Disable SIGPIPE for EOF write tests
    signal(SIGPIPE, SIG_IGN)

  test "Pipe EOF read":
    let (rd, wr) = newPipe()

    close wr
    var str = newString(10)
    check rd.read(str) == 0

  test "AsyncPipe EOF read":
    let (rd, wr) = newAsyncPipe()

    close wr
    var str = new string
    str[] = newString(10)
    check rd.read(str) == 0

  test "Pipe EOF write":
    let (rd, wr) = newPipe()

    close rd
    let data = "test data"
    expect IOError:
      try:
        wr.write(data)
      except IOError as e:
        check e.bytesTransferred == 0
        raise e # Reraise so expect can catch it

  test "AsyncPipe EOF write":
    let (rd, wr) = newAsyncPipe()

    close rd
    let data = "test data"
    expect IOError:
      try:
        wr.write(data)
      except IOError as e:
        check e.bytesTransferred == 0
        raise e

  test "Pipe read/write":
    proc writeWorker(wr: ptr WritePipe) {.thread.} =
      {.gcsafe.}:
        wr.write TestBufferedData
        close wr

    var (rd, wr) = newPipe()
    var thr: Thread[ptr WritePipe]
    # Launch a thread to write test data to the pite
    thr.createThread(writeWorker, addr wr)

    var rdBuf = newString TestBufferedData.len
    # Read the data from this thread
    check rd.read(rdBuf) == rdBuf.len
    # Then verify that it's the same data
    check rdBuf == TestBufferedData
    # Collect the writer
    joinThread thr

  test "AsyncPipe read/write":
    let (rd, wr) = newAsyncPipe()

    proc writeWorker() {.asyncio.} =
      wr.write TestBufferedData
      close wr

    # Start the writer, which will suspend as it ran out of buffer space
    writeWorker()

    let rdBuf = new string
    rdBuf[] = newString TestBufferedData.len

    proc readWorker() {.asyncio.} =
      check rd.read(rdBuf) == rdBuf.len

    # Start the reader, which will suspend waiting for more data from writer
    readWorker()

    # Activate the queue to process the events
    run()

    # Verify that the correct data is retrieved
    check rdBuf[] == TestBufferedData

  test "Sync read and async write test":
    proc readWorker(rd: ptr ReadPipe) {.thread.} =
      {.gcsafe.}:
        var rdBuf = newString TestBufferedData.len
        check rd.read(rdBuf) == rdBuf.len
        check rdBuf == TestBufferedData

    var (rd, wr) = newPipe(Wr = AsyncWritePipe)
    var thr: Thread[ptr ReadPipe]
    # Start a thread which will read until it received the full test buffer
    thr.createThread(readWorker, addr rd)

    # Write the data to the pipe, the writer will suspend as the pipe
    # ran out of space.
    wr.write TestBufferedData

    # Run the queue to process events
    run()

    # Collect the reader
    joinThread thr

  test "Async read and sync write test":
    proc writeWorker(wr: ptr WritePipe) {.thread.} =
      {.gcsafe.}:
        wr.write TestBufferedData
        close wr

    var (rd, wr) = newPipe(Rd = AsyncReadPipe)
    var thr: Thread[ptr WritePipe]
    # Start a thread which will write the full test buffer to the pipe
    thr.createThread(writeWorker, addr wr)

    let rdBuf = new string
    rdBuf[] = newString TestBufferedData.len

    proc readWorker() {.asyncio.} =
      check rd.read(rdBuf) == rdBuf.len

    # Run the read worker which will read the test buffer from the pipe
    readWorker()

    # Run the queue to process events
    run()

    # Verify that the data is correct
    check rdBuf[] == TestBufferedData

    # Collect the writer
    joinThread thr
