#
#            Abstractions for operating system services
#                   Copyright (c) 2023 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

when defined(windows):
  import pkg/balls
  import sys/paths

  suite "Windows path handling tests":
    test "toPath() normalization":
      const tests = [
        # Normalized
        # -- Relative paths
        ("abc", "abc"),
        ("a/b", r"a\b"),
        ("abc/def", r"abc\def"),
        (r"abc\..\def", r"abc\..\def"),
        (r"abc\def\ghi", r"abc\def\ghi"),
        # -- Rooted paths
        (r"\", r"\"),
        ("/abc", r"\abc"),
        (r"\abc\def", r"\abc\def"),
        ("/abc/../def", r"\abc\..\def"),
        # -- Root-relative path
        (r"\..", r"\"),
        ("/../../abc", r"\abc"),
        # -- Parent-relative path
        ("..", ".."),
        ("../..", r"..\.."),
        (r"..\..\abc", r"..\..\abc"),
        # -- Current directory
        (".", "."),
        # -- Paths starting with dot
        ("...", "..."),
        (".abc", ".abc"),
        ("..abc", "..abc"),
        ("../...", r"..\..."),
        (r"...\...", r"...\..."),
        ("abc/.def", r"abc\.def"),
        (r"abc\..def\.ghi", r"abc\..def\.ghi"),
        ("/abc/.def/.ghi", r"\abc\.def\.ghi"),
        (r"\abc\..def\.ghi", r"\abc\..def\.ghi"),

        # Empty path
        ("", "."),

        # Drive-qualified path
        # -- Relative paths
        ("c:abc", "C:abc"),
        ("a:a/b", r"A:a\b"),
        ("1:abc/def", r"1:abc\def"),
        (r"@:abc\..\def", r"@:abc\..\def"),
        (r"D:abc\def\ghi", r"D:abc\def\ghi"),
        # -- Absolute paths
        (r"A:\", r"A:\"),
        ("a:/abc", r"A:\abc"),
        (r"#:\abc\def", r"#:\abc\def"),
        ("Q:/abc/../def", r"Q:\abc\..\def"),
        # -- Root-relative path
        (r"c:\..", r"C:\"),
        ("D:/../../abc", r"D:\abc"),
        # -- Parent-relative path
        ("R:..", "R:.."),
        ("R:../..", r"R:..\.."),
        (r"r:..\..\abc", r"R:..\..\abc"),
        # -- Current directory
        ("C:.", "C:"),
        ("c:", "C:"),
        # -- Paths starting with dot
        ("C:...", "C:..."),
        ("D:.abc", "D:.abc"),
        ("b:..abc", "B:..abc"),
        ("A:../...", r"A:..\..."),
        (r"F:...\...", r"F:...\..."),
        ("z:abc/.def", r"Z:abc\.def"),
        (r"a:abc\..def\.ghi", r"A:abc\..def\.ghi"),
        ("c:/abc/.def/.ghi", r"C:\abc\.def\.ghi"),
        (r"d:\abc\..def\.ghi", r"D:\abc\..def\.ghi"),

        # NT-qualified path
        # -- Absolute paths
        (r"\\.", r"\\.\"),
        ("//?/abc", r"\\?\abc"),
        (r"/\?\abc\def", r"\\?\abc\def"),
        ("//./abc/../def", r"\\.\abc\..\def"),
        # -- Root-relative path
        (r"/\?\..", r"\\?\"),
        ("//./../../abc", r"\\.\abc"),
        ("//?/../../abc", r"\\?\abc"),

        # UNC-qualified path
        # -- Absolute paths
        ("//hostonly", r"\\hostonly\"),
        (r"\\host\share", r"\\host\share\"),
        ("//another/c$", r"\\another\c$\"),
        (r"\/host\share\abc\def", r"\\host\share\abc\def"),
        ("//host/share/abc/../def", r"\\host\share\abc\..\def"),
        # -- Root-relative path
        (r"\\host\share\", r"\\host\share\"),
        ("//host/share/../../abc", r"\\host\share\abc"),
        ("//hostonly/..", r"\\hostonly\..\"),

        # Trailing slash
        # -- Relative paths
        ("abc/", "abc"),
        (r"a\b\", r"a\b"),
        ("abc/def/", r"abc\def"),
        # -- Rooted paths
        (r"\abc\", r"\abc"),
        ("/abc/def/", r"\abc\def"),
        (r"\abc\..\def\", r"\abc\..\def"),
        # -- Parent-relative paths
        ("../", ".."),
        (r"..\..\", r"..\.."),
        ("../../abc/", r"..\..\abc"),
        # -- Current directory
        (r".\", "."),
        ("./././.", "."),
        # -- Paths starting with dot
        (".../", "..."),
        (r".abc\", ".abc"),
        ("..abc/", "..abc"),
        (r"..\...\", r"..\..."),
        (".../.../", r"...\..."),
        (r"abc\.def\", r"abc\.def"),
        ("abc/..def/.ghi/", r"abc\..def\.ghi"),
        (r"\abc\.def\.ghi\", r"\abc\.def\.ghi"),
        ("/abc/..def/.ghi/", r"\abc\..def\.ghi"),
        # -- Incomplete UNC
        ("//////", r"\\"),
        (r"\/\/", r"\\"),

        # Double slash
        # -- Relative paths
        (r"abc\\", "abc"),
        ("abc///", "abc"),
        (r"abc\\\\", "abc"),
        ("a//b", r"a\b"),
        (r"abc\\def", r"abc\def"),
        ("abc//..////def", r"abc\..\def"),
        # -- Rooted paths
        (r"\abc\\", r"\abc"),
        ("/abc///", r"\abc"),
        (r"\abc\\\\", r"\abc"),
        ("/abc//def", r"\abc\def"),
        (r"\abc\\..\\\\def", r"\abc\..\def"),
        # -- Parent-relative paths
        ("..////...", r"..\..."),
        (r"..\\...\\\\", r"..\..."),
        ("...//...", r"...\..."),
        (r"...\\...\\\\", r"...\..."),
        ("abc////.def", r"abc\.def"),
        (r"abc\\\\..def\.ghi\", r"abc\..def\.ghi"),
        ("/abc////.def/.ghi/", r"\abc\.def\.ghi"),
        (r"\abc\\\\..def\.ghi\", r"\abc\..def\.ghi"),
        # -- UNC path
        ("//host/////share", r"\\host\share\"),
        (r"\\\\host", r"\\host\"),
        ("///host", r"\\host\"),

        # Dot element
        # -- Relative paths
        (r"abc\.", "abc"),
        ("a/./b", r"a\b"),
        (r"abc\.\def", r"abc\def"),
        ("abc/.././def", r"abc\..\def"),
        (r".\abc\.", r"abc"),
        ("./a/./b", r"a\b"),
        ("./abc/./def", r"abc\def"),
        (r".\abc\..\.\def", r"abc\..\def"),
        # -- Rooted paths
        ("/abc/.", r"\abc"),
        (r"\abc\.\def", r"\abc\def"),
        ("/abc/.././def", r"\abc\..\def"),
        # -- Parent-relative path
        (r"..\.", r".."),
        (r".\..", r".."),
        (".././..", r"..\.."),
        (r"..\.\..\.\abc", r"..\..\abc"),
        # -- Paths starting with dot
        ("./.../", "..."),
        (r"...\.", "..."),
        (".abc/.", ".abc"),
        (r"..abc\.", "..abc"),
        (".././...", r"..\..."),
        (r"...\.\...", r"...\..."),
        ("abc/./.def", r"abc\.def"),
        (r"abc\..def\.\.ghi\", r"abc\..def\.ghi"),
        ("/./abc/.def/.ghi/", r"\abc\.def\.ghi"),
        (r"\.\abc\.\..def\.ghi\", r"\abc\..def\.ghi"),
        ("./C:/notadrive", r".\C:\notadrive")
      ]

      for (orig, target) in tests:
        let normalized = orig.toPath.string
        check normalized == target,
              "expected '" & target & "' but got '" & normalized & '\''
        checkpoint "passed:", "'" & orig & "'", "->", "'" & normalized & "'"

    test "Joining paths":
      const tests = [
        ("", @["a"], "a"),
        ("", @["a", "b"], r"a\b"),
        # Base swapping is not allowed
        ("", @["C:", "Windows"], r".\C:\Windows"),
        ("", @[r"\\host\share", "foo/bar"], r"host\share\foo\bar"),
        # Always produce rooted drive paths
        ("c:", @["Windows", "System32"], r"C:\Windows\System32"),
        # Backing out of root
        (r"\", @["..", "../..", "stuff"], r"\stuff"),
        # Adding nothing means nothing happens
        (".", @[""], "."),
        ("C:", @[""], "C:"),
        (r"/\", @[""], r"\\"),
        (r"/\host\", @[""], r"\\host\"),
        (r"/\host\share\", @[""], r"\\host\share\"),
        # Can complete UNC paths
        ("//host", @["share", "..", "other"], r"\\host\share\other"),
        ("//host", @["share"], r"\\host\share\"),
        ("//", @["host"], r"\\host\")
      ]

      for (base, parts, target) in tests:
        var path = base.toPath
        path.join parts
        check path == target, "expected '" & target & "' but got '" & path & '\''
