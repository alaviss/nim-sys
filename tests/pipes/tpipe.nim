import system except File, IOError
import std/strutils
import pkg/balls
import sys/[pipes, files, private/syscall/posix, ioqueue]
import ".."/helpers/io

{.experimental: "implicitDeref".}

const Delimiter = "\c\l\c\l"
  # The HTTP delimiter

let
  TestBufferedData = "!@#$%^TEST%$#@!\n".repeat(2_000_000)
    ## A decently sized buffer that surpasses most OS pipe buffer size, which
    ## is usually in the range of 4-8MiB.
    ##
    ## Declared as a `let` to avoid binary size being inflated by the inlining.
  TestDelimitedData = TestBufferedData & Delimiter
    ## The buffer used to test delimited reads.

makeAccRead(AsyncReadPipe)
makeAccWrite(AsyncWritePipe)
makeDelimRead(AsyncReadPipe)

suite "Test Pipe read/write behaviors":
  test "Pipe EOF read":
    let (rd, wr) = newPipe()

    close wr
    var str = newString(10)
    check rd.read(str) == 0

  test "Pipe EOF write":
    let (rd, wr) = newPipe()

    close rd
    let data = "test data"
    expect IOError:
      try:
        discard wr.write(data)
      except IOError as e:
        check e.bytesTransferred == 0
        raise e # Reraise so expect can catch it

  test "AsyncPipe EOF read":
    let (rd, wr) = newAsyncPipe()

    close wr

    proc runner() {.asyncio.} =
      var str = new string
      str[] = newString(10)
      check rd.read(str) == 0

    runner()
    run()

  test "AsyncPipe EOF write":
    let (rd, wr) = newAsyncPipe()

    close rd
    let data = "test data"
    expect IOError:
      try:
        discard wr.write(data)
      except IOError as e:
        check e.bytesTransferred == 0
        raise e

  test "Pipe zero read":
    let (rd, wr) = newPipe()

    # Write something small so there is "something" in the pipe to prevent
    # blocking
    discard wr.write(" ")
    var str = newString(0)
    check rd.read(str) == 0

  test "Pipe zero write":
    let (rd, wr) = newPipe()

    var str = newString(0)
    check wr.write(str) == 0

  test "AsyncPipe zero read":
    let (rd, wr) = newAsyncPipe()

    # Close the pipe to make sure read doesn't queue
    #
    # This is because Windows will queue reads until a pipe write is done.
    close wr

    proc runner() {.asyncio.} =
      var str = new string
      check rd.read(str) == 0

      var sq = new seq[byte]
      check rd.read(sq) == 0

      check rd.read(nil, 0) == 0

    runner()
    run()

  test "AsyncPipe zero write":
    let (rd, wr) = newAsyncPipe()

    proc runner() {.asyncio.} =
      check wr.write("") == 0
      check wr.write(default seq[byte]) == 0

      var str = new string
      check wr.write(str) == 0

      var sq = new seq[byte]
      check wr.write(sq) == 0

    runner()
    run()

  test "Pipe long read/write":
    proc writeWorker(wr: ptr WritePipe) {.thread.} =
      {.gcsafe.}:
        wr.accumlatedWrite TestBufferedData
        # Signal that we are done
        close wr

    var (rd, wr) = newPipe()
    var thr: Thread[ptr WritePipe]
    # Launch a thread to write test data to the pite
    thr.createThread(writeWorker, addr wr)

    # Read and verify that it's the same data
    #
    # We add some extra buffer space to test EOF
    check rd.accumlatedRead(TestBufferedData.len + 1024) == TestBufferedData
    # Collect the writer
    joinThread thr

  test "AsyncPipe long read/write":
    let (rd, wr) = newAsyncPipe()

    proc writeWorker() {.asyncio.} =
      wr.accumlatedWrite TestBufferedData
      # Signal that we are done
      close wr

    # Start the writer, which will suspend as it ran out of buffer space
    writeWorker()

    proc readWorker() {.asyncio.} =
      check rd.accumlatedRead(TestBufferedData.len + 1024) == TestBufferedData

    # Start the reader, which will suspend waiting for more data from writer
    readWorker()

    # Activate the queue to process the events
    run()

  test "Sync read and async write test":
    proc readWorker(rd: ptr ReadPipe) {.thread.} =
      {.gcsafe.}:
        check rd.accumlatedRead(TestBufferedData.len + 1024) == TestBufferedData

    var (rd, wr) = newPipe(Wr = AsyncWritePipe)
    var thr: Thread[ptr ReadPipe]
    # Start a thread which will read until it received the full test buffer
    thr.createThread(readWorker, addr rd)

    # Write the data to the pipe, the writer will suspend as the pipe
    # ran out of space.
    proc writeWorker() {.asyncio.} =
      wr.accumlatedWrite TestBufferedData
      # Signal that we are done
      close wr

    writeWorker()

    # Run the queue to process events
    run()

    # Collect the reader
    joinThread thr

  test "Async read and sync write test":
    proc writeWorker(wr: ptr WritePipe) {.thread.} =
      {.gcsafe.}:
        wr.accumlatedWrite TestBufferedData
        # Signal that we are done
        close wr

    var (rd, wr) = newPipe(Rd = AsyncReadPipe)
    var thr: Thread[ptr WritePipe]
    # Start a thread which will write the full test buffer to the pipe
    thr.createThread(writeWorker, addr wr)

    proc readWorker() {.asyncio.} =
      check rd.accumlatedRead(TestBufferedData.len + 1024) == TestBufferedData

    # Run the read worker which will read the test buffer from the pipe
    readWorker()

    # Run the queue to process events
    run()

    # Collect the writer
    joinThread thr

  test "Pipe delimited read / write":
    proc writeWorker(wr: ptr WritePipe) {.thread.} =
      {.gcsafe.}:
        wr.accumlatedWrite TestDelimitedData

    var (rd, wr) = newPipe()
    var thr: Thread[ptr WritePipe]
    # Start a thread which will write the full test buffer to the pipe
    thr.createThread(writeWorker, addr wr)

    # Read from the pipe and verify that the data is correct
    check rd.delimitedRead(Delimiter) == TestDelimitedData

    # Collect the writer
    joinThread thr

  test "AsyncPipe delimited read / write":
    var (rd, wr) = newAsyncPipe()

    proc writeWorker() {.asyncio.} =
      wr.accumlatedWrite TestDelimitedData

    # Start the worker, which should suspend due to out of buffer space
    writeWorker()

    proc readWorker() {.asyncio.} =
      # Read from the pipe and verify that the data is correct
      check rd.delimitedRead(Delimiter) == TestDelimitedData

    # This should suspend to wait for more data
    readWorker()

    # Run the queue
    run()

  test "Pipe delimited read / AsyncPipe write":
    proc readWorker(rd: ptr ReadPipe) {.thread.} =
      {.gcsafe.}:
        check rd.delimitedRead(Delimiter) == TestDelimitedData

    var (rd, wr) = newPipe(Wr = AsyncWritePipe)
    var thr: Thread[ptr ReadPipe]
    # Start a thread which will read until it received the full test buffer
    thr.createThread(readWorker, addr rd)

    # Write the data to the pipe, the writer will suspend as the pipe
    # ran out of space.
    proc writeWorker() {.asyncio.} =
      wr.accumlatedWrite TestDelimitedData

    writeWorker()

    # Run the queue to process events
    run()

    # Collect the reader
    joinThread thr

  test "AsyncPipe delimited read / Pipe write":
    proc writeWorker(wr: ptr WritePipe) {.thread.} =
      {.gcsafe.}:
        wr.accumlatedWrite TestDelimitedData

    var (rd, wr) = newPipe(Rd = AsyncReadPipe)
    var thr: Thread[ptr WritePipe]
    # Start a thread which will write the full test buffer to the pipe
    thr.createThread(writeWorker, addr wr)

    proc readWorker() {.asyncio.} =
      check rd.delimitedRead(Delimiter) == TestDelimitedData

    # Run the read worker which will read the test buffer from the pipe
    readWorker()

    # Run the queue to process events
    run()

    # Collect the writer
    joinThread thr

