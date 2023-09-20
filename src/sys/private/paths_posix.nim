#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import strsliceutils

const
  SeparatorImpl = '/'
  ValidSeparatorsImpl = {SeparatorImpl}

template componentSlicesImpl() {.dirty.} =
  var atRoot = false # Whether we are at root FS

  for slice in s.splitSlices(ValidSeparators):
    # If the slice is zero-length
    if slice.len == 0:
      # If it starts at index 0
      if slice.a == 0:
        # Then this is created by the root position (ie. the left side of "/").
        yield (Root, 0 .. 0)
        atRoot = true

      # Otherwise its the same as "current directory" and can be omitted.
      else:
        discard "duplicated /, can be skipped"

    else:
      if s.slice(slice) == ".":
        discard "current directory are skipped"
      elif s.slice(slice) == "..":
        # Only yield previous directory if its not the root FS
        if not atRoot:
          yield (PreviousDir, slice)
      else:
        atRoot = false
        yield (Element, slice)

template isAbsoluteImpl(): bool {.dirty.} =
  p[0] == Separator

template joinImpl() {.dirty.} =
  # The joiner would join the path like this:
  #
  # base <- "a/b": "<base>/a/b"
  #
  # Which would result in:
  #
  # "." <- "a/b": "./a/b"
  #
  # which we do not want.
  #
  # To keep the logic simple, simply empty out the path here, which will be
  # interpreted by the joiner as "relative to current dir" and will not insert
  # a separator.
  if base == ".":
    base.string.setLen 0

  var atRoot = base == "/"
  for part in parts.items:
    for kind, slice in part.componentSlices:
      if kind == PreviousDir and atRoot:
        discard "At root"
      # Ignore "root" because all parts are supposed to be relative to the
      # current base.
      elif kind != Root:
        # If the next position is not at the start of the path and there were
        # no separator at the end of the current path.
        if base.len > 0 and base[^1] != Separator:
          # Insert a separator
          base.string.add Separator

        # Copy the slice to the current write position.
        base.string.add part.slice(slice)
        atRoot = false

  # If the path is empty
  if base.len == 0:
    # Set it to "."
    base.string.add '.'

template toPathImpl() {.dirty.} =
  result = Path:
    # Create a new buffer with the length of `s`.
    var path = newString(s.len)
    # Set the length to zero, which lets us keep the buffer.
    path.setLen 0
    path

  # If the path is absolute
  if s.len > 0 and s.Path.isAbsolute:
    # Set the base to `/`
    result.string.add '/'
  else:
    # Set the base to `.`
    result.string.add '.'

  # Add the path into `s`
  result.join s
