#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Safe wrappers for `<spawn.h>` without the prefix.
##
## Only the parts used by sys/exec is wrapped at the moment.

# NOTE: Wrap the rest before promoting to public API.

{.push header: "<spawn.h>".}

import ".."/".."/".."/handles
import ".."/".."/errors
import ".."/posix

type
  FileActions* {.bycopy, importc: "posix_spawn_file_actions_t",
                 incompleteStruct, requiresInit.} = object
    ## The `posix_spawn_file_actions_t` object. It has a destructor attached
    ## so there is no need to destroy manually.

proc init*(fa: var FileActions): cint
          {.cdecl, importc: "posix_spawn_file_actions_init".}
  ## Manual initialization proc, see the man page for
  ## `posix_spawn_file_actions_init` for more details.
  ##
  ## A high-level wrapper is available as
  ## `initFileActions() <#initFileActions>`_.
proc destroy*(fa: var FileActions): cint
             {.cdecl, importc: "posix_spawn_file_actions_destroy".}
  ## Manual destruction proc, see the man page for
  ## `posix_spawn_file_actions_destroy` for more details.
  ##
  ## A destructor is already attached to the `FileActions` type, so this proc
  ## should never have to be called.

proc initFileActions*(): FileActions {.inline.} =
  ## Creates a new FileActions object
  posixChk init(result), "Could not create a new FileActions object"

proc `=destroy`(fa: var FileActions) =
  ## Destroys the FileActions object
  # According to POSIX, the only error would be EINVAL, meaning that `fa` was
  # already destroyed. It shouldn't matter here.
  discard destroy fa

proc addClose*(fa: var FileActions, fildes: FD): cint
              {.cdecl, importc: "posix_spawn_file_actions_addclose".}

proc addDup2*(fa: var FileActions, fildes: FD, newfildes: FD): cint
             {.cdecl, importc: "posix_spawn_file_actions_adddup2".}

proc spawn*(pid: ptr Pid, path: cstring, fileActions: ptr FileActions,
            attrp: pointer, argv, envp: ptr UncheckedArray[cstring]): cint
           {.cdecl, importc: "posix_spawn".}

proc spawnp*(pid: ptr Pid, file: cstring, fileActions: ptr FileActions,
             attrp: pointer, argv, envp: ptr UncheckedArray[cstring]): cint
            {.cdecl, importc: "posix_spawnp".}

{.pop.}
