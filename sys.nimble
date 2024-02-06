# Package

version       = "0.0.1"
author        = "Leorize"
description   = "Abstractions for common operating system services"
license       = "MIT"
srcDir        = "src"


# Dependencies

when not defined(isNimSkull):
  requires "nim >= 2.0.0"
requires "https://github.com/nim-works/cps ^= 0.10.1"
requires "https://github.com/status-im/nim-stew#3c91b8694e15137a81ec7db37c6c58194ec94a6a"

# Bundled as submodule instead since the package can only be installed on Windows.
# requires "https://github.com/khchen/winim#bffaf742b4603d1f675b4558d250d5bfeb8b6630"
