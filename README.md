# `erl_hls`

Compile a bounded subset of Erlang processes into hardware and interoperate
with them from native Erlang processes, through simulation or an FPGA. The
current hardware backend lowers through XLS.

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

This regenerates the translated DSLX from the Erlang sources, copies only the
required inputs into `/home/ecpeterson/erl_hls-build/regsvc` on
`192.168.64.7`, and runs XLS IR conversion, optimization, and Verilog
generation there. It then runs a cycle-controlled two-process SystemVerilog
routing scenario and the EUnit application scenario through a VPI bridge.
Independent application and debug FIFO pairs carry the two physical AXI Stream
paths. The runner does not use or modify the VM's existing `~/erl_hls`
checkout, and finishes by checking all four source-adjacent DSLX and RTL
artifact pairs plus the generated topology DSLX golden declared in
`tools/xls_goldens.sh`.

After changing the translator or a translated example, refresh the checked-in
artifacts with the same full regression:

```sh
tools/update_xls_goldens.sh
```

The files are copied only after the pinned remote flow and its simulations
complete successfully.

The phi example also includes lowerable phenomenological data- and syndrome-
noise actors. CPU tests wire those actors to a self-periodic phi cell and run
the request/query/measurement pipeline across consecutive decoder steps. The
closed hardware fixture is now an Erlang semantic topology plus a separate
physical profile which generates its DSLX wrapper. See the
[generated phi/noise topology](src/examples/phi_decoder/phi_phenom_topology.md) for its
structure, checks, and current limitations.

The remote host and paths can be overridden with `ERL_HLS_REMOTE_HOST`,
`ERL_HLS_REMOTE_ROOT`, and `ERL_HLS_REMOTE_XLS`.

GitHub Actions runs the same generated-RTL and bridged-EUnit regressions on
Ubuntu using a checksum-pinned XLS release. `tools/prepare_xls_sim.sh` creates
the portable simulation staging directory; `tools/remote_xls_sim.sh` executes
that directory on any Linux host with XLS, Erlang, and Icarus installed. The
same remote runner invokes the XLS interpreter on `hls_debug_trace.x` and
`hls_debug_observer.x`, so their `#[test]` functions run in both GitHub Actions
and the UTM flow before the debug procs are lowered to RTL.

The debug subsystem is divided into focused DSLX modules for shared types,
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
`TLAST`. On the Erlang side, one `hls_fabric` process owns each physical stream
while distinct `hls_gs` proxy PIDs retain the ordinary `gen_server`-style API.
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
    registers = hls_type:zero() :: hls_lists:list(hls_nums:u32(), 16)
}).
```

The `hls_pack` parse transform expands this marker into the corresponding
Erlang value using the field's type annotation. The XLS compiler uses the same
annotation to generate `zero!`, avoiding a duplicated type descriptor and
ensuring that CPU and hardware instances begin with the same record values.

## Wire tags

An actor may split its wire-record declaration across repeated
`-hls_tags([...])` attributes, including attributes contributed by header
files. The compiler concatenates the blocks in include-expanded source order;
each tag must be a unique atom, and an actor may declare at most 253 of them.
Error and actor-data tags occupy values 1 and 2, and public record tags begin
at 3.

The ordering is part of the wire ABI. Appending a block preserves existing
values, but prepending a block or moving an include can renumber every tag
after it. A shared protocol header may therefore own both its record schemas
and their tag block, provided every independently lowered participant includes
it after the same preceding tag sequence.
