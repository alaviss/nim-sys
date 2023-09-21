#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

when defined(posix):
  import pkg/balls
  import sys/paths

  suite "POSIX path handling tests":
    test "toPath() normalization":
      const tests = [
        # Normalized
        # -- Relative paths
        ("abc", "abc"),
        ("a/b", "a/b"),
        ("abc/def", "abc/def"),
        ("abc/../def", "abc/../def"),
        ("abc/def/ghi", "abc/def/ghi"),
        # -- Absolute paths
        ("/", "/"),
        ("/abc", "/abc"),
        ("/abc/def", "/abc/def"),
        ("/abc/../def", "/abc/../def"),
        # -- Parent-relative path
        ("..", ".."),
        ("../..", "../.."),
        ("../../abc", "../../abc"),
        # -- Current directory
        (".", "."),
        # -- Paths starting with dot
        ("...", "..."),
        (".abc", ".abc"),
        ("..abc", "..abc"),
        ("../...", "../..."),
        (".../...", ".../..."),
        ("abc/.def", "abc/.def"),
        ("abc/..def/.ghi", "abc/..def/.ghi"),
        ("/abc/.def/.ghi", "/abc/.def/.ghi"),
        ("/abc/..def/.ghi", "/abc/..def/.ghi"),

        # Empty path
        ("", "."),

        # Trailing slash
        # -- Relative paths
        ("abc/", "abc"),
        ("a/b/", "a/b"),
        ("abc/def/", "abc/def"),
        # -- Absolute paths
        ("/////", "/"),
        ("/abc/", "/abc"),
        ("/abc/def/", "/abc/def"),
        ("/abc/../def/", "/abc/../def"),
        # -- Parent-relative paths
        ("../", ".."),
        ("../../", "../.."),
        ("../../abc/", "../../abc"),
        # -- Current directory
        ("./", "."),
        ("./././.", "."),
        # -- Paths starting with dot
        (".../", "..."),
        (".abc/", ".abc"),
        ("..abc/", "..abc"),
        ("../.../", "../..."),
        (".../.../", ".../..."),
        ("abc/.def/", "abc/.def"),
        ("abc/..def/.ghi/", "abc/..def/.ghi"),
        ("/abc/.def/.ghi/", "/abc/.def/.ghi"),
        ("/abc/..def/.ghi/", "/abc/..def/.ghi"),

        # Double slash
        # -- Relative paths
        ("abc//", "abc"),
        ("abc///", "abc"),
        ("abc////", "abc"),
        ("a//b", "a/b"),
        ("abc//def", "abc/def"),
        ("abc//..////def", "abc/../def"),
        # -- Absolute paths
        ("/abc//", "/abc"),
        ("/abc///", "/abc"),
        ("/abc////", "/abc"),
        ("/abc//def", "/abc/def"),
        ("/abc//..////def", "/abc/../def"),
        # -- Parent-relative paths
        ("..////...", "../..."),
        ("..//...////", "../..."),
        ("...//...", ".../..."),
        ("...//...////", ".../..."),
        ("abc////.def", "abc/.def"),
        ("abc////..def/.ghi/", "abc/..def/.ghi"),
        ("/abc////.def/.ghi/", "/abc/.def/.ghi"),
        ("/abc////..def/.ghi/", "/abc/..def/.ghi"),

        # Dot element
        # -- Relative paths
        ("abc/.", "abc"),
        ("a/./b", "a/b"),
        ("abc/./def", "abc/def"),
        ("abc/.././def", "abc/../def"),
        ("./abc/.", "abc"),
        ("./a/./b", "a/b"),
        ("./abc/./def", "abc/def"),
        ("./abc/.././def", "abc/../def"),
        # -- Absolute paths
        ("/abc/.", "/abc"),
        ("/abc/./def", "/abc/def"),
        ("/abc/.././def", "/abc/../def"),
        # -- Parent-relative path
        ("../.", ".."),
        ("./..", ".."),
        (".././..", "../.."),
        (".././.././abc", "../../abc"),
        # -- Paths starting with dot
        ("./.../", "..."),
        (".../.", "..."),
        (".abc/.", ".abc"),
        ("..abc/.", "..abc"),
        (".././...", "../..."),
        ("..././...", ".../..."),
        ("abc/./.def", "abc/.def"),
        ("abc/..def/./.ghi/", "abc/..def/.ghi"),
        ("/./abc/.def/.ghi/", "/abc/.def/.ghi"),
        ("/./abc/./..def/.ghi/", "/abc/..def/.ghi"),
      ]

      for (orig, target) in tests:
        let normalized = orig.toPath.string
        check normalized == target,
              "expected '" & target & "' but got '" & normalized & '\''
        checkpoint "passed:", "'" & orig & "'", "->", "'" & normalized & "'"

    test "Joining paths":
      const tests = [
        ("", @["a"], "a"),
        ("", @["a", "b"], "a/b"),
        # Root-relative
        ("/", @["..", ".."], "/"),
      ]

      for (base, parts, target) in tests:
        var path = base.toPath
        path.join parts
        check path == target, "expected '" & target & "' but got '" & path & '\''
