{.experimental: "implicitDeref".}

when defined(linux) or defined(macosx) or defined(bsd):
  import std/[posix, os, strutils]
  import pkg/[cps, balls]
  import sys/[files, ioqueue, handles]

  import asyncio
  import ".."/helpers/handles as helper_handle

  const TestData = "!@#$%^TEST%$#@!\n"
  let BigTestData = TestData.repeat(10 * 1024 * 1024)
    ## A decently sized chunk of data that surpasses most OS pipe buffer size,
    ## which is usually in the range of 4-8MiB.
    ##
    ## Declared as as a `let` to avoid binary size, and compiler RAM usage
    ## from being inflated by the inlining.

  suite "Test readiness behaviors":
    test "Ready to read":
      var (rd, wr) = newAsyncPipe()
      defer:
        unregister rd
        unregister wr

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
      defer:
        unregister rd
        unregister wr

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
      defer:
        unregister rd
        unregister wr

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
