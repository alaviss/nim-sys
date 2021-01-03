import pkg/testes
import sys/pipes

testes:
  let p = initPipe()
  let ap = initAsyncPipe()
