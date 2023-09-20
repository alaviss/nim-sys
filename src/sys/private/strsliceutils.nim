#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## General purpose string utilities that returns slices.
##
## TODO: This needs to be spun off into a project of its own

template slice*(s: string, slice: Slice[int]): untyped =
  ## Shorter alias for `toOpenArray(s, start, end)`
  toOpenArray(s, slice.a, slice.b)

template slice*(s: string, slice: HSlice[int, BackwardsIndex]): untyped =
  ## Shorter alias for `toOpenArray(s, start, end)`
  toOpenArray(s, slice.a, s.len - slice.b)

iterator splitSlices*(s: string, chars: set[char]): Slice[int] =
  ## A split iterator that yields slices of the input instead of copies of
  ## those slices.
  ##
  ## If `chars` is not found in `s`, the full range of the string is yielded.
  ##
  ## Only yields if `s` is not empty.
  var start = 0
  for idx, ch in s.pairs:
    if ch in chars:
      yield start ..< idx
      start = idx + 1

  # Yield the rest if its longer than 0 or if it ends in a delimiter
  let remainder = start ..< s.len
  if remainder.len > 0 or (start > 0 and s[start - 1] in chars):
    yield remainder

func add*(s: var string, buf: openArray[char]) =
  ## Append characters in `buf` to `s`.
  let writePos = s.len
  s.setLen(s.len + buf.len)
  copyMem(addr s[writePos], unsafeAddr buf[0], buf.len)
