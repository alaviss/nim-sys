#
#            Abstractions for operating system services
#                   Copyright (c) 2021 Leorize
#
# Licensed under the terms of the MIT license which can be found in
# the file "license.txt" included with this distribution. Alternatively,
# the full text can be found at: https://spdx.org/licenses/MIT.html

from std/os import getEnv, putEnv
import std/sugar
import syscall/posix/spawn
import syscall/posix
import errors
import signalsafe_posix as ss

const EnvTableMode = modeCaseSensitive

type
  ProcessIdImpl = distinct Pid
  ProcessStatusImpl = distinct cint
  ProcessImpl {.requiresInit.} = object
    pid: ProcessIdImpl
    status: Option[ProcessStatusImpl]

template exitedImpl() {.dirty.} =
  result = WIfExited(ps.cint)

template exitCodeImpl() {.dirty.} =
  if ps.exited:
    result = some(int WExitStatus(ps.cint))

template successImpl() {.dirty.} =
  let exitCode = ps.exitCode
  if exitCode.isSome:
    result = get(exitCode) == 0

template signaledImpl() {.dirty.} =
  result = WIfSignaled(ps.cint)

template signalImpl() {.dirty.} =
  if ps.signaled:
    result = some(int WTermSig(ps.cint))

template pidImpl() {.dirty.} =
  result = p.pid

proc getStatus(pid: ProcessIdImpl, wait: bool): Option[ProcessStatusImpl] =
  ## Get the current status of the given process id.
  var status: cint
  let flags =
    if wait:
      0.cint
    else:
      WNoHang
  let ret = waitpid(pid.Pid, status, flags)
  posixChk ret, ErrorWait % $pid.Pid
  if ret != 0:
    result = some status.ProcessStatusImpl

template waitTimeoutImpl() {.dirty.} =
  if p.status.isSome:
    result = p.status
  elif timeout == DurationZero:
    p.status = p.pid.getStatus(wait = false)
    result = p.status
  else:
    doAssert false, "waiting with a non-zero timeout is not supported"

template waitImpl() {.dirty.} =
  if p.status.isSome:
    result = get p.status
  else:
    p.status = p.pid.getStatus(wait = true)
    result = get p.status

template terminatedImpl() {.dirty.} =
  result = p.wait(DurationZero).isSome

template asyncWaitImpl() {.dirty.} =
  result = newFuture[ProcessStatus]("exec.waitAsync")
  let future = result

  proc retrieveStatus(_: AsyncFD): bool =
    var status: Option[ProcessStatusImpl]

    try:
      status = p.wait(DurationZero)
    except:
      future.fail getCurrentException()
      return

    if status.isSome:
      future.complete get status
    else:
      result = true

  addProcess(p.pid.Pid, retrieveStatus)

template initNulStdioImpl() {.dirty.} =
  let fd = posix.open("/dev/null", ORdWr or OCloExec)
  posixChk fd
  let file = newFile(fd.FD)
  result = Stdio(kind: skFile, file: file)

# TODO: Move to sys/paths when that become a thing.
const
  DirSep = '/'
  PathSep = ':'

## TODO: move to sys/fs once that become a thing.
proc checkExe(path: string): bool =
  ## Check if the given path is executable and is a file.
  ##
  ## Ignores all errors.
  var fileInfo: Stat
  if stat(path.cstring, fileInfo) == -1:
    return false
  # Check if the executable bit is set, since even root need that bit set
  # before it can executes.
  if SIsDir(fileInfo.stMode) or (fileInfo.stMode and 0o111u32) == 0:
    return false
  # More checks (like user-group) can be done, but given the race condition
  # currently exhibited by findExe(), it is pointless to waste more cycles on
  # this.
  result = true

template findExeImpl() {.dirty.} =
  if name.len == 0:
    result = ""
  elif DirSep in name:
    if checkExe(name):
      result = name
    else:
      result = ""
  else:
    let path = getEnv("PATH")
    for idx, c in path:
      if c != PathSep and idx < path.high:
        result.add c
      else:
        if (
          (result.len != 0 and result[0] == DirSep) or
          lfSearchNoRelativePath notin flags
        ):
          if result.len == 0:
            result.add "."
          result.add DirSep
          result.add name.string
          if checkExe(result):
            return
          result.setLen 0

type
  CStrSeq = distinct seq[cstring]
    ## seq[cstring] but with an extra `nil` at the end for C interop.
    ## Entries added to this array are only valid for as long as the source
    ## itself, so be careful in choosing what goes in or out.
    ##
    ## At least one entry has to be added.

  NullessStrSeq = object
    ## An object representing a sequence of NUL-terminated strings.
    buf: string
    arr: CStrSeq

func add(cs: var CStrSeq, v: cstring) =
  ## Adds `v` into `s`
  template s: untyped = seq[cstring](cs)
  if s.len == 0:
    s.add nil
  s[s.high] = v
  s.add nil

func toCStringArray(s: CStrSeq): ptr UncheckedArray[cstring] =
  ## Return the cstring array.
  cast[ptr UncheckedArray[cstring]](seq[cstring](s)[0])

func toCStringArray(n: NullessStrSeq): ptr UncheckedArray[cstring] =
  ## Returns the cstring array, which stays alive for the duration of `n`.
  n.arr.toCStringArray

template addItem(n: var NullessStrSeq, body: untyped) =
  ## Efficient way to piece data using the `n` internal buffer
  template piece(c: char) {.used.} =
    doAssert c != '\0', "NUL must not be added"
    n.buf.add c
  template piece(s: NullessString) {.used.} =
    n.buf.add s.string

  let start = n.buf.len
  try:
    body
  finally:
    n.buf.add '\0'
    n.arr.add cast[cstring](addr n.buf[start])

func add(n: var NullessStrSeq, val: NullessString) =
  ## Add the string `val` into the seq.
  n.addItem:
    piece val

func addEnviron(n: var NullessStrSeq, key: EnvName, val: NullessString) =
  ## Add the environment string consist of `key` with value `val` to `n`.
  n.addItem:
    piece key.NullessString
    piece '='
    piece val

## TODO: This goes into sys/env or sys/process
var environ {.importc.}: ptr UncheckedArray[cstring]
iterator environment(): tuple[key: EnvName, val: NullessString] =
  ## Parses the global environment, then return the key and value.
  ##
  ## According to POSIX this operation is not thread-safe.
  var i = 0
  while environ != nil and environ[i] != nil:
    var
      key: EnvName
      val: NullessString
      keyDone = false
      j = 0
    while environ[i][j] != '\0':
      if not keyDone:
        if environ[i][j] != '=':
          key.string.add environ[i][j]
        else:
          keyDone = true
      else:
        val.string.add environ[i][j]

      inc j

    if keyDone:
      yield (key, val)
    else:
      doAssert false, "The environment is invalid! Your operating " &
                      " system may not be conforming to POSIX or your" &
                      " application is modifying the environment in an" &
                      " another thread while it is being read."

    inc i

template buildEnv(l: Launcher): ptr UncheckedArray[cstring] =
  ## Build an environment vector from Launcher.
  ##
  ## Defined as a template to prevent the creation of a new scope, keeping
  ## allocated strings alive until after launch.
  var result: ptr UncheckedArray[cstring]

  if l.env.StringTableRef.len == 0:
    if lfClearEnv notin l.flags:
      result = environ
    else:
      var newEnv = newSeq[cstring](1)
      newEnv[0] = nil
      result = cast[ptr UncheckedArray[cstring]](addr newEnv[0])
  else:
    let e =
      if lfClearEnv notin l.flags:
        # Copy our environment so we can modify it.
        var result = newStringTable(EnvTableMode)
        for name, val in l.env.StringTableRef.pairs():
          result[name] = val
        Environment result
      else:
        l.env
    var newEnv: NullessStrSeq
    if lfClearEnv notin l.flags:
      # Add and transform the current environment.
      for name, val in environment():
        if name in e:
          if e[name].len > 0:
            newEnv.addEnviron name, e[name]
          else:
            discard "Empty environment means remove"
          e.del name
        else:
          newEnv.addEnviron name, val
    # Add new environment.
    for name, val in e:
      newEnv.addEnviron name, e[name]
    result = newEnv.toCStringArray()

  result

func addShellQuoted(s: var NullessString, v: NullessString) =
  ## Add shell quoted version of `v` into `s`.
  # XXX: Maybe should be a public API.
  const NeedQuoting = {
    '|', '&', ';', '<', '>', '(', ')', '$', '`', '\\', '"', '\'', ' ', '\t',
    '\n', '*', '?', '[', '#', '~', '=', '%'
  }
    ## Obtained from POSIX shell grammar:
    ## https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_02

  proc add(s: var NullessString, c: char) {.borrow.}
  proc add(s: var NullessString, c: string) {.borrow.}
  proc add(s: var NullessString, c: NullessString) {.borrow.}
  iterator items(s: NullessString): char {.borrow.}

  var needQuoting = false
  for c in v:
    if c in NeedQuoting:
      needQuoting = true
      break

  if not needQuoting:
    s.add v
  else:
    s.add '\''
    for c in v:
      if c == '\'':
        s.add "'\\''"
      else:
        s.add c
    s.add '\''

template buildArg(l: Launcher): ptr UncheckedArray[cstring] =
  ## Build an argument list from the launcher.
  ##
  ## Defined as a template to prevent the creation of a new scope, keeping
  ## allocated strings alive until after launch.
  var result: CStrSeq

  if lfShell in l.flags:
    result.add "sh"
    result.add "-c"
    if lfShellQuote notin l.flags:
      result.add l.program.cstring
    else:
      var shellCmd: NullessString
      shellCmd.addShellQuoted l.program
      for arg in l.args:
        shellCmd.string.add ' '
        shellCmd.addShellQuoted arg
      result.add shellCmd.cstring
  else:
    result.add l.program.cstring
    for arg in l.args:
      result.add arg.cstring

  result.toCStringArray()

template getExe(l: Launcher): cstring =
  ## Return the executable to be passed to execve()
  if lfShell in l.flags:
    if lfNativeSearch notin l.flags:
      cstring findExe("sh", l.flags)
    else:
      cstring "sh"
  elif lfNativeSearch notin l.flags:
    cstring findExe(l.program.string, l.flags)
  else:
    cstring l.program

proc addStdio(fa: var FileActions, stdio: Stdio, fd: FD) =
  ## Add `fd` configuration to `fa` according to `stdio`.
  case stdio.kind
  of skParent:
    discard "No configuration needed"
  of skClosed:
    posixChk fa.addClose(fd), ErrorLaunch
  else:
    posixChk fa.addDup2(stdio.fd, fd), ErrorLaunch
    if stdio.fd != fd:
      posixChk fa.addClose(stdio.fd), ErrorLaunch # Just in case the file does not have CLOEXEC set

proc apply(stdio: Stdio, fd: FD): bool {.raises: [].} =
  ## Configure `fd` according to `stdio`. Returns `false` on failure.
  ##
  ## This function is async-signal-safe.
  case stdio.kind:
  of skParent:
    discard "No configuration needed"
  of skClosed:
    # Errors can be ignored, since in almost all cases, the fd will still be
    # closed.
    discard posix.close(fd.cint)
  else:
    if not stdio.fd.cint.duplicateTo(fd.cint, inheritable = true):
      return false
    if stdio.fd != fd:
      # Just in case the file does not have CLOEXEC set
      discard posix.close(stdio.fd.cint)

  result = true

template doPosixSpawn() {.dirty.} =
  ## Perform launch() via posix_spawn
  var fileActions = initFileActions()

  fileActions.addStdio(l.stdin, StdinFileno.FD)
  fileActions.addStdio(l.stdout, StdoutFileno.FD)
  fileActions.addStdio(l.stderr, StderrFileno.FD)

  let
    exe = l.getExe()
    argv = l.buildArg()
    envp = l.buildEnv()

  if lfNativeSearch notin l.flags:
    posixChk spawn(cast[ptr Pid](addr result.pid), exe, addr fileActions, nil,
                   argv, envp), ErrorLaunch
  else:
    posixChk spawnp(cast[ptr Pid](addr result.pid), exe, addr fileActions, nil,
                    argv, envp), ErrorLaunch

template doFork() {.dirty.} =
  ## Perform launch() via fork/vfork

  type
    ForkEnv = object
      ## Makeshift closure for the child process preparation proc.
      l: ptr Launcher ## The launcher passed to `launch()`. Do not modify.
      exe: cstring ## The executable to be run.
      argv, envp: ptr UncheckedArray[cstring] ## \
        ## The argument vector and environment to pass to execve().
      err: WritePipe ## The pipe used to relay error codes to the parent.

  proc doExec(fe: ptr ForkEnv): cint {.cdecl, raises: [].} =
    ## Perform preparation steps and execute the target process.
    ##
    ## This procedure must:
    ## - Not modify global program states.
    ## - Not use anything that might raise an exception (not even asserts).
    ## - Not allocate memory under any circumstances.
    ## - Not modify the passed environment.
    ## - Prefer async-signal-safe functions.
    ##
    ## These constraints allow this procedure to be used on vfork() in a
    ## semi-safe manner, and reduce the overhead from the CoW behavior of
    ## fork().
    ##
    ## The return value is not used, only employed for Linux's clone().
    {.push stacktrace: off, linetrace: off.}
    # Stacktrace requires memory allocation.
    template errOn(expr: untyped) =
      ## If `expr` is true, send `errno` via the pipe and quit.
      if expr:
        break errOnBreak

    try:
      block exitOnBreak:
        block errOnBreak:
          errOn not fe.l.stdin.apply StdinFileno.FD
          errOn not fe.l.stdout.apply StdoutFileno.FD
          errOn not fe.l.stderr.apply StderrFileno.FD

          # TODO: employ close_range() and/or closefrom() to speed this up.
          #
          # Parsing /proc/self/fd can be an option on kernels not supporting
          # close_range().
          if lfClearFD in fe.l.flags:
            let maxFD = sysconf(ScOpenMax)
            errOn maxFD == -1
            for fd in 3..maxFD:
              errOn (not ss.setInheritable(fd.cint, false)) and errno != EBADF

          for fd in fe.l.inherits:
            errOn not ss.setInheritable(fd.cint, true)

          if fe.l.workingDir.len != 0:
            errOn chdir(fe.l.workingDir) == -1

          for op in fe.l.popts.forkOps:
            if op != nil:
              errOn not op(l)

          if lfNativeSearch notin fe.l.flags:
            errOn execve(fe.exe, fe.argv, fe.envp) == -1
          else:
            errOn execvpe(fe.exe, fe.argv, fe.envp) == -1

          break exitOnBreak

        let err = errno
        discard write(fe.err.fd.cint, unsafeAddr err, sizeof(err))
    finally:
      exitnow(127) # If execution did not happen, exit with code 127.
    {.pop.}

  when defined(linux):
    var vfStack: seq[byte]
    if lfUnsafeUseVFork in l.flags:
      vfStack.setLen 8 * 1024 * 1024

  var
    env = ForkEnv(
      l: unsafeAddr l,
      exe: l.getExe(),
      argv: l.buildArg(),
      # While it is possible to adjust the environment after fork(), it will
      # cause heap allocation which should be avoided to reduce CoW overhead.
      envp: l.buildEnv()
    )
    (rd, wr) = newPipe()
  env.err = move wr

  template waitExecution() {.dirty.} =
    # TODO: Potentially make this part asynchronous. This is extremely slow
    # when flags like `lfClearFD` is set since we have to close the entire
    # range.
    close wr # Close our end of the write pipe.
    var err: typeof(errno)
    # Retrieve the error code from the pipe.
    let bytes = rd.read cast[ptr array[sizeof(err), byte]](addr err)[]
    if bytes > 0:
      # An error occurred
      if bytes == sizeof(err):
        let errCode = cast[ptr cint](addr err)[]
        raise newOSError(errCode, ErrorLaunch)
      else:
        # The child process will exit with error code 127 anyway, so just
        # ignore if it is not possible to report.
        discard

  template execViaFork() {.dirty.} =
    result.pid = ProcessIdImpl fork()
    if result.pid.Pid == -1:
      posixChk result.pid.Pid, ErrorLaunch
    elif result.pid.Pid != 0:
      # Parent
      waitExecution()
    else:
      # Child
      {.push stacktrace: off, linetrace: off.}
      # Do not use stack trace here, since it modifies a global object which
      # may incur a significant performance hit due to CoW.
      discard doExec(addr env)
      {.pop.}

  when defined(linux):
    if lfUnsafeUseVFork notin l.flags:
      execViaFork()
    else:
      # NOTE: For most architectures, the stack grows downwards, so we
      # assume that here. This may need modification once we deal with
      # architectures whose stack grows the other way around.
      result.pid = ProcessIdImpl clone(
        cast[proc(arg: pointer): cint {.cdecl.}](doExec),
        addr vfStack[high vfStack],
        CloneVFork or CloneVM,
        addr env
      )

      if result.pid.Pid == -1:
        posixChk result.pid.Pid, ErrorLaunch
      else:
        waitExecution()
  else:
    execViaFork()

template launchImpl() {.dirty.} =
  if {lfClearFD, lfUseFork, lfUnsafeUseVFork} * l.flags == {} and
     l.workingDir.len == 0 and
     l.inherits.len == 0 and
     l.popts.forkOps.len == 0:
    doPosixSpawn()
  else:
    when not (defined(bsd) or defined(linux) or defined(macos)):
      if lfClearFD in l.flags:
        # According to POSIX, it could not standardize closefrom() because
        # some systems emulate POSIX characteristics via FDs. This make closing
        # random FDs potentially dangerous on unverified systems.
        raise newException(ValueError, "Closing open FDs is not verified to work on this operating system")
    doFork()
