when (NimMajor, NimMinor) >= (1, 5) and defined(linux):
  import pkg/[cps, balls]
  import sys/[handles, ioqueue]

  import ".."/helpers/handles as helper_handle

  proc testFailure() {.cps: Continuation.} =
    fail "This code should not be run"

  suite "Unregistering FD from queue":
    test "Unregistering FD prevents its continuation from being run":
      let (rd, wr) = pipe()
      defer:
        close rd
        close wr

      # Queue testFailure() for Write on the write side of the pipe, which
      # will be resolved to ready when the queue is run as an empty pipe
      # is ready to be written to.
      #
      # We can discard this because `nil` will be returned here.
      discard wait(whelp testFailure(), wr, Write)

      # Unregister the pipe
      unregister wr

      # Run the queue, testFailure() should not run
      run()
