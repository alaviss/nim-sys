import sys/[continuations, handles, ioqueue]
import sys/private/syscall/posix
import std/strutils

let BigString = "!@#$%^TEST%$#@!\n".repeat(2_000_000)

type
  Wakeable = ref object of RootObj
    future*: Future[void]

proc wakeable(f: sink Future[void]): Wakeable =
  Wakeable(future: f)

proc poll(w: Wakeable): FutureState

proc waker(w: Wakeable): Waker =
  proc wake(ctx: sink RootRef) {.tailcall.} =
    let ctx = Wakeable ctx
    discard poll(ctx)

  ((ref RootObj) w, wake)

proc poll(w: Wakeable): FutureState =
  w[].future = poll(move w[].future, w.waker)
  w[].future.state

proc state(w: Wakeable): FutureState =
  w[].future.state

proc pipe(): tuple[rd: ref Handle[FD], wd: ref Handle[FD]] =
  var fds: array[2, cint]
  doAssert pipe2(fds, O_NONBLOCK or O_CLOEXEC) == 0

  (newHandle(FD fds[0]), newHandle(FD fds[1]))

proc writeAll(fd: sink (ref Handle[FD]), buf: sink string): Future[void] =
  makeFuture:
    var idx = 0
    while idx < buf.len:
      doAssert ioqueue.ready(fd[], Event.Write).wait == Event.Write
      let written = write(fd[].fd.cint, addr buf[idx], buf.len - idx)
      doAssert written > 0
      idx += int written

proc readAll(fd: sink (ref Handle[FD])): Future[string] =
  makeFuture:
    var pages: seq[string]
    while true:
      doAssert ioqueue.ready(fd[], Event.Read).wait == Event.Read
      var buf = newString(4096)
      let readed = read(fd[].fd.cint, addr buf[0], buf.len)

      doAssert readed >= 0
      if readed == 0:
        break

      buf.setLen(readed)
      pages.add buf

    pages.join()

proc run(): Future[void] =
  makeFuture:
    let (rd, wr) = pipe()
    var wrTask = wr.writeAll(BigString)
    var rdTask = rd.readAll()

    while wrTask.state == Pending or rdTask.state == Pending:
      let waker = suspend(Waker, cont):
        initPending(cont)

      if wrTask.state == Pending:
        wrTask = poll(move wrTask, waker)

      if rdTask.state == Pending:
        rdTask = poll(move rdTask, waker)

    wrTask.unwrap()
    doAssert rdTask.unwrap() == BigString

proc main() =
  let fut = wakeable run()
  discard poll(fut)

  while fut.state == Pending:
    ioqueue.tick()

main()
