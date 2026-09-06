# `erl_hls`

Compile a bounded subset of Erlang processes into hardware and interoperate
with them from native Erlang processes, through simulation or an FPGA. The
current hardware backend lowers through XLS.

## Tests

Run the Erlang-side unit and CPU-reference tests locally:

```sh
rebar3 eunit
```

Run generated-RTL regressions with the native XLS toolchain, Erlang, and
Icarus Verilog:

```sh
export ERL_HLS_XLS_ROOT="$HOME/xls-v0.0.0-10601-g9f360fc89-darwin-arm64"
tools/xls_sim.sh
```

Set the root to the installed native build on other hosts. The runner requires
`interpreter_main`, `ir_converter_main`, `opt_main`, and `codegen_main`; it
fails before staging if they are unavailable. The flow executes locally.

The flow regenerates DSLX from Erlang, runs XLS interpretation, IR conversion,
optimization and Verilog generation, and exercises cycle-controlled RTL and
ERTS application scenarios through the VPI bridge. Independent application and
debug FIFO pairs carry the two AXI Stream paths. Artifacts remain in
`_build/xls_sim/regsvc`. The final check compares source-adjacent DSLX and the
compact Verilog digest manifest declared in `tools/xls_goldens.sh`; generated
Verilog is retained in the staging directory rather than checked in.

After changing the translator or a translated example, refresh the checked-in
artifacts with the same full regression:

```sh
tools/update_xls_goldens.sh
```

The files are copied only after the native flow and its simulations complete
successfully.

The phi example also includes lowerable phenomenological data- and syndrome-
noise actors. CPU tests wire those actors to a self-periodic phi cell and run
the request/query/measurement pipeline across consecutive decoder steps. A
local CPU deployment also runs the complete noisy distance-three closeout
through the same routed codec, runner, and reducer used by the hardware bridge.
The closed hardware fixture is an Erlang semantic topology plus a separate
physical profile which generates its DSLX wrapper. The routine native
regression closes a zero-noise distance-one experiment from ERTS through its
generated gateway and Icarus model. The opt-in
`ERL_HLS_PHI_NATIVE_ICARUS=1 tools/run_phi_memory_demo.sh` command uses the
configured native XLS root to run the noisy distance-three fixture first on
ERTS and then through native Icarus.
After the common quiet/empty fence, both paths query every data qubit once in
the configured basis (Z in this fixture), then compare the coordinate-sorted
anticommutation bits and correction witness directly. A complementary-basis
measurement requires a separate reset and run.
See the
[generated phi/noise topology](src/examples/phi_decoder/phi_phenom_topology.md) for its
structure, checks, and current limitations.

`ERL_HLS_XLS_ROOT` selects the native compiler installation. Lower-level
`tools/run_xls_sim.sh STAGE XLS_ROOT` also accepts it as its second argument.

GitHub Actions runs the same generated-RTL and bridged-EUnit regressions on
Ubuntu using a checksum-pinned XLS release. `tools/prepare_xls_sim.sh` creates
the portable simulation staging directory; `tools/remote_xls_sim.sh` executes
that directory locally on macOS or Linux with XLS, Erlang, and Icarus installed.
The same stage runner invokes the XLS interpreter on `hls_debug_trace.x` and
`hls_debug_observer.x`, so their `#[test]` functions run in both GitHub Actions
and the native flow before the debug procs are lowered to RTL.

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

The phi memory gateway is wrapped with the same monitor. Its distance-one and
opt-in distance-three bridge scenarios send real routed debug requests and
require populated counter and trace replies after the memory experiment. This
placement observes physical routed application packets; it does not expose
individual actor mailboxes or state.

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

## State-machine callbacks

`hls_statem` uses phase-named `Phase(enter | cast, Content, Data)` callbacks
with `callback_mode() -> [state_functions, state_enter]`. The bounded result
vocabulary and postponement rules are documented in
[`hls_statem`](src/api/hls_statem.erl). The
[actor-owned reduction design](docs/actor-reductions.md) records the planned
phase-local reduction actions and their XLS/RTL constraints.

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
