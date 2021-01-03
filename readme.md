# An abstraction layer for common operating system services

This package is an experiment in rewriting various parts of stdlib's `os` module.

The goals are:
- To employ the use of destructors for resource lifetime management
- To provide simpler and more powerful interfaces to operating system services
- To abstract away OS differences and provide consistent and intuitive behaviors
- To reduce reliance on libc

Currently this project is a work-in-progress, and works here are aimed for upstreaming to the stdlib.

# On-going projects

These stdlib modules are targeted for redesign/reimplementation (ordered by priority):
- osproc
- io
- os

# Targets

This package primarily targets the following operating systems:

- Windows (not supported yet)
- Linux
- macOS

There is also second-tier support for:

- FreeBSD
- OpenBSD
- NetBSD
- POSIX-compatible OSes

These OS are not covered by automated testing, so they may break at any time.

# License

This project is distributed under the terms of the MIT license.

See [license.txt](license.txt) for more details.
