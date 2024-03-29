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

const
  ErrorClosedHandle = "The resource handle has already been closed or is invalid"
    ## Error message used for ClosedHandleDefect.

  ErrorSetInheritable = "Could not change the resource handle inheritable attribute"
    ## Error message used when setInheritable fails.

  ErrorSetBlocking {.used.} = "Could not change the resource handle blocking attribute"
    ## Error message used when setBlocking fails.

when false:
  const
    ErrorDuplicate = "Could not duplicate resource handle"
      ## Error message used when duplicate fails.

when defined(posix):
  include private/handles_posix
elif defined(windows):
  include private/handles_windows
else:
  {.error: "This module has not been ported to your operating system.".}

type
  FD* = distinct FDImpl
    ## The type of the OS resource handle provided by the operating system.

  SocketFD* = distinct FD
    ## The type of the OS resource handle used for network sockets.

  AnyFD* = FD or SocketFD
    ## A typeclass representing any OS resource handles.

  InvalidResourceHandle = distinct FD
    ## The type of the invalid resource handle. This is a special type
    ## just for InvalidFD usage.

const
  InvalidFD* = cast[InvalidResourceHandle](-1)
    ## An invalid resource handle.

template raiseClosedHandleDefect*() =
  ## Raises a Defect for closing an invalid/closed handle.
  ##
  ## Calling `close()` on an invalid/closed handle is extremely dangerous, as
  ## the handle could have been re-used by the operating system for an another
  ## resource requested by the application.
  raise newException(Defect, ErrorClosedHandle)

func `==`*(a, b: FD): bool {.borrow.}
  ## Equivalence operator for `FD`

func `==`*(a, b: SocketFD): bool {.borrow.}
  ## Equivalence operator for `SocketFD`

func `==`*(a: AnyFD, b: typeof(InvalidFD)): bool {.inline.} =
  ## Equivalence operator for comparing any file descriptor with `InvalidFD`.
  a == (typeof a) b

func `==`*(a: typeof(InvalidFD), b: AnyFD): bool {.inline.} =
  ## Equivalence operator for comparing any file descriptor with `InvalidFD`.
  b == a

proc close*(fd: AnyFD) =
  ## Closes the resource handle `fd`.
  ##
  ## If the passed resource handle is not valid, `ClosedHandleDefect` will be
  ## raised.
  closeImpl()

proc setInheritable*(fd: AnyFD, inheritable: bool) =
  ## Controls whether `fd` can be inherited by a child process.
  setInheritableImpl()

when not declared(setBlockingImpl):
  # XXX: Pending nim-lang/Nim#16672 so we can fold this into setBlocking
  template setBlockingImpl() =
    {.error: "setBlocking is not available for your operating system".}

proc setBlocking*(fd: AnyFD, blocking: bool) =
  ## Controls the blocking state of `fd`, only available on POSIX systems.
  setBlockingImpl()

when false:
  # NOTE: Staged until process spawning is added.
  proc duplicate*[T: AnyFD](fd: T, inheritable = false): T =
    ## Duplicate an OS resource handle. The duplicated handle will refer to the
    ## same resource as the original. This operation is commonly known as
    ## `dup`:idx: on POSIX systems.
    ##
    ## The duplicated handle will not be inherited automatically by child
    ## processes. The parameter `inheritable` can be used to change this
    ## behavior.
    duplicateImpl()

  proc duplicateTo*[T: AnyFD](fd, target: T, inheritable = false) =
    ## Duplicate the resource handle `fd` to `target`, making `target` refers
    ## to the same resource as `fd`. This operation is commonly known as
    ## `dup2`:idx: on POSIX systems.
    ##
    ## The duplicated handle will not be inherited automatically by the child
    ## prrocess. The parameter `inheritable` can be used to change this behavior.
    duplicateToImpl()

# XXX: T should be a concept, but those don't work atm
type
  Handle*[T] = object
    ## An object used to associate a handle with a lifetime.
    shiftedFd: FDImpl ## The file descriptor mapped to a different range that
                      ## is invalid when zero-ed.

func fd*[T](h: Handle[T]): T {.inline.} =
  ## Returns the resource handle held by `h`.
  ##
  ## The returned handle will stay valid for the duration of `h`.
  ##
  ## **Note**: Do **not** close the returned handle. If ownership is wanted,
  ## use `takeFd` instead.
  getFdImpl()

func `fd=`[T](h: var Handle[T], fd: T) {.inline.} =
  ## Set the handle to be tracked. This does not destroy the previous handle.
  setFdImpl()

func takeFd*[T](h: var Handle[T]): T {.inline.} =
  ## Returns the resource handle held by `h` and release ownership to the
  ## caller. `h` will then be invalidated.
  result = h.fd
  `fd=`(h, InvalidFD.T)

proc close*[T](h: var Handle[T]) {.inline.} =
  ## Close the handle owned by `h` and invalidating it.
  ##
  ## If `h` is invalid, `ClosedHandleDefect` will be raised.
  try:
    close h.fd
  finally:
    # Always invalidate `h.fd` to avoid double-close on destruction.
    `fd=`(h, InvalidFD.T)

proc `=destroy`[T](h: var Handle[T]) =
  ## Destroy the file handle.
  if h.fd != InvalidFD:
    close h

proc `=copy`*[T](dest: var Handle[T], src: Handle[T]) {.error.}
  ## Copying a file handle is forbidden. Either a `ref Handle` should be used
  ## or `duplicate` should be used to make a handle refering to the same
  ## resource.

proc initHandle*[T](fd: T): Handle[T] {.inline.} =
  ## Creates a `Handle` owning the passed `fd`. The `fd` shall then be freed
  ## automatically when the `Handle` go out of scope.
  `fd=`(result, fd)

proc newHandle*[T](fd: T): ref Handle[T] {.inline.} =
  ## Creates a `ref Handle` owning the passed `fd`. The `fd` shall then be
  ## freed automatically when the returned `ref Handle[T]` is collected by the
  ## GC.
  new result
  result[] = initHandle(fd)
