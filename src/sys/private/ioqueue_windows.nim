#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

type
  EventQueueImpl = object
    ## The queue of IOCP is implemented in a different module

template initImpl() {.dirty.} = discard

template runningImpl(): bool {.dirty.} =
  iocp.running()

template pollImpl() {.dirty.} =
  iocp.poll(runnable, timeout)

template persistImpl() {.dirty.} =
  iocp.persist(fd)

template unregisterImpl() {.dirty.} =
  iocp.unregister(fd)
