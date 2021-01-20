import system except File, IOError
import std/[asyncdispatch, asyncfutures, strutils]
import pkg/balls
import sys/[pipes, files, private/syscall/posix]

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
    check waitFor(rd.read str) == 0

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
        waitFor wr.write(data)
      except IOError as e:
        check e.bytesTransferred == 0
        raise e

  test "Pipe read/write":
    proc writeWorker(wr: ptr File) {.thread.} =
      {.gcsafe.}:
        wr.write TestBufferedData
        close wr

    var (rd, wr) = newPipe()
    var thr: Thread[ptr File]
    thr.createThread(writeWorker, addr wr)

    var rdBuf = newString TestBufferedData.len
    check rd.read(rdBuf) == rdBuf.len
    check rdBuf == TestBufferedData
    joinThread thr

  test "AsyncPipe read/write":
    let (rd, wr) = newAsyncPipe()

    let wrFut = wr.write TestBufferedData
    wrFut.addCallback do:
      {.gcsafe.}:
        close wr

    let rdBuf = new string
    rdBuf[] = newString TestBufferedData.len
    check waitFor(rd.read rdBuf) == rdBuf.len
    check rdBuf[] == TestBufferedData
    check wrFut.finished

  test "Sync read and async write test":
    proc readWorker(rd: ptr File) {.thread.} =
      {.gcsafe.}:
        var rdBuf = newString TestBufferedData.len
        check rd.read(rdBuf) == rdBuf.len
        check rdBuf == TestBufferedData
        close rd

    var (rd, wr) = newPipe(Wr = AsyncFile)
    var thr: Thread[ptr File]
    thr.createThread(readWorker, addr rd)

    waitFor wr.write TestBufferedData
    joinThread thr

  test "Async read and sync write test":
    proc writeWorker(wr: ptr File) {.thread.} =
      {.gcsafe.}:
        wr.write TestBufferedData
        close wr

    var (rd, wr) = newPipe(Rd = AsyncFile)
    var thr: Thread[ptr File]
    thr.createThread(writeWorker, addr wr)

    let rdBuf = new string
    rdBuf[] = newString TestBufferedData.len
    check waitFor(rd.read rdBuf) == rdBuf.len
    check rdBuf[] == TestBufferedData
    joinThread thr
