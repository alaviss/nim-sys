#
#            Abstractions for operating system services
#                   Copyright (c) 2023 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import strsliceutils

const
  SeparatorImpl = '\\'
  ValidSeparatorsImpl = {SeparatorImpl, '/'}

type
  PathParseState = enum
    Start
    MaybeRoot
    FoundPrefix
    DosDrivePrefix
    UncPrefix
    AtRoot
    PathElement

  PathState = enum
    UncNeedHost
    UncNeedShare
    AtRoot
    Normal

template componentSlicesImpl() {.dirty.} =
  var state = Start

  for slice in s.splitSlices(ValidSeparators):
    var
      stay = true
      slice = slice
    while stay:
      stay = false
      case state
      of Start:
        # Drive letter and maybe a path component
        if s.slice(slice).hasDosDrive:
          yield (Prefix, 0 .. 1)
          state = DosDrivePrefix
          if slice.len > 2:
            # This is a relative path (ie. C:abc)
            # Trim the drive letter and switch gear
            slice = slice.a + 2 .. slice.b
            state = PathElement
            stay = true

        # Single \
        elif slice.len == 0:
          state = MaybeRoot

        else:
          state = PathElement
          stay = true

      of MaybeRoot:
        # This might be on the right of a \
        # Only yield prefix if there is something after this slice.
        if slice.len == 0 and slice.b + 1 < s.len:
          state = FoundPrefix
        else:
          yield (Root, 0 ..< 0)
          state = AtRoot
          stay = true

      of FoundPrefix:
        # Special prefix for NT and DOS paths
        if slice.len == 1 and s[slice.a] in {'.', '?'}:
          state = AtRoot
          yield (Prefix, slice.a - 2 .. slice.b)
          yield (Root, 0 ..< 0)
        # UNC otherwise
        elif slice.len > 0:
          state = UncPrefix
          yield (Prefix, slice.a - 2 .. slice.b)
        else:
          discard "Wait until we found something"

      of DosDrivePrefix:
        # There is something after the DOS drive, this is a rooted path
        yield (Root, 0 ..< 0)
        state = AtRoot
        stay = true

      of UncPrefix:
        if slice.len > 0:
          state = AtRoot
          yield (Prefix, slice)
          yield (Root, 0 ..< 0)

      of AtRoot:
        if s.slice(slice) == "." or s.slice(slice) == "..":
          discard ". and .. at root is still root"
        elif slice.len > 0:
          state = PathElement
          yield (Element, slice)

      of PathElement:
        if slice.len > 0:
          if s.slice(slice) == "..":
            yield (PreviousDir, slice)
          elif s.slice(slice) != ".":
            yield (Element, slice)

  case state
  # Nothing after we found '\'
  # Then it's just a root.
  of MaybeRoot:
    yield (Root, 0 ..< 0)
  # Found only `\\`
  # Consider it an incomplete UNC path.
  of FoundPrefix:
    yield (Prefix, s.len - 2 .. s.len - 1)
  else:
    discard "Nothing to do"

func isNotDos(p: Nulless | openarray[char]): bool =
  ## Returns whether `p` is not a DOS path.
  p.len > 1 and p[0] in ValidSeparatorsImpl and p[1] in ValidSeparatorsImpl

func hasDosDrive(p: Nulless | openarray[char]): bool =
  ## Returns whether `p` is prefixed with a DOS drive.
  p.len > 1 and p[1] == ':'

template isAbsoluteImpl(): bool {.dirty.} =
  p.isNotDos() or (p.len > 2 and p.slice(1..2) == r":\")

template joinImpl() {.dirty.} =
  # Temporary empty out the base if it's the current directory.
  #
  # The dot will be inserted for disambiguation as needed.
  if base == ".":
    base.string.setLen 0

  var state = PathState.Normal
  for kind, slice in base.componentSlices:
    case kind
    of Prefix:
      case state
      # First state entered
      of Normal:
        if base.slice(slice).isNotDos:
          if slice.len == 2:
            state = UncNeedHost
          elif slice.len == 3 and base[slice.b] in {'.', '?'}:
            discard "Still rather normal here"
          else:
            state = UncNeedShare
        else:
          discard "This is a DOS drive"
      of UncNeedShare:
        state = AtRoot
      of UncNeedHost, AtRoot:
        discard "These states cannot be reached from the start"
    of Root:
      state = AtRoot
    else:
      state = Normal
      break

  for part in parts.items:
    for kind, slice in part.componentSlices:
      var slice = slice
      case kind
      of Prefix:
        if part.slice(slice).isNotDos:
          # Skips \\
          inc slice.a, 2

      of Root:
        discard "Nothing to do"

      of PreviousDir:
        if state == AtRoot:
          continue

      else:
        discard "No processing needed"

      if slice.len > 0:
        if base.len == 0 and part.slice(slice).hasDosDrive:
          base.string.add r".\"
        elif base.len > 0 and base[^1] != Separator:
          base.string.add Separator

        base.string.add part.slice(slice)

        case state
        of UncNeedShare, UncNeedHost:
          # The share/host has just been added, cap it off
          base.string.add Separator
        else:
          discard

        state = if state != Normal: succ state else: state

  if base.len == 0:
    base.string.add "."

template toPathImpl() {.dirty.} =
  result = Path:
    # Create a new buffer with the length of `s`.
    var path = newString(s.len)
    # Set the length to zero, which lets us keep the buffer.
    path.setLen 0
    path

  var afterPrefix = false
  for kind, slice in s.componentSlices:
    case kind
    of Prefix:
      if s.slice(slice).isNotDos:
        # Skips the first two (back)slashes
        let slice = slice.a + 2 .. slice.b
        # Add our own
        result.string.add r"\\"
        # And the rest
        if slice.len > 0:
          result.string.add s.slice(slice)
          # Cap it off
          result.string.add '\\'
      elif not afterPrefix and s.slice(slice).hasDosDrive:
        # Normalize the drive by uppercasing it
        result.string.add: toUpperAscii s[slice.a]
        result.string.add ':'
      else:
        # UNC share name
        result.string.add s.slice(slice)

      afterPrefix = true
    of Root:
      # If it's right after a device or win32 namespace then
      # there might be a separator already.
      if result.len == 0 or result[^1] != Separator:
        result.string.add Separator

      afterPrefix = false
    else:
      # Add separator as needed
      if afterPrefix:
        discard "Don't add separator after a prefix to handle drive-relative results"
      elif result.len > 0 and result[^1] != Separator:
        result.string.add Separator
      # Disambiguates an element that looked like a drive
      elif result.len == 0 and s.slice(slice).hasDosDrive:
        result.string.add r".\"

      result.string.add s.slice(slice)

      afterPrefix = false

  # If path is empty, make it current directory
  if result.len == 0:
    result.string.add '.'
