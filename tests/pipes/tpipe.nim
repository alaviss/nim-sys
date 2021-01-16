import system except File, IOError
import std/[asyncdispatch, asyncfutures, strutils]
import pkg/testes
import sys/[pipes, files, private/syscall/posix]

{.experimental: "implicitDeref".}

let TestBufferedData = "!@#$%^TEST%$#@!\n".repeat(10_000_000)
  ## A decently sized buffer that surpasses most OS pipe buffer size, which
  ## is usually in the range of 4-8MiB.
  ##
  ## Declared as a `let` to avoid binary size being inflated by the inlining.

testes:
  when defined(posix):
    ## Disable SIGPIPE for EOF write tests
    signal(SIGPIPE, SIG_IGN)

  test "Pipe EOF read":
    var (rd, wr) = newPipe()

    close wr
    var str = newString(10)
    check rd.read(str) == 0

  test "AsyncPipe EOF read":
    var (rd, wr) = newAsyncPipe()

    close wr
    var str = new string
    str[] = newString(10)
    check waitFor(rd.read str) == 0

  test "Pipe EOF write":
    var (rd, wr) = newPipe()

    close rd
    let data = "test data"
    expect IOError:
      try:
        wr.write(data)
      except IOError as e:
        check e.bytesTransferred == 0
        raise e # Reraise so expect can catch it

  test "AsyncPipe EOF write":
    var (rd, wr) = newAsyncPipe()

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
    var (rd, wr) = newAsyncPipe()

    let wrFut = wr.write TestBufferedData
    wrFut.addCallback do:
      {.gcsafe.}:
        close wr

    let rdBuf = new string
    rdBuf[] = newString TestBufferedData.len
    check waitFor(rd.read rdBuf) == rdBuf.len
    check rdBuf[] == TestBufferedData
    check wrFut.finished
