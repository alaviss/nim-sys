{.experimental: "implicitDeref".}

when (NimMajor, NimMinor) >= (1, 5) and defined(linux):
  import std/[posix, os, strutils]
  import pkg/[cps, balls]
  import sys/[files, eventqueue, handles]

  import ".."/helpers/handles as helper_handle

  const TestData = "!@#$%^TEST%$#@!\n"
  let BigTestData = TestData.repeat(10 * 1024 * 1024)
    ## A decently sized chunk of data that surpasses most OS pipe buffer size,
    ## which is usually in the range of 4-8MiB.
    ##
    ## Declared as as a `let` to avoid binary size, and compiler RAM usage
    ## from being inflated by the inlining.

  proc newAsyncPipe(): tuple[rd, wr: ref Handle[FD]] =
    var (rd, wr) = helper_handle.pipe()

    rd.setBlocking(false)
    wr.setBlocking(false)

    result = (newHandle(rd), newHandle(wr))

  proc write[T: byte or char](fd: Handle[FD], data: openArray[T]) =
    ## Write all bytes in `data` into `fd`.
    var totalWritten = 0
    while totalWritten < data.len:
      let written = write(fd.get.cint, data[totalWritten].unsafeAddr, data.len - totalWritten)
      case written
      of -1:
        raise newIOError(totalWritten, errno.int32)
      else:
        totalWritten += written

  proc read[T: byte or char](fd: Handle[FD], buf: var openArray[T]): int =
    ## Read all bytes from `fd` into `buf` until it's filled or there is
    ## nothing left to read
    while result < buf.len:
      let readBytes = read(fd.get.cint, buf[result].addr, buf.len - result)
      case readBytes
      of -1:
        raise newIOError(result, errno.int32)
      of 0:
        break
      else:
        result += readBytes

  proc readAsync(rd: ref Handle[FD], buf: ref string) {.cps: Continuation.} =
    ## Read data from `rd` until `buf` is filled or there is nothing else
    ## to be read, asynchronously.
    ##
    ## After finished, `buf` will be set to the length of the data received.
    ## It is done like this since our dispatcher don't provide tracking
    ## information outside of cps yet
    var offset = 0
    while offset < buf.len:
      try:
        let read = read(rd, buf.toOpenArray(offset, buf.len - 1))
        buf.setLen offset + read
        break
      except files.IOError as e:
        # Add the offset so we know where exactly we are
        e.bytesTransferred += offset
        if e.errorCode == EAGAIN:
          offset = e.bytesTransferred
          wait rd.get, {Read}
        else:
          raise e

  proc writeAsync(wr: ref Handle[FD], buf: string) {.cps: Continuation.} =
    ## Write all bytes in `buf` into `wr` asynchronously
    var offset = 0
    while offset < buf.len:
      try:
        write(wr, buf.toOpenArray(offset, buf.len - 1))
        break
      except files.IOError as e:
        # Add the offset so we know where exactly we are
        e.bytesTransferred += offset
        if e.errorCode == EAGAIN:
          offset = e.bytesTransferred
          wait wr.get, {Write}
        else:
          raise e

  suite "Test readiness behaviors":
    test "Ready to read":
      var (rd, wr) = newAsyncPipe()

      let str = new string
      str.setLen(TestData.len)
      # Start the reader first, it will suspend because there's nothing
      # to read from
      readAsync(rd, str)

      # Write our payload, it's small so it won't block
      wr.write(TestData)
      # Close to signify completion
      close wr

      # Run the dispatcher, which should finish our read
      run()

      check str == TestData

    test "Ready to write":
      var (rd, wr) = newAsyncPipe()

      # Fill our buffer til we can't write anymore
      try:
        wr.write(BigTestData)
        fail "we couldn't fill the buffer"
      except files.IOError as e:
        if e.errorCode != EAGAIN:
          raise

      # Start our writer, it will suspend because the buffer is full
      # This payload is small, so when it starts writing it will finish
      # immediately
      wr.writeAsync(TestData)

      # Empty the buffer
      var str = newString(BigTestData.len)
      # We should be able to empty the buffer in one swoop
      try:
        discard rd.read(str)
        fail "we couldn't empty the buffer"
      except files.IOError as e:
        if e.errorCode != EAGAIN:
          raise

      # Run the dispatcher, our writer should start writing now
      run()
      # Close our write line so that read knows that there is nothing left
      close wr

      # Read and make sure that we get just enough data
      check rd.read(str) == TestData.len, "there are more data in the buffer than specified"

      str.setLen(TestData.len)
      check str == TestData

    test "Multiple waiters for read/write":
      var (rd, wr) = newAsyncPipe()

      var str = new string
      str.setLen(BigTestData.len)

      # Start the reader, it will suspend because there's nothing to read
      rd.readAsync(str)

      # Start the writer, it will suspend because our buffer is too big to
      # write in one go
      wr.writeAsync(BigTestData)

      # Let's run this mess
      run()

      check str == BigTestData
