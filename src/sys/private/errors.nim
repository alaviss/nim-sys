#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

from std / os import raiseOsError, OSErrorCode

template posixChk*(op: untyped, errmsg: string = ""): untyped =
  ## Check whether the operation finished without error.
  ##
  ## If an error occur, `raiseOsError()` will be called with
  ## `errno` and `errmsg` as arguments
  if op == -1:
    raiseOsError(OSErrorCode errno, errmsg)
