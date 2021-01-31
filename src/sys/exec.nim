#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

## Abstractions for process spawning/execution.

{.experimental: "implicitDeref".}

import std/[asyncdispatch, options, strtabs, strutils, times]
import files, handles, pipes

type
  NullessString* = distinct string
    ## A string without NUL, suitable for use as command arguments.

  EnvName* = distinct string
    ## A string without NUL and/or `=`, suitable for use as environment
    ## variable names.

  Environment* = distinct StringTableRef
    ## A string table for storing environment variables mappings. Semantics
    ## of this table corresponds to the target operating system.
    ##
    ## The NUL character can not be stored in this table.

  LaunchFlag* = enum
    ## Attributes used for launching programs
    lfClearEnv = "Clear environment" ## Clear all environment variables when
                                     ## launching the child process before
                                     ## applying the given Environment.
    lfClearFD = "Close open FDs" ## \
      ## Ensure all open FDs are closed, unless it is set for inheritance via
      ## Launcher.inherits.
      ## On supported POSIX-like systems, this flag might incur a significant
      ## performance penalty. Newer versions of Linux and FreeBSD have
      ## optimizations for this, however.
      ## Unsupported systems will yield a runtime error if this flag is set.

    lfSearchNoRelativePath = "Do not search relative paths" ## \
      ## Do not search within relative paths to the current working directory
      ## specified in PATH.
      ##
      ## PATH entries like "../foo" or "." or "" (empty) are ignored when
      ## this flag is set.
    lfNativeSearch = "Native program search" ## \
      ## Instead of performing the program search via findExe(), let the
      ## platform perform the search. While the use of this flag avoids the
      ## file system race associated with findExe(), this flag introduces
      ## platform-dependent behaviors that programs should be aware of.
      ##
      ## For example: Windows always perform searches within the current
      ## working directory, which might be unwanted and potentially be a
      ## security issue if left unchecked.
      ##
      ## All lfSearch* flags will be ignored if this flag is set.

    lfShell = "Launch via shell" ## \
      ## Use the shell to launch the program. `program` will be used as the
      ## command string for the shell. Setting `args` to a non-empty value
      ## will yield an error, unless `lfShellQuote` is specified.
    lfShellQuote = "Shell: Quote the arguments" ## \
      ## Quote `program` and `args` then construct the command string by
      ## concatenating them with a space.
      ##
      ## Only applied when `lfShell` is specified.

    lfUseFork = "POSIX: Launch with fork()" ## \
      ## POSIX-only. Use fork-exec pipeline to start the program. While slower
      ## and heavier than the default launch method (posix_spawn if available),
      ## it is more deterministic and supports older operating systems.
      ##
      ## Users might also define sysExecUseFork to force this flag even when
      ## a more efficient alternative is available (ie. due to targeting an
      ## older system).
      ##
      ## This flag is ignored on unsupported operating systems.
    lfUnsafeUseVFork = "Unsafe(Linux): Launch with vfork()" ## \
      ## Linux-only. Similar to lfUseFork but uses clone() with CLONE_VFORK and
      ## a separated stack (8MiB is allocated). While faster than fork-exec, it
      ## is extremely dangerous in multithreaded processes due to potential
      ## races. Do not use unless you understand the risks. The default launch
      ## method should be as fast without the downsides.
      ##
      ## Overrides lfUseFork if set. This flag is ignored on unsupported
      ## operating systems.

  StdioKind* = enum
    ## Type of standard input/output handles.
    skParent = "Inherit from parent" ## Uses the parent standard input/output
                                     ## streams.
    skClosed = "Closed" ## Close the stream. Should only be used with processes
                        ## that are aware of this fact. Use initNulStdio()
                        ## instead if you want to discard the child process
                        ## streams.
    skFile = "File" ## A File. Note that this file will share the offset
    skWritePipe = "Write-end of a pipe" ## \
      ## Only the write end of a pipe. Usage of this end as stdin will raise
      ## an error. This end will be closed in the parent process on launch.
    skReadPipe = "Read-end of a pipe" ## \
      ## Only the read end of a pipe. Usage of this end as stdout or stderr
      ## will raise an error. This end will be closed in the parent process
      ## on launch.
    skHandle = "Handle" ## A reference to a Handle[FD].
    skFD = "FD" ## An untracked FD. The user is responsible for keeping the
                ## FD alive until the child process launch.
                ## Failure to do so might cause the launch to fail or the
                ## child process to misbehave.

  Stdio* = object
    ## An object containing suitable handles for use as standard input/output.
    case kind: StdioKind
    of skParent, skClosed:
      discard
    of skFile:
      file: files.File
    of skWritePipe:
      wr: WritePipe
    of skReadPipe:
      rd: ReadPipe
    of skHandle:
      handle: ref Handle[FD]
    of skFD:
      fd: FD

  # NOTE: PlatformOptions is meant as a tool for performing simple extension of
  # Launcher. There is only one criteria for what fields should be added: If it
  # is easier to perform the wanted behavior via direct usage of the OS native
  # APIs, then it should not be here.
  PlatformOptions* = object
    ## Platform-specific launch options which allow for fine-grained control
    ## over the process launch process.
    when defined(posix):
      forkOps*: seq[proc(l: Launcher): bool {.raises:[].}] ## \
        ## Additional procedures to be run on fork() before execve().
        ## Operations performed by this library will be performed before these
        ## procedures are executed. These procedures should return a boolean
        ## signifying whether the operation was successful. Execution will
        ## be aborted on failure and the errno will be reported to the parent.
        ##
        ## Avoid allocating memory as it will drastically slow down the
        ## procedure. Do not allocate any memory if lfUnsafeUseVFork is used
        ## (Linux-only).
        ##
        ## Usage of this field implies lfUseFork.
    elif defined(windows):
      rawCmdLine*: string ## \
        ## The raw UTF-8 command line to be passed to CreateProcess(). The
        ## library will convert the command line to Windows' Unicode. This
        ## allows the user to perform their own parameter quoting.
        ##
        ## Overrides `Launcher.program`, `Launcher.args`, `lfShell` if set to a
        ## non-empty value.

  Launcher* = object
    ## An object containing common settings used to start a program.
    program*: NullessString ## The program that is to be run.
    args*: seq[NullessString] ## The arguments to be passed to the program.
    env*: Environment ## The environment modifications to be made to the
                      ## child process.
    workingDir*: string ## The working directory for the launching process.
                        ## If it's empty, defaults to the current working
                        ## directory.
    stdin*, stdout*, stderr*: Stdio ## Standard input, output, error streams
                                    ## for the child process.
    inherits*: seq[FD] ## A list of FDs to be inherited as-is. The user is
                       ## responsible for keeping these FDs alive until after
                       ## the launch of the child process.
    flags*: set[LaunchFlag] ## Attributes used to launch the program.
    popts*: PlatformOptions ## Platform-specific launch options.

func toNulless*(s: sink string): NullessString
               {.inline, raises: [ValueError].} =
  ## Convert a `string` into `NullessString`, raises `ValueError` if any NUL
  ## character was found in the string.
  let nulPos = s.find '\0'
  if nulPos != -1:
    raise newException(ValueError, "NUL character found at position " & $nulPos)
  result = s.NullessString

func toNulless*(s: sink NullessString): NullessString {.inline.} =
  ## A no-op if the string is already a NullessString, useful for generics.
  s

func toEnvName*(s: sink string): EnvName {.inline, raises: [ValueError].} =
  ## Convert a `string` into `EnvName`, raises `ValueError` if any NUL or `=`
  ## character was found in the string.
  let invalidPos = s.find {'\0', '='}
  if invalidPos != -1:
    raise newException(ValueError, "NUL or '=' character found at position " & $invalidPos)
  result = s.EnvName

func toEnvName(s: sink EnvName): EnvName {.inline.} =
  ## A no-op for `EnvName` for generics.
  s

func len*(s: NullessString): int {.borrow.}
  ## Get the length of the passed NullessString.

func contains*(e: Environment, key: string or EnvName): bool {.inline.} =
  ## Check if the variable `key` is in the environment.
  key.toEnvName.string in StringTableRef(e)

func `[]`*(e: Environment, key: string or EnvName): NullessString {.inline.} =
  ## Retrieve the environment variable `key` from the environment.
  NullessString StringTableRef(e)[key.toEnvName.string]

func `[]=`*[T: NullessString or string](e: Environment, key: string or EnvName,
                                        value: sink T) {.inline.} =
  ## Put the `value` for environment variable `key` into the environment.
  if key.string.len == 0:
    raise newException(ValueError, "The environment variable key must not be empty")
  StringTableRef(e)[key.toEnvName.string] = value.toNulless.string

iterator pairs*(e: Environment): tuple[name: EnvName, val: NullessString] =
  ## Iterates through all variables in the environment.
  for n, v in StringTableRef(e):
    yield (n.EnvName, v.NullessString)

func del*(e: Environment, key: string or EnvName) {.inline.} =
  ## Remove the environment variable `key` from the environment.
  ##
  ## This is the equivalence to setting the value of the variable `key` to
  ## an empty value.
  e[key] = "".toNulless

func add*(s: var seq[NullessString], arg: sink string) {.inline.} =
  ## Add the argument `arg` to `s`.
  ##
  ## This is a convenience overload to automate the conversion to
  ## NullessString.
  s.add arg.toNulless

func add*(s: var seq[NullessString], args: openArray[string]) {.inline.} =
  ## Add the arguments in `args` to `s`.
  ##
  ## This is a convenience overload to automate the conversion to
  ## NullessString.
  for arg in args:
    s.add arg

func set*(s: var seq[NullessString], args: openArray[string]) {.inline.} =
  ## Replace the contents of `s` with `args`.
  ##
  ## This is a convenience function to automate the conversion to
  ## NullessString.
  s.setLen 0
  s.add args

func initParentStdio*(): Stdio {.inline.} =
  ## Creates a Stdio object indicating an inherited stream.
  Stdio(kind: skParent)

func initClosedStdio*(): Stdio {.inline.} =
  ## Creates a Stdio object indicating a closed stream.
  ##
  ## Most programs assume an open Stdio, and may misbehave if those are
  ## closed. If you only want to discard the program stdio streams, use
  ## `initNulStdio() <#initNulStdio>`_ instead.
  Stdio(kind: skClosed)

func initStdio*(f: files.File): Stdio {.inline.} =
  ## Creates a Stdio object referring to a File.
  Stdio(kind: skFile, file: f)

func initStdio*(wr: WritePipe): Stdio {.inline.} =
  ## Creates a Stdio object referring to a WritePipe.
  ##
  ## This object can not be used as the standard input for the child process.
  ## The referred pipe endpoint will be closed on child process execution.
  ##
  ## .. code-block:: nim
  ##   import std/sugar
  ##   import sys/[exec, pipes]
  ##
  ##   let
  ##     (rd, wr) = newPipe(Rd = AsyncReadPipe)
  ##     childOut = initStdio(wr)
  ##
  ##   let process = initLauncher("echo", "hello!").dup(stdout = childOut, stderr = childOut).launch()
  ##
  ##   # Enjoy asynchronous reads.
  ##   let buf = newString(40)
  ##   waitFor childOut.read(buf)
  Stdio(kind: skWritePipe, wr: wr)

func initStdio*(rd: ReadPipe): Stdio {.inline.} =
  ## Creates a Stdio object referring to a ReadPipe.
  ##
  ## This object can not be used as the standard output or error for the child
  ## process. The referred pipe endpoint will be closed on child process
  ## execution.
  ##
  ## .. code-block:: nim
  ##   import sys/[exec, pipes]
  ##
  ##   let
  ##     (rd, wr) = newPipe(Wr = AsyncWritePipe)
  ##     childIn = initStdio(rd)
  ##
  ##   # Launch child process...
  ##
  ##   # Enjoy asynchronous writes.
  ##   let buf = socket.recvLine()
  ##   waitFor childIn.write(waitFor buf)
  Stdio(kind: skReadPipe, rd: rd)

func initStdio*(h: ref Handle[FD]): Stdio {.inline.} =
  ## Creates a Stdio object holding a reference to a Handle[FD].
  Stdio(kind: skHandle, handle: h)

func initStdio*(fd: FD): Stdio {.inline.} =
  ## Creates a Stdio object holding a FD.
  ##
  ## The user is responsible for keeping the FD alive until after the child
  ## process executed.
  Stdio(kind: skFD, fd: fd)

func kind*(s: Stdio): StdioKind {.inline.} =
  ## Returns the type of the passed Stdio object.
  s.kind

func file*(s: Stdio): files.File {.inline.} =
  ## Returns the file held by the passed Stdio object.
  s.file

func `file=`*(s: var Stdio, f: files.File) {.inline.} =
  ## Replace the file held by `s` with `f`.
  s.file = f

func fd*(s: Stdio): FD {.inline.} =
  ## Returns the `FD` held by `s`. Works with any `StdioKind` containing only
  ## one FD.
  case s.kind
  of skFD:
    s.fd
  of skHandle:
    s.handle.get
  of skReadPipe:
    s.rd.fd
  of skWritePipe:
    s.wr.fd
  of skFile:
    s.file.fd
  else:
    s.fd # A runtime error will be triggered due to mismatched discriminator.

func `fd=`*(s: var Stdio, fd: FD) {.inline.} =
  ## Replace the `FD` held by `s` with `fd`. Unlike `fd()`, this only work with
  ## `skFD` Stdio.
  s.fd = fd

func readPipe*(s: Stdio): ReadPipe {.inline.} =
  ## Returns the read endpoint held by `s`.
  s.rd

func `readPipe=`*(s: var Stdio, rp: ReadPipe) {.inline.} =
  ## Replaces the read endpoint held by `s` with `rp`.
  s.rd = rp

func writePipe*(s: Stdio): WritePipe {.inline.} =
  ## Returns the write endpoint held by `s`.
  s.wr

func `writePipe=`*(s: var Stdio, wp: WritePipe) {.inline.} =
  ## Replaces the write endpoint held by `s` with `wp`.
  s.wr = wp

func command*(program: string or NullessString,
              args: varargs[NullessString, toNulless]): Launcher =
  ## Creates a new Launcher object for launching the specified `program` with
  ## the given `args`.
  ##
  ## Default settings includes:
  ## - Inherit stdio streams from parent.
  ## - All inheritable FDs are inherited by default.
  if program.len == 0:
    raise newException(ValueError, "`program` must not be empty")
  result = Launcher(program: program.toNulless, args: @args)

func shell*(command: string or NullessString): Launcher =
  ## Creates a new Launcher object for running the given `command` via the
  ## shell.
  ##
  ## Default settings are similar to `command()`_, except that the `lfShell`
  ## flag is set.
  if command.len == 0:
    raise newException(ValueError, "`command` must not be empty")
  result = command(command)
  result.flags.incl lfShell

const
  ErrorLaunch = "Could not launch the specified program"
    ## Used when `launch()` fails.

  ErrorWait = "Could not wait for the specified process (PID: $1)"
    ## Used when `wait()` fails.

when defined(posix):
  include private/exec_posix
else:
  {.error: "This module has not been ported to your operating system".}

type
  ProcessId* = ProcessIdImpl
    ## A type representing the process identifier.

  Process* = ref ProcessImpl
    ## An object representing a child process.

  ProcessStatus* = ProcessStatusImpl
    ## A type representing the OS process status.

func `=copy`(dst: var ProcessImpl, src: ProcessImpl) {.error.}
  ## Copying a `Process` is forbidden.

func exited*(ps: ProcessStatus): bool {.inline, raises: [].} =
  ## Whether the given `ps` indicates that the process exited normally.
  exitedImpl()

func exitCode*(ps: ProcessStatus): Option[int] {.inline, raises: [].} =
  ## Retrieve the exit code from `ps`.
  ##
  ## The exit code might not be available if the process was terminated because
  ## of a signal.
  exitCodeImpl()

func success*(ps: ProcessStatus): bool {.inline, raises: [].} =
  ## Whether the given `ps` indicates a successful run.
  ##
  ## Typically means that the process terminated with exit code 0.
  successImpl()

func signaled*(ps: ProcessStatus): bool {.inline, raises: [].} =
  ## Whether the given `ps` indicates that the process was terminated by a
  ## signal.
  signaledImpl()

func signal*(ps: ProcessStatus): Option[int] {.inline, raises: [].} =
  ## Returns the number of the signal that terminated the process.
  signalImpl()

proc pid*(p: Process): ProcessId =
  ## Returns the PID of the passed process `p`.
  pidImpl()

proc wait*(p: Process, timeout: Duration): Option[ProcessStatus] =
  ## Wait for the passed process `p` to exit.
  ##
  ## Returns the status of `p` if the process stopped before `timeout`.
  waitTimeoutImpl()

proc wait*(p: Process): ProcessStatus =
  ## Wait for the passed process `p` to exit.
  ##
  ## Returns the status of `p`.
  waitImpl()

proc terminated*(p: Process): bool =
  ## Returns whether the passed process `p` has terminated.
  terminatedImpl()

proc waitAsync*(p: Process): Future[ProcessStatus] =
  ## Wait for the passed process `p` to exit, asynchronously.
  ##
  ## Returns the exit code of `p`.
  asyncWaitImpl()

func newEnvironment(envs: varargs[tuple[name, value: string]]): Environment =
  ## Creates a new Environment object from the given `name`, `value` pairs.
  result = Environment newStringTable(EnvTableMode)
  for (name, value) in envs:
    result[name] = value

proc initNulStdio(): Stdio =
  ## Returns an Stdio object pointing to the operating system's "null" device,
  ## which consumes all input and provides zero output.
  initNulStdioImpl()

proc findExe*(name: string, flags: set[LaunchFlag] = {}): string =
  ## Returns the path to the executable with the specified `name` in the
  ## operating system's search path. An empty string is returned none were
  ## found.
  ##
  ## If `name` contains a directory separator, it is tried immediately and no
  ## search will occur.
  ##
  ## This procedure behavior can be altered via `lfSearch*` flags.
  ## `lfNativeSearch` is ignored.
  ##
  ## **Notes**
  ## - There is an inherent file system race with this procedure, where the
  ##   returned PATH might no longer be executable at the time of execution.
  ##   However, this does not matter for most applications.
  ## - The returned path at most is only verified to have the "executable"
  ##   permission set. This procedure does not verify whether it is actually
  ##   possible to execute the returned file, since the only way to verify
  ##   is to actually execute the program.
  ## - This procedure is an exported helper for `launch` since it is useful.
  ##   This means its functions are limited to the most common usecases.
  ##   Programs needing specialized functions are advised to develop their own
  ##   `findExe()` or `launch()`.
  ##
  ## **Platform specific behaviors**
  ## - On Windows, the environment variable `PATHEXT` specifies a
  ##   semicolon-delimited list of extensions to be tried. If unset or empty, a
  ##   reasonable default is used.
  findExeImpl()

proc launch*(l: Launcher): Process =
  ## Launch the program specified by the given Launcher.
  ##
  ## If any of `stdin`, `stdout`, `stderr` is a pipe type, the pipe ending
  ## passed to the child will be closed.
  ##
  ## The environment should not be modified during program launch. In the
  ## future this restriction might be removed.
  ##
  ## **Platform specific details**
  ## - On Windows, certain types of executables (ie. batch files) will be
  ##   launched via the shell regardless of `lfShell` flag. This detection
  ##   may not be available if `lfNativeSearch` is set†
  ## - On Windows, `launch()` and its variants are serialized to avoid race
  ##   conditions regarding inheritable files.
  ## - On POSIX, errors happened in between fork-exec will be reported if
  ##   obtainable, otherwise 127 will be used as the exit code.
  if l.stdin.kind == skWritePipe:
    raise newException(ValueError, "A " & $l.stdin.kind & " can not be used as stdin")
  if l.stdout.kind == skReadPipe:
    raise newException(ValueError, "A " & $l.stdout.kind & " can not be used as stdout")
  if l.stderr.kind == skReadPipe:
    raise newException(ValueError, "A " & $l.stderr.kind & " can not be used as stderr")
  if lfShell in l.flags and lfShellQuote notin l.flags and l.args.len > 0:
    raise newException(ValueError, "`args` must not be set if lfShell is used without lfShellQuote")
  launchImpl()

proc exec*(l: Launcher): tuple[p: Process, status: ProcessStatus] =
  ## Launch the program specified by the given Launcher, then wait until it
  ## exits.
  result.p = launch l
  result.status = wait result.p

proc captureOutput*(l: Launcher): tuple[p: Process, output: string] =
  ## Launch the program specified by the given Launcher, then capture all
  ## output produced.
  ##
  ## Any `stdin`, `stdout`, `stderr` settings are ignored and overridden with:
  ## - `stdin` is set to `initNulStdin()`
  ## - `stdout`, `stderr` is set to the same `WritePipe` created by this
  ##   procedure.
  ##
  ## Blocks until the process exits.
  var l = l
  l.stdin = initNulStdio()
  let (rd, wr) = newPipe()
  l.stdout = initStdio(wr)
  l.stderr = initStdio(wr)
  result.p = launch l

  while true:
    let next = result.output.len
    result.output.setLen result.output.len + 4096
    let read = rd.read result.output.toOpenArrayByte(next, result.output.high)
    result.output.setLen result.output.len - 4096 + read
    if read == 0:
      break
