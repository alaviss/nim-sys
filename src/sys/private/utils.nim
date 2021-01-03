#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Provides helper macros and definitions for use within the project

import macros

macro docForward*(prc: untyped): untyped =
  ## Helper macro to allow forward declaring a proc with documentations
  runnableExamples:
    proc foo {.docForward.} =
      ## Documentation

    when not defined(nimdoc):
      proc foo = discard # Implementation
  prc.expectKind nnkProcDef

  let prototype = prc.copyNimTree
  prototype.body = newEmptyNode()

  template docDecl(proto, prc: untyped): untyped {.dirty.} =
    when defined(nimdoc):
      prc
    else:
      proto

  result = getAst docDecl(prototype, prc)
