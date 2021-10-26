#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#              Copyright (c) 2020-2021 Andy Davidoff
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Common constants shared between ioqueue modules

type
  Error* {.pure.} = enum
    ## Enums for errors raised by this module
    Init = "Could not initialize the event queue"
      ## Used when initialization failed.

    Queue = "Could not queue event"
      ## Used when queuing for events failed.

    Poll = "Could not poll the operating system for events"
      ## Used when poll() failed.

    QueuedFD = "The given resource handle ($1) is already waited on"
      ## Used when the user wait() on more than once on a given FD

    Unregister = "Could not unregister resource from the OS"
      ## Used when unregister() fails

    Register = "Could not register resource to the OS"
      ## Used when persist() fails
