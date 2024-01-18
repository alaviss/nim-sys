# Package

version       = "0.1.0"
author        = "Leorize"
description   = "Abstractions for common operating system services"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.5.1"
requires "https://github.com/disruptek/balls >= 5.0.0 & < 6.0.0"
when (NimMajor, NimMinor, NimPatch) < (1, 9, 0):
  requires "https://github.com/nim-works/cps >= 0.8.0 & < 0.9.0"
else:
  requires "https://github.com/nim-works/cps >= 0.9.0 & < 0.10.0"
requires "https://github.com/status-im/nim-stew#3c91b8694e15137a81ec7db37c6c58194ec94a6a"

# Bundled as submodule instead since the package can only be installed on Windows.
# requires "https://github.com/khchen/winim#bffaf742b4603d1f675b4558d250d5bfeb8b6630"

task test, "Run test suite":
  when defined(windows):
    exec "balls.cmd"
  else:
    exec "balls"
