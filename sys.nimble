# Package

version       = "0.0.4"
author        = "Leorize"
description   = "Abstractions for common operating system services"
license       = "MIT"
srcDir        = "src"


# Dependencies

when not defined(isNimSkull):
  requires "nim >= 2.0.0"
requires "https://github.com/nim-works/cps >= 0.11.0 & <0.12.0"
requires "https://github.com/status-im/nim-stew#3c91b8694e15137a81ec7db37c6c58194ec94a6a"
requires "https://github.com/khchen/winim >= 3.9.4 & < 4.0.0"
