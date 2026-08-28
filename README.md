# `erl_xls`

Translate (certain) Erlang processes into XLS processes.  Interoperate them through simulation or through FPGA with native Erlang processes.

## Tests

Run the Erlang-side unit and CPU-reference tests locally:

```sh
rebar3 eunit
```

The generated-RTL regression uses the Linux UTM instance because XLS is not
available on macOS:

```sh
tools/xls_sim.sh
```

This regenerates `regsvc.x` from the Erlang source, copies only the required
inputs into `/home/ecpeterson/erl_xls-build/regsvc` on `192.168.64.7`, and runs
XLS IR conversion, optimization, and Verilog generation there. It then runs a
cycle-controlled two-process SystemVerilog routing scenario and the EUnit
application scenario through a VPI bridge. Independent application and debug
FIFO pairs carry the two physical AXI Stream paths. The runner does not use or
modify the VM's existing `~/erl_xls` checkout.

The remote host and paths can be overridden with `ERL_XLS_REMOTE_HOST`,
`ERL_XLS_REMOTE_ROOT`, and `ERL_XLS_REMOTE_XLS`.

GitHub Actions runs the same generated-RTL and bridged-EUnit regressions on
Ubuntu using a checksum-pinned XLS release. `tools/prepare_xls_sim.sh` creates
the portable simulation staging directory; `tools/remote_xls_sim.sh` executes
that directory on any Linux host with XLS, Erlang, and Icarus installed. The
same remote runner invokes the XLS interpreter on `xls_debug_trace.x` and
`xls_debug_observer.x`, so their `#[test]` functions run in both GitHub Actions
and the UTM flow before the debug procs are lowered to RTL.

The debug subsystem is divided into focused XLS modules for shared types,
trace storage semantics, passive observation, and response serialization, and
is lowered beside the application. A small passive RTL tap keeps
instrumentation ready signals out of the application datapath. The shared
EUnit scenario queries counters and a bounded frame trace from Erlang,
including trace overflow and drain behavior. Packed application state is not
mirrored into the passive debug path. The SystemVerilog scenario additionally
proves that routed debug access remains available while application output is
backpressured and that the reserved former state-query tag is rejected. See the
[debug protocol](docs/debug-protocol.md) for that interface.

The routed simulation hosts two independent `regsvc` instances behind each
shared stream. A 32-bit source/destination envelope precedes the existing
application or debug frame, and arbitration retains a selected endpoint through
`TLAST`. On the Erlang side, one `xls_fabric` process owns each physical stream
while distinct `xls_gs` proxy PIDs retain the ordinary `gen_server`-style API.
The regression checks isolated process state, concurrent calls, complete-frame
arbitration under backpressure, and debug access while application output is
blocked. Fabric endpoint addresses are transport identifiers, not Erlang PIDs.
The topology-specific Verilog composition used by Icarus is kept under
`test/rtl`; a production Vivado design can package the router and endpoint
boundaries independently and connect them in its block design.

## Translated record defaults

Every field in a private-state or wire record must have a type-directed zero
default:

```erlang
-record(state, {
    registers = xls_type:zero() :: xls_lists:list(xls_nums:u32(), 16)
}).
```

The `xls_pack` parse transform expands this marker into the corresponding
Erlang value using the field's type annotation. The XLS compiler uses the same
annotation to generate `zero!`, avoiding a duplicated type descriptor and
ensuring that CPU and hardware instances begin with the same record values.
