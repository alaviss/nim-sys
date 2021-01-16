#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import pkg/balls

type
  GotDefect = object of CatchableError

template expectDefect*(body: untyped) =
  when not defined(nimPanics):
    expect GotDefect:
      try:
        body
      except Defect:
        raise newException(GotDefect, "defect catched")
  else:
    skip("--panics is enabled")
