{.experimental: "implicitDeref".}

when (NimMajor, NimMinor) >= (1, 5) and (defined(linux) or defined(macosx) or
                                         defined(bsd) or defined(windows)):
  import std/[os, strutils]
  import pkg/balls
  import sys/[ioqueue, handles]

  import asyncio

  const TestData = "!@#$%^TEST%$#@!\n"
  let BigTestData = TestData.repeat(10 * 1024 * 1024)
    ## A decently sized chunk of data that surpasses most OS pipe buffer size,
    ## which is usually in the range of 4-8MiB.
    ##
    ## Declared as as a `let` to avoid binary size, and compiler RAM usage
    ## from being inflated by the inlining.

  suite "Test queue":
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
