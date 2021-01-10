# Package

version       = "0.1.0"
author        = "Leorize"
description   = "Abstractions for common operating system services"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.4.0"
requires "https://github.com/disruptek/testes >= 0.7.12"

# Bundled as submodule instead since the package can only be installed on Windows.
# requires "https://github.com/khchen/winim#bffaf742b4603d1f675b4558d250d5bfeb8b6630"

task test, "Run test suite":
  when defined(windows):
    exec "testes.cmd"
  else:
    exec "testes"
