import std/macros

type
  ContinuationFn*[Ctx, R] = proc (ctx: sink Ctx): R {.tailcall.}
  ContinuationValFn*[Ctx, T, R] = proc (val: sink T, ctx: sink Ctx): R {.tailcall.}

  Continuation*[Ctx, R] = tuple
    ctx: Ctx
    fn: ContinuationFn[Ctx, R]

  ContinuationVal*[Ctx, T, R] = tuple
    ctx: Ctx
    fn: ContinuationValFn[Ctx, T, R]

  GenericContinuation*[R] = Continuation[ref RootObj, R]
  GenericContinuationVal*[T, R] = ContinuationVal[ref RootObj, T, R]

  Waker* = GenericContinuation[void]
  PendingContinuation*[T] = GenericContinuationVal[Waker, Future[T]]

  FutureState* {.pure.} = enum
    Pending
    Error
    Resolved

  Future*[T] {.requiresInit.} = object
    case state: FutureState
    of Pending:
      continuation: PendingContinuation[T]
    of Error:
      error: ref Exception
    of Resolved:
      value: T

  AnyObj[T] = object of RootObj
    value: T


proc drop[T](_: sink T) = discard

proc newGenericContinuation*(continuation: sink GenericContinuation): GenericContinuation =
  continuation

proc newGenericContinuation*[Ctx, R](continuation: sink Continuation[Ctx, R]): GenericContinuation[R] =
  type CtxType = AnyObj[Continuation[Ctx, R]]
  proc fn(ctx: sink ref RootObj): R {.tailcall.} =
    let
      continuation = (ref CtxType) ctx
      (ctx, fn) = move continuation[].value

    fn(ctx)

  let ctx = (ref RootObj) (ref CtxType)(value: continuation)
  (ctx, fn)

proc newGenericContinuation*[Ctx, T, R](continuation: sink ContinuationVal[Ctx, T, R]): GenericContinuationVal[T, R] =
  type CtxType = AnyObj[ContinuationVal[Ctx, T, R]]

  proc fn(val: sink T, ctx: sink RootRef): R {.tailcall.} =
    let
      continuation = (ref CtxType) ctx
      (ctx, fn) = move continuation[].value

    fn(val, ctx)

  let ctx = (ref RootObj) (ref CtxType)(value: continuation)
  (ctx, fn)

proc initResolved*[T](value: sink T): Future[T] {.inline.} =
  Future[T](state: FutureState.Resolved, value: value)

proc initResolved*(): Future[void] {.inline.} =
  Future[void](state: FutureState.Resolved)

proc initError*(T: typedesc, error: ref Exception): Future[T] {.inline.} =
  Future[T](state: FutureState.Error, error: error)

proc initPending*[Ctx, T](continuation: sink ContinuationVal[Ctx, Waker, Future[T]]): Future[T] {.inline, raises: [].} =
  Future[T](state: FutureState.Pending, continuation: newGenericContinuation(continuation))

template makeFuture*[T](body: T): Future[T] =
  try:
    when T isnot void:
      initResolved:
        body
    else:
      body
      initResolved()
  except CatchableError as e:
    initError(typedesc[T], e)

func state*(f: Future): FutureState {.inline.} =
  f.state

func unwrap*[T](f: sink Future[T]): T {.inline.} =
  case f.state
  of Resolved:
    when T isnot void:
      move f.value
  of Error:
    raise move(f.error)
  of Pending:
    unreachable("Future is pending")

proc poll*[T](f: sink Future[T], waker: sink Waker): Future[T] {.tailcall.} =
  if f.state == Pending:
    let (ctx, fn) = move f.continuation
    fn(waker, ctx)
  else:
    f

template wait*[T](f: Future[T]): T =
  var future = f
  while future.state == Pending:
    let waker = suspend(Waker, continuation):
      initPending(continuation)
    future = poll(future, waker)

  future.unwrap
