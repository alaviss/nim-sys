#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Special kinds of strings used for interacting with certain operating system
## APIs.
##
## While mutating APIs are provided, they are limited to simple operations
## only. For performance it is recommended to convert them to strings, perform
## the necessary mutations, then use the checked converters.

import std/strutils

type
  Without*[C: static set[char]] = distinct string
    ## A distinct string type without the characters in set `C`.

const
  InvalidChar = "$1 is not a valid character for this type of string."
    # Error message used for setting an invalid character.

  FoundInvalid = "Invalid character ($1) found at position $2"
    # Error message used when an invalid character is found during search.

converter toString*(w: Without): lent string =
  ## Read-only converter from any `Without` type to a string. This enables
  ## drop-in compatibility with non-mutating operations on a string.
  w.string

template `[]`*[C](w: Without[C], slice: Slice[int]): Without[C] =
  ## Returns a copy of `w`'s `slice`.
  Without[C] w.string[slice]

template `[]`*[C](w: Without[C], slice: HSlice[int, BackwardsIndex]): Without[C] =
  ## Returns a copy of `w`'s `slice`.
  Without[C] w.string[slice]

func `[]=`*[C](w: var Without[C], i: Natural, c: char)
              {.inline, raises: [ValueError].} =
  ## Set the byte at position `i` of the string `w` to `c`.
  ##
  ## Raises `ValueError` if `c` is in `C`.
  if c notin C:
    string(w)[i] = c
  else:
    raise newException(ValueError, InvalidChar % escape $c)

func toWithout*(s: sink string, C: static set[char]): Without[C]
               {.inline, raises: [ValueError].} =
  ## Checked conversion to `Without[C]`.
  ##
  ## Raises `ValueError` if any character in `C` was found in the string.
  let invalidPos = s.find C
  if invalidPos != -1:
    raise newException(
      ValueError,
      FoundInvalid % [escape $s[invalidPos], $invalidPos]
    )
  result = Without[C](s)

func toWithout*[A](w: sink Without[A], C: static set[char]): Without[C]
               {.inline, raises: [ValueError].} =
  ## Convert between `Without` types.
  ##
  ## Raises `ValueError` if any character in `C` was found in the string.
  ##
  ## When `A` is equal to `C`, `w` will be returned and no check occurs. This
  ## makes it useful for use in generics.
  when A == C:
    w
  else:
    w.string.toWithout(C)

func filter*(s: string, C: static set[char]): Without[C] {.raises: [].} =
  ## Remove characters in set `C` from `s` and create a `Without[C]`.
  var i = 0
  result = Without[C](s)
  while i < result.len:
    if result[i] in C:
      result.string.delete(i, i)
    else:
      inc i

func filter*[A](w: Without[A], C: static set[char]): Without[C]
               {.raises: [].} =
  ## Remove characters in set `C` from `w` and create a `Without[C]`.
  ##
  ## When `A` is equal to `C`, `w` will be returned. This makes it useful for
  ## use in generics.
  when A == C:
    w
  else:
    w.string.filter(C)

template add*[C](w: var Without[C], s: Without[C]) =
  ## Append the string `s` to `w`.
  w.string.add s.string

func add*[C](w: var Without[C], s: string) =
  ## Append the string `s` to `w`.
  ##
  ## Raises `ValueError` if any character in `C` if found in the string `s`.
  let origLen = w.len
  try:
    w.string.setLen origLen + s.len
    for idx, c in s:
      w[origLen + idx] = c
  except:
    # Clean up on failure
    w.string.setLen origLen
    raise

func add*[C](w: var Without[C], c: char) {.inline, raises: [ValueError].} =
  ## Append the character `c` to `w`.
  ##
  ## Raises `ValueError` if `c` is in `C`.
  if c notin C:
    w.string.add c
  else:
    raise newException(ValueError, InvalidChar % escape $c)

type
  Nulless* = Without[{'\0'}]
    ## A string without the character NUL, mainly used for file paths or
    ## command arguments.

func toNulless*(s: sink string): Nulless
               {.inline, raises: [ValueError].} =
  ## Checked conversion to `NullessString`.
  ##
  ## Raises `ValueError` if any NUL character was found in the string.
  s.toWithout({'\0'})

func toNulless*(s: sink Nulless): Nulless
               {.inline, raises: [].} =
  ## Returns `s`. This function is provided for use in generics.
  s
