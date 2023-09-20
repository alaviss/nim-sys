#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Cross-platform utilities to manipulate path names. The manipulation routines
## work directly on the paths and does not check the file system.

import std/strutils
import strings

type
  Path* {.requiresInit.} = distinct Nulless
    ## A distinct string representing an operating system path.
    ##
    ## For POSIX, the path will always be represented under the following rules:
    ##
    ## * Any `/..` at the beginning will be collasped into `/`.
    ##
    ## * Any `.` path element will be omitted, unless its the only element.
    ##
    ## * Any `//` will be converted to `/`.
    ##
    ## * Any trailing slash will be removed.
    ##
    ## For Windows, the path will always be represented under the following rules:
    ##
    ## * Any `/` separator will be converted to ``\``.
    ##
    ## * Any `\..` at the root component will be collasped into `\\`.
    ##
    ## * Any `.` path element will be omitted, unless its the only element or is necessary
    ##   for disambiguation.
    ##
    ## * Any `\\` will be converted to ``\``, unless they occur at the beginning of the path.
    ##
    ## * Any trailing backslash will be removed if they are not significant.
    ##
    ## * For DOS paths, the drive letter is always in uppercase.
    ##
    ## This type does not support Windows' native NT paths (paths starting with `\??`) and
    ## will treat them as relative paths. The `\\?` prefix should be used to
    ## handle them instead.
    ##
    ## The path is never an empty string.

  ComponentKind* {.pure.} = enum
    ## The type of path component
    Prefix ## The prefix in which a rooted path will start from.
           ##
           ## A path might have more than one prefix (ie. UNC host and shares).
           ## In such cases the prefixes can be concatenated into one using
           ## the `Separator`.
    Root
    PreviousDir
    Element

  ComponentSlice* = tuple
    ## A tuple describing a path component
    kind: ComponentKind
    slice: Slice[int] # The slice of the input string with the type

  Component* = tuple
    ## A tuple describing a path component
    kind: ComponentKind
    path: Path # The slice with the type

when defined(posix):
  include private/paths_posix
elif defined(windows):
  include private/paths_windows
else:
  {.error: "This module has not been ported to your operating system.".}

const
  Separator* = SeparatorImpl
    ## The main path separator of the target operating system.

  ValidSeparators* = ValidSeparatorsImpl
    ## The valid path separators of the target operating system.

converter toNulless*(p: Path): Nulless =
  ## One-way implicit conversion to nulless string.
  ##
  ## This allows read-only string operations to be done on `p`.
  Nulless(p)

converter toString*(p: Path): string =
  ## One-way implicit conversion to string.
  ##
  ## This allows read-only string operations to be done on `p`.
  string(p)

iterator componentSlices*(s: Path | Nulless): ComponentSlice =
  ## Parse `s` and yields its path components as slices of the input.
  ##
  ## Some normalizations are done:
  ##
  ## * Duplicated separators (ie. `//`) will be skipped.
  ##
  ## * Current directory (ie. `.`) will be skipped.
  ##
  ## * Previous directories relative to root (ie. `/..`) will be skipped.
  ##
  ## **Platform specific details**
  ##
  ## * Currently, `Prefix` is only yielded on Windows.
  ##
  ## * Windows' UNC prefix will be splitted into two parts, both branded as
  ##   `Prefix`.
  componentSlicesImpl()

iterator componentSlices*(s: string): ComponentSlice =
  ## Parse `s` and yields its path components as slices of the input.
  ##
  ## Overload of `componentSlices(Nulless) <#componentSlices,Nulless>`_ for
  ## strings.
  ##
  ## An error will be raised if `s` contains `NUL`.
  for result in s.toNulless.componentSlices:
    yield result

iterator components*(s: Path | Nulless): Component =
  ## Parse `s` and yields its path components.
  ##
  ## Some normalizations are done:
  ##
  ## * Duplicated separators (ie. `//`) will be skipped.
  ##
  ## * Current directory (ie. `.`) will be skipped.
  ##
  ## * Previous directories relative to root (ie. `/..`) will be skipped.
  for kind, slice in s.componentSlices:
    yield (kind, Path s[slice])

iterator components*(s: string): Component =
  ## Parse `s` and yields its path components as slices of the input.
  ##
  ## Overload of `components(Nulless) <#components,Nulless>`_ for
  ## strings.
  ##
  ## A `ValueError` will be raised if `s` contains `NUL`.
  for result in s.toNulless.components:
    yield result

func isAbsolute*(p: Path): bool {.inline, raises: [].} =
  ## Returns whether the path `p` is an absolute path.
  isAbsoluteImpl()

func join*[T: string | Nulless | Path](base: var Path, parts: varargs[T])
                                      {.raises: [ValueError].} =
  ## Join `parts` to `base` path.
  ##
  ## Each `parts` entry is treated as if its relative to the result of `base`
  ## joined with prior entries.
  ##
  ## If any of `parts` contains `NUL`, `ValueError` will be raised.
  ##
  ## **Platform specific details**
  ##
  ## * On Windows, drive-relative paths can only be created if the base itself is
  ##   pointing to a drive-relative entry (ie. `C:relative`). A bare drive like `C:`
  ##   will always be joined into a drive-absolute path to reduce the surprise factor.
  ##
  joinImpl()

func toPath*(p: sink Path): Path =
  ## Returns `p` as is. This is provided for generics.
  p

func toPath*(s: string | Nulless): Path {.raises: [ValueError].} =
  ## Convert the string `s` into a `Path`.
  ##
  ## An empty string is assumed to be `.` (current directory).
  ##
  ## Raises `ValuesError` if an invalid character is found in `s`.
  toPathImpl()

func `/`*[T: string | Nulless | Path](base, rel: T): Path
                                     {.raises: [ValueError], inline.} =
  ## Returns a path formed by joining `base` with `rel`.
  result = base.toPath
  result.join rel
