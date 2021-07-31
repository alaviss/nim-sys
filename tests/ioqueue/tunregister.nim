{.experimental: "implicitDeref".}

when (NimMajor, NimMinor) >= (1, 5):
  import pkg/[cps, balls]
  import sys/[handles, ioqueue]

  import asyncio

  suite "Unregistering FD from queue":
    test "Unregistering FD prevents its continuation from being run":
      let (rd, wr) = newAsyncPipe()
      defer:
        close rd

      proc tester() {.asyncio.} =
        let buf = new string
        buf.setLen 1
        readAsync(rd, buf)
        fail "This code should not be run"

      # Run our tester, which will be queued since the read pipe is empty
      tester()

      # Close the write side, which will unblock the pipe
      close wr

      # Unregister the pipe
      unregister rd

      # Run the queue, the proc should not continue
      run()
