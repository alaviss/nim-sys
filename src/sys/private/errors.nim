#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#             Copyright (c) 2015-2021 Nim contributors
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

{.experimental: "implicitDeref".}

from std/os import osErrorMsg, OSErrorCode
from syscall/posix import errno

template initOSError*(e: var OSError, errorCode: int32,
                      additionalInfo = "") =
  ## Initializes an OSError object. This is a copy of stdlib's newOSError
  ## but perform in-place creation instead.
  e.errorCode = errorCode
  e.msg = osErrorMsg(OSErrorCode errorCode)
  if e.msg == "":
    e.msg = "unknown OS error, code: ", $e.errorCode
  if additionalInfo.len > 0:
    if e.msg.len > 0 and e.msg[^1] != '\n': e.msg.add '\n'
    e.msg.add  "Additional info: "
    e.msg.addQuoted additionalInfo

proc newOSError*(errorCode: int32, additionalInfo = ""): ref OSError {.inline.} =
  result = new OSError
  result.initOSError(errorCode, additionalInfo)

template posixChk*(op: untyped, errmsg: string = ""): untyped =
  ## Check whether the operation finished without error.
  ##
  ## If an error occur, `raiseOsError()` will be called with
  ## `errno` and `errmsg` as arguments
  if op == -1:
    raise newOSError(errno, errmsg)
