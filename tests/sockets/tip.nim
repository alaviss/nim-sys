when defined(posix):
  import pkg/balls
  import sys/sockets

  suite "IP address testing":
    test "IPv4 to string":
      check $ip4(127, 0, 0, 1) == "127.0.0.1"
      check $ip4(1, 1, 1, 1) == "1.1.1.1"

    test "Resolving localhost works":
      block test:
        for ep in resolveIP4("localhost").items:
          if ep.ip == ip4(127, 0, 0, 1):
            break test

        check false, "did not find 127.0.0.1 when resolving for localhost"
