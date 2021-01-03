#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## This module contains abstractions for various operating system resource
## handles.
##
## .. code-block:: nim
##   import posix
##
##   block:
##     let fd = posix.open("test.txt", O_RDWR or O_CREAT)
##     assert fd != -1, "opening file failed"
##     let handle = initHandle(fd.FD)
##     # The handle will be closed automatically once the scope ends

import system except io
import private/utils

type
  FDImpl = (when defined(windows): uint else: cint)
    ## The representative type for the OS resource handle

  FD* = distinct FDImpl
    ## The type of the OS resource handle provided by the operating system.

  SocketFD* = distinct FD
    ## The type of the OS resource handle used for network sockets.

  AnyFD* = FD or SocketFD
    ## A typeclass representing any OS resource handles.

  Handle*[T: AnyFD] {.requiresInit.} = object
    ## An object used to associate a handle with a lifetime.
    fd: T

const
  InvalidFD* = cast[FD](-1)
    ## An invalid resource handle.

  ErrorSetInheritable = "Could not change the resource handle inheritable attribute"
    ## Error message used when setInheritable fails.

  ErrorSetBlocking {.used.} = "Could not change the resource handle blocking attribute"
    ## Error message used when setBlocking fails.

  ErrorDuplicate = "Could not duplicate resource handle"
    ## Error message used when duplicate fails.

func `==`*(a, b: FD): bool {.borrow.}
  ## Equivalence operator for `FD`

func `==`*(a, b: SocketFD): bool {.borrow.}
  ## Equivalence operator for `SocketFD`

proc `=destroy`[T: AnyFD](h: var Handle[T]) {.inline, docForward.} =
  ## Destroy the file handle.

proc `=copy`*[T: AnyFD](dest: var Handle[T], src: Handle[T]) {.error.}
  ## Copying a file handle is forbidden. Either a `ref Handle` should be used
  ## or `duplicate` should be used to make a duplicate of the handle.

proc initHandle*[T: AnyFD](fd: T): Handle[T] {.inline.} =
  ## Creates a Handle owning the passed `fd`. The `fd` shall then be freed
  ## automatically when the `Handle` go out of scope.
  Handle[T](fd: fd)

proc newHandle*[T: AnyFD](fd: T): ref Handle[T] {.inline.} =
  ## Creates a Handle owning the passed `fd`. The `fd` shall then be freed
  ## automatically when there are no reference to the returned `ref Handle`.
  (ref Handle[T])(fd: fd)

proc get*[T: AnyFD](h: Handle[T]): T {.inline.} =
  ## Returns the resource handle held by the passed `Handle`.
  ##
  ## The returned handle will stay alive for the duration of `h`.
  ##
  ## **Note**: Do **not** close the returned handle. If ownership is wanted,
  ## use `take` instead.
  h.fd

proc take*[T: AnyFD](h: var Handle[T]): T {.inline.} =
  ## Release the resource handle held by the passed `Handle` to the caller.
  ##
  ## The passed `Handle` will then be invalidated.
  result = h.fd
  h.fd = InvalidFD

proc setInheritable*(fd: AnyFD, inheritable: bool) {.docForward.} =
  ## Controls whether `fd` can be inherited by a child process.

when defined(nimdoc) or defined(posix):
  proc setBlocking*(fd: AnyFD, blocking: bool) {.docForward.} =
    ## Controls the blocking state of `fd`, only supports POSIX and Unix-like
    ## systems. Check for availability with `declared()` before use.

proc duplicate*[T: AnyFD](fd: T, inheritable = false): T {.docForward.} =
  ## Duplicate an OS resource handle. The duplicated handle will refer to the
  ## same resource as the original. This operation is commonly known as
  ## `dup`:idx: on POSIX systems.
  ##
  ## The duplicated handle will not be inherited automatically by child
  ## processes. The parameter `inheritable` can be used to change this behavior.

proc duplicateTo*[T: AnyFD](fd, target: T, inheritable = false) {.docForward.} =
  ## Duplicate the resource handle `fd` to `target`, making `target` refers
  ## to the same resource as `fd`. This operation is commonly known as
  ## `dup2`:idx: on POSIX systems.
  ##
  ## The duplicated handle will not be inherited automatically by the child
  ## prrocess. The parameter `inheritable` can be used to change this behavior.

proc duplicate*[T: AnyFD](h: Handle[T],
                          inheritable = false): Handle[T] {.inline.} =
  ## Duplicate an OS resource handle. The duplicated handle will refer to the
  ## same resource as the original. This operation is commonly known as
  ## `dup`:idx: on POSIX systems.
  ##
  ## The duplicated handle will not be inherited automatically by child
  ## processes. The parameter `inheritable` can be used to change this behavior.
  result = initHandle InvalidFD
  result.fd = h.fd.duplicate inheritable

proc duplicateTo*[T: AnyFD](h, target: Handle[T],
                            inheritable = false) {.inline.} =
  ## Duplicate the resource handle `h` to `target`, making `target` refers
  ## to the same resource as `h`. This operation is commonly known as
  ## `dup2`:idx: on POSIX systems.
  ##
  ## The duplicated handle will not be inherited automatically by the child
  ## prrocess. The parameter `inheritable` can be used to change this behavior.
  duplicateTo(h.fd, target.fd, inheritable)

when defined(nimdoc):
  discard ## Hide implementation from nimdoc
elif defined(posix):
  include private/handles_posix
else:
  {.error: "This module has not been ported to your operating system.".}
