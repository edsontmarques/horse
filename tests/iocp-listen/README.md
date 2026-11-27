# Listen cycle of the IOCP provider

`tests/src/tests/Tests.Horse.Provider.IOCP.Listen.pas` runs the real IOCP
provider on port `19266` and checks how it starts listening, refuses a busy
port, runs the `Listen` callbacks and listens again. It is part of
`tests/src/IOCPUnitTests.dpr`. Each `Listen` blocks, so every check runs it
on a thread of its own, and counts it as up when its listen callback runs,
after the workers exist. `IocpListenHolder.dpr` is a second process that holds
the port with the IOCP provider until it is killed.

| Check | What passes |
|---|---|
| CA1 busy port | With another socket bound to `INADDR_ANY` on the port, `Listen` fails with the 10048 message. |
| CA1b port held by an IOCP | With `IocpListenHolder` on the port, `Listen` fails with the 10048 or the 10013 message. |
| CA1c exclusive port | With the IOCP listening, a socket with `SO_REUSEADDR` cannot `bind` the port. |
| CA2 message | The messages of CA1 and CA1b are the literal ones, with the port and the code. |
| CA3 listen again, same process | A server answers two keep-alive requests and is stopped with `StopListenGraceful`, the client still connected. A new `Listen` on the port comes up. 10 rounds. |
| CA3b listen again, other process | `IocpListenHolder` answers a client and is killed with `TerminateProcess`. A `Listen` on the port comes up. 10 rounds. |
| CA5 callbacks | `Listen(port, OnListen, OnStop)` runs `OnListen` once, and a request made inside it is served. `OnStop` runs once after the stop. A second `Listen(port, OnListen2)` does not run the first `OnStop`. |
| CA6 clean state | After a `Listen` refused by CA1, freeing the port lets the next `Listen` come up. |
| CA7 Listen while up | A second `Listen` while the server is up, on another port and host, fails with the "já está escutando" message. The server keeps its port, its host and its answers, and only its own `OnStop` runs. |
| CA8 stop with requests arriving (ignored, see below) | Two clients keep sending keep-alive requests while `StopListen` runs on another thread. `StopListen` returns within 30 s, and so does the `Listen`; each round records how long the stop took. 10 rounds. |
| CA7c Listen as soon as Listen returns | The thread of a `Listen` listens again the moment it returns, after a stop slowed down by a keep-alive client. The new server comes up whole and answers. 10 rounds. |
| CA7b Listen right after StopListen | A `Listen` started right after `StopListen`, before the first `Listen` returns, is refused or comes up, and never swaps the `OnStop` of the cycle still ending. 10 rounds. |

Each check starts by asserting that no IOCP is up in the test process and
that the port has no listener.

A stop, and a killed process, end the keep-alive connections with a reset,
which leaves no `TIME_WAIT` (measured on Windows on 2026-11-26). So CA3 and
CA3b also send a `Connection: close` request, which the server closes itself,
leaving its side in `TIME_WAIT`. Before the new `Listen`, CA3 and CA3b check
with `GetTcpTable2` that a server-side connection on the port is still active
or in `TIME_WAIT`. The connection checked is the one the round closed, found by
its client port, so that connections left by an earlier round never satisfy
it. Without
one, they fail on that precondition, because the risk would not have been
exercised, and the message lists the TCP rows of the port.

What Windows answered goes to `iocp-listen-observations.log`, which the script
appends to `run.log` under `Observations:`: the code of CA1b and of CA1c, and
the connections CA3 and CA3b found in their first round, and how many CA7b
calls were refused.

Until IOCP-LISTEN-1:
- the listen socket used `SO_REUSEADDR`, which on Windows lets a second
  socket bind a port another one is listening on, so two servers shared the
  port with no error;
- a failed `bind` said neither the port nor the code;
- the callbacks given to `Listen` were ignored;
- a failed `Listen` left Winsock started and could leave the socket open.

## Windows

```powershell
./tests/iocp-listen/run-iocp-listen.ps1 -Version 19.0
```

`-Version` is the RAD Studio folder (`19.0` is Delphi 10.2 Tokyo). The script
builds `IocpListenHolder` and `IOCPUnitTests` into
`benchmarks/results/iocp-listen-*` and runs the tests there. A failed check is
reported by DUnitX, and the script then stops with an error.

To run chosen checks, each in a process of its own, name the methods of
`TTestHorseProviderIOCPListen`. Each run has to find exactly one test, or it
fails as `NOT ISOLATED`; one that does not end in 120 s (`-TestTimeout`) is killed and fails as
`TIMEOUT`, and the next ones still run:

```powershell
./tests/iocp-listen/run-iocp-listen.ps1 -Version 19.0 -Tests ListenAgainAsSoonAsListenReturnsComesUpWhole,ListenWhileListeningIsRefusedAndKeepsTheServer
```

## Negative control

The tests use only the public API of the provider, so the previous source
needs no seam. Export the `src` of the commit before IOCP-LISTEN-1 (`aad6568`)
into the ignored results folder. `git archive` only reads the repository, so it
also works from a machine where the checkout is a shared folder without git:

```sh
mkdir -p benchmarks/results/horse-before-aad6568
git archive aad6568 src | tar -x -C benchmarks/results/horse-before-aad6568
```

Against that source some checks hang, so each one runs in a process of its
own:

```powershell
./tests/iocp-listen/run-iocp-listen.ps1 -Version 19.0 -HorseSource .\benchmarks\results\horse-before-aad6568\src -Tests BusyPortIsRefusedWithPortAndCode,PortHeldByAnotherIocpIsRefused,ReuseAddressSocketCannotShareTheListeningPort,ListenRunsItsOwnCallbacksOnce,RefusedListenLeavesThePortFree,ListenAgainAsSoonAsListenReturnsComesUpWhole,ListenRightAfterStopRunsEachStopCallbackOnce,ListenWhileListeningIsRefusedAndKeepsTheServer
```

The holder is built from the same source. Against that source:
- CA1b, CA1c and CA7 fail, because the second socket or server comes up on the
  port;
- CA1 fails only on the message (CA2): Windows already refused that `bind`;
- CA5 fails because no callback runs;
- CA7c and CA7b fail, or hang until the script kills them, because no
  callback runs.

### Against the first version of IOCP-LISTEN-1

The listen cycle (one cycle at a time, the start and the release under one
lock, the Listen thread waiting for the release to end) came after the first
version of the fix, which was never committed. Its negative control was run
once, before the commit, against the `src` of `aad6568` with the
`src/Horse.Provider.IOCP.pas` of that first version, and is recorded in the
spec (`webtools-sse-i-iocp-listen`), with the command it used:

```powershell
./tests/iocp-listen/run-iocp-listen.ps1 -Version 19.0 -HorseSource .\benchmarks\results\horse-slice-v1\src -Tests ListenAgainAsSoonAsListenReturnsComesUpWhole,ListenRightAfterStopRunsEachStopCallbackOnce,ListenWhileListeningIsRefusedAndKeepsTheServer
```

There, CA7c fails because the release of the first cycle runs over the second,
or hangs until the script kills it after 120 s and records `TIMEOUT`; and CA7
fails because the second `Listen`, on another port, comes up. CA7b
depends on when the first `Listen` thread wakes, and its result is recorded,
not predicted.

CA6 has no negative control: the previous source already left the port free
after that refusal. CA3 and CA3b have none either. They measure the risk that
`SO_EXCLUSIVEADDRUSE` brings to a quick restart.

CA6 covers a refusal at `bind`. A failure after the socket opens (`AcceptEx`,
the completion port) releases the same resources but has no check, because
Windows gives no way to make it fail on demand.

### CA8

CA8 is ignored in the suite. A stop with keep-alive requests arriving can wait
forever for a worker that never leaves its loop, and so could `aad6568`
(measured on Windows on 2026-11-26: 3 of 3 runs against `aad6568` and 2 of 3
against IOCP-LISTEN-1 hung in some round). It is the bench of its own slice
(spec `webtools-sse-s-iocp-stop-under-load`), which removes the `Ignore`.
Without the `Ignore`, run it with
`-Tests StopWithRequestsArrivingReturns -TestTimeout 400`.

These tests need a licensed Delphi, so the public FPC job does not run them.
