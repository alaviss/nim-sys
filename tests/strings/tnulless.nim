#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

import pkg/balls
import sys/strings

suite "Nulless tests":
  test "Converting a string without NUL is error-free":
    discard "NUL-less".toNulless

  test "Converting a string with NUL raises ValueError":
    expect ValueError:
      discard "NUL\0here".toNulless

  test "filter() don't affect compilant strings":
    check "NUL-less" == "NUL-less".filter({'\0'})

  test "filter() filters non-compliant characters":
    check "NUL\0here".filter({'\0'}) == "NULhere".toNulless

  test "Read operators":
    let sample = "NUL-less".toNulless
    check sample[0] == 'N'
    check sample[^1] == 's'

  test "Assigning compilant character":
    var sample = "NUL-less".toNulless
    sample[0] = 'n'

  test "Assigning non-compilant character raises ValueError":
    var sample = "NUL-less".toNulless
    expect ValueError:
      sample[0] = '\0'
    check sample == "NUL-less"

  test "Nulless can be added to Nulless":
    var sample = "NUL".toNulless
    sample.add "-less".toNulless
    check sample == "NUL-less"

  test "Adding compilant character":
    var sample = "NUL".toNulless
    sample.add '-'
    check sample == "NUL-"

  test "Adding non-compilant character raises ValueError":
    var sample = "NUL".toNulless
    expect ValueError:
      sample.add '\0'
    check sample == "NUL"

  test "Adding compilant string":
    var sample = "NUL".toNulless
    sample.add "-less"
    check sample == "NUL-less"

  test "Adding non-compilant string raises":
    var sample = "NUL".toNulless
    expect ValueError:
      sample.add "-\0less"
    check sample == "NUL"
