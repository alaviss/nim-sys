#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Abstractions for operating system pipes and FIFOs (named pipes).

import system except File
import files
import private/utils

const
  ErrorPipeCreation = "Could not create pipe"
    ## Error message used when pipe creation fails.

proc initPipe*(flags: set[FileFlag] = {}): tuple[rd, wr: File] {.docForward.} =
  ## Creates a new anonymous pipe.
  ##
  ## Returns a tuple containing the read and write endpoints of the pipe.
  ##
  ## Only the flag `ffInheritable` is supported.

proc newPipe*(flags: set[FileFlag] = {}): tuple[rd, wr: ref File] {.docForward.} =
  ## Creates a new anonymous pipe as references.
  ##
  ## Returns a tuple containing the read and write endpoints of the pipe.
  ##
  ## Only the flag `ffInheritable` is supported.

proc initAsyncPipe*(flags: set[FileFlag] = {}): tuple[rd, wr: AsyncFile] {.docForward.} =
  ## Creates a new asynchronous anonymous pipe.
  ##
  ## Returns a tuple containing the read and write endpoints of the pipe.
  ##
  ## Only the flag `ffInheritable` is supported.

proc newAsyncPipe*(flags: set[FileFlag] = {}): tuple[rd, wr: ref AsyncFile] {.docForward.} =
  ## Creates a new asynchrounous anonymous pipe as references.
  ##
  ## Returns a tuple containing the read and write endpoints of the pipe.
  ##
  ## Only the flag `ffInheritable` is supported.


when defined(nimdoc):
  discard "Hide implementation from nim doc"
elif defined(posix):
  include private/pipes_posix
else:
  {.error: "This module has not been ported to your operating system.".}
