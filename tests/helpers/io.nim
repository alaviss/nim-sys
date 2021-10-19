#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import std/strutils
import sys/ioqueue

const Delimiter* = "\c\l\c\l"
  # The HTTP delimiter

let
  TestBufferedData* = "!@#$%^TEST%$#@!\n".repeat(2_000_000)
    ## A decently sized buffer that surpasses most OS pipe buffer size, which
    ## is usually in the range of 4-8MiB.
    ##
    ## Declared as a `let` to avoid binary size being inflated by the inlining.
  TestDelimitedData* = TestBufferedData & Delimiter
    ## The buffer used to test delimited reads.

proc accumlatedRead*[T](readable: T, size: Natural): string =
  ## Read until a buffer of `size` is reached or EOF is received.
  ##
  ## This is to be used with low-level interfaces from `files`.
  result.setLen(size)
  # The next position to start a read on
  var pos = 0

  while pos < result.len:
    let read = readable.read(result.toOpenArray(pos, result.len - 1))
    if read > 0:
      pos += read
    else:
      break

  # Set the result length to the actual amount read
  result.setLen(pos)

template makeAccRead*(T: untyped) =
  ## Generate asynchronous `accumlatedRead()` for type `T`
  proc accumlatedRead(readable: T, size: Natural): string {.asyncio.} =
    ## Read until a buffer of `size` is reached or EOF is reached.
    result.setLen(size)
    # The next position to start a read on
    var pos = 0

    while pos < result.len:
      let read = readable.read(
        cast[ptr UncheckedArray[byte]](addr result[pos]), result.len - pos
      )
      if read > 0:
        pos += read
      else:
        break

    # Set the result length to the actual amount read
    result.setLen(pos)

proc accumlatedWrite*[T](writable: T, buf: string) =
  ## Write until the entirety of `buf` is written to `writable`.
  # The next position to start a write on
  var pos = 0
  while pos < buf.len:
    pos += writable.write(buf.toOpenArray(pos, buf.len - 1))

template makeAccWrite*(T: untyped) =
  ## Generate asynchronous `accumlatedWrite()` for type `T`
  proc accumlatedWrite(writable: T, buf: string) {.asyncio.} =
    ## Write until the entirety of `buf` is written to `writable`.
    # The next position to start a write on
    var pos = 0
    while pos < buf.len:
      pos += writable.write(cast[ptr UncheckedArray[byte]](unsafeAddr buf[pos]), buf.len - pos)

const Chunk = 1024
  ## The amount of buffer space reserved for reading extra data.

proc delimitedRead*[T](readable: T, delimiter: string): string =
  ## Read until `delimiter` is found at the end of a read operation.
  ##
  ## This is used to simulate arbitrary reads.
  while true:
    # The next position to perform a read to, also the original length
    let pos = result.len

    # Accumulate extra space
    result.setLen(result.len + Chunk)

    # Read into the buffer slice
    let read = readable.read(result.toOpenArray(pos, result.len - 1))

    # Adjust the buffer space to the received data.
    result.setLen(pos + read)

    # If we found the marker, exit
    if result.endsWith(delimiter):
      break

template makeDelimRead*(T: untyped) =
  ## Generate asynchronous `delimitedRead()` for type `T`
  proc delimitedRead(readable: T, delimiter: string): string {.asyncio.} =
    ## Read until `delimiter` is found at the end of a read operation.
    ##
    ## This is used to simulate testing arbitrary reads, stopping on a distinct
    ## marker.
    while true:
      # The next position to perform a read to, also the original length
      let pos = result.len

      # Accumulate extra space
      result.setLen(result.len + Chunk)

      # Read into the buffer slice
      let read = readable.read(
        cast[ptr UncheckedArray[byte]](addr result[pos]), result.len - pos
      )

      # Adjust the buffer space to the received data.
      result.setLen(pos + read)

      # If we found the marker, exit
      if result.endsWith(delimiter):
        break
