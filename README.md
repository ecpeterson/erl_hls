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
checkout, and finishes by checking the source-adjacent generated DSLX and the
compact Verilog digest manifest declared in `tools/xls_goldens.sh`. Generated
Verilog is compiled and simulated from the staging directory instead of being
checked into the repository; GitHub Actions uploads it with the other
diagnostics when a regression or digest check fails.

After changing the translator or a translated example, refresh the checked-in
artifacts with the same full regression:

```sh
tools/update_xls_goldens.sh
```

The files are copied only after the pinned remote flow and its simulations
complete successfully.

The phi example also includes lowerable phenomenological data- and syndrome-
noise actors. CPU tests wire those actors to a self-periodic phi cell and run
the request/query/measurement pipeline across consecutive decoder steps. A
local CPU deployment also runs the complete noisy distance-three closeout
through the same routed codec, runner, and reducer used by the hardware bridge.
The closed hardware fixture is an Erlang semantic topology plus a separate
physical profile which generates its DSLX wrapper. The routine remote
regression closes a zero-noise distance-one experiment from ERTS through its
generated gateway and Icarus model. The opt-in
`tools/run_phi_memory_demo.sh` command runs the same noisy distance-three
fixture first on ERTS and then through Icarus on the configured remote host.
After the common quiet/empty fence, both paths query every data qubit once in
the configured basis (Z in this fixture), then compare the coordinate-sorted
anticommutation bits and correction witness directly. A complementary-basis
measurement requires a separate reset and run.
See the
[generated phi/noise topology](src/examples/phi_decoder/phi_phenom_topology.md) for its
structure, checks, and current limitations.

The remote host and paths can be overridden with `ERL_HLS_REMOTE_HOST`,
`ERL_HLS_REMOTE_ROOT`, and `ERL_HLS_REMOTE_XLS`.

GitHub Actions runs the same generated-RTL and bridged-EUnit regressions on
Ubuntu using a checksum-pinned XLS release. `tools/prepare_xls_sim.sh` creates
the portable simulation staging directory; `tools/remote_xls_sim.sh` executes
that directory on any Linux host with XLS, Erlang, and Icarus installed. The
same remote runner invokes the XLS interpreter on `hls_debug_framing.x`, `hls_debug_trace.x`, and
`hls_debug_observer.x`, so their `#[test]` functions run in both GitHub Actions
and the UTM flow before the debug procs are lowered to RTL.

The debug subsystem is divided into focused DSLX modules for shared types,
trace storage semantics, passive observation, and response serialization, and
is lowered beside the application. A small passive RTL tap keeps
instrumentation ready signals out of the application datapath. The shared
EUnit scenario queries counters and a bounded frame trace from Erlang,
including trace overflow and drain behavior. The [routed loss regression](docs/debug-protocol.md#diagnosing-generated-applications) diagnoses injected sampling gaps through `hls_debug`, with VPI limited to the public debug transport. Packed application state is not
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

`hls_statem` uses phase-named `Phase(EventType, Content, Data)` callbacks.
Entry and cast clauses have separate fixed result shapes; overloaded Erlang
specifications can preserve the relationship between each event kind and its
result. Its bounded result vocabulary and postponement rules live with the
[`hls_statem` API](src/api/hls_statem.erl). The
[actor-owned reduction design](docs/actor-reductions.md) records the
phase-local reduction actions, canonical CPU/XLS semantics, and constraints on
future optimized placement.

Phase-entry callbacks can use ordinary `case`/`if` branches to select bounded action lists with different lengths, ports, and schemas. Only selected payload expressions contribute values or failures. Shared storage follows the largest alternative, and topology inference checks the union of possible outputs. The [entry contract](docs/entry-outcomes.md) describes source restrictions, reduction opens, and direct/shared commit behavior. Run `bash tools/test_entry_outcomes.sh XLS_ROOT` for BEAM-derived DSLX/JIT and RTL comparisons.

Shared actor-runtime and topology algorithms live in checked DSLX libraries. Generated modules supply actor-specific records, callback outcomes, routing tables, and channel wiring:

- [`mailbox.x`](priv/xls/lib/mailbox.x): mailbox selection, admission reservation, effect-credit collection, and retirement metadata.
- [`frame_transport.x`](priv/xls/lib/frame_transport.x): frame relays and array/grid multiplexers, parameterized by lane counts and channel depth.
- [`frame_queue.x`](priv/xls/lib/frame_queue.x): two-frame source-fragment queues and simultaneous bank pop/push.
- [`scheduler.x`](priv/xls/lib/scheduler.x) and [`arbitration.x`](priv/xls/lib/arbitration.x): actor eligibility and shared round-robin selection.
- [`effect_window.x`](priv/xls/lib/effect_window.x): lookahead ownership arbitration and router-side credit/reservation transitions.

The libraries have direct DSLX tests, run explicitly by `tools/remote_xls_sim.sh`. These cover queue order and capacity, postponement and retirement, scheduling fairness and exclusion, transport backpressure, and the lookahead-credit lifecycle. `tools/prepare_xls_sim.sh` stages all library modules.

Effect-window grants use the arbiter's registered ownership and pending-request snapshot. A received request or release becomes eligible for arbitration in a later activation; ownership remains exclusive until release, with round-robin choice among pending contenders. A router may return an unusable grant and request another reservation in the same activation. Neither input feeds the arbiter's current grant decision. Activation latency depends on the XLS pipeline schedule and backpressure.

Run `bash tools/test_effect_window.sh XLS_ROOT [STAGE]` for the DSLX/JIT and generated-RTL handshake regressions. It requires Icarus Verilog, Yosys, and `timeout`, and covers blocked grants, delayed releases, fairness, reset with outstanding work, and immediate return/re-request clients across four pipeline schedules. `ERL_HLS_YOSYS` selects a Yosys executable; otherwise the scripts use `yosys` on PATH or the bundled FPGA experiment installation. `bash tools/check_rtl_structure.sh TOP OUTPUT_PREFIX RTL...` also checks a generated design directly: it flattens and optimizes behavioral RTL, then rejects structural errors and combinational cycles before technology mapping. The emitted script and logs are saved beside `OUTPUT_PREFIX`. This check does not establish physical timing closure.

## Composable numeric types and DSLX companions

Host packing follows an explicit [numeric conversion contract](docs/numeric-contract.md). Integers must fit their signed or unsigned range; `hls_nums:wrap/2` and `hls_fixed:wrap/2` request modular conversion on both BEAM and XLS. Float packing rounds to finite binary16/32/64 values and rejects overflow to infinity. `hls_type:normalize/2` exposes the canonical host value, and `pack_exact/2` additionally requires preservation of the original Erlang term. Every successful pack must unpack and repack identically. Lists and vectors require exact lengths, generated record packers enforce record shape, and `hls_type:pack/2` checks each provider's binary width. These codec laws are distinct from arithmetic agreement: intermediate widths, rounding schedules, and subnormal handling still matter.

`hls_fixed:signed(Width, FractionBits)` describes a signed fixed-point scalar stored as a scaled integer. Width includes the sign bit and is byte-aligned. Host conversion and packing reject out-of-range values; `saturate/2` clamps explicitly, and `round_ratio/2` rounds integer division to nearest with ties away from zero. Lowered `round_ratio/2` takes a positive static `u32` divisor. [`hls_fixed.x`](priv/xls/lib/hls_fixed.x) implements the parametric arithmetic on the raw signed integers; scaling remains part of the declared type contract.

`hls_vec:vector(ElementType, Size)` describes a fixed-size homogeneous vector with one-based indexing. It packs exactly `Size` elements in the existing array wire order. `dot(AccumulatorType, Left, Right)` widens signed elements before multiplication and addition; every intermediate sum must fit the declared accumulator. It operates on raw integers, so fixed-point products retain their combined fractional scale until explicitly rescaled. [`hls_vec.x`](priv/xls/lib/hls_vec.x) owns the DSLX dot product; array indexing and update use DSLX's native operations.

For example, `hls_vec:vector(hls_fixed:signed(16, 8), 3)` is a three-element Q7.8 vector. The phi example now names its Q15.16 scalar `phi_field:scalar()` and its two-layer vector `phi_field:field()`. The actor calls `phi_field:relax/4` for the coupled update. These types preserve the previous raw values and wire layout, while rejecting malformed lengths and out-of-range packed scalars.

Type providers can export the optional `hls_type` callback `dslx_imports/0`, returning module-name atoms such as `[phi_field]`. The compiler collects declarations from include-expanded remote types and calls, including nested type arguments, and emits sorted, deduplicated companion imports for both `hls_gs` and `hls_statem`. A provider's `print_type/2` and `transpile/3` can then refer to public companion types and functions. The companion files must be on XLS's import path; XLS resolves their transitive imports. The example's [`phi_field.x`](src/examples/phi_decoder/phi_field.x) sits beside its BEAM implementation and is copied into simulation stages. Remote runners transfer the staged DSLX set together.

## Translated record defaults

Both actor forms use a checked compile-time `init([])` value for cold start and hardware reset. Nonzero values belong in the initializer; record defaults remain type-directed zero. Shared schedulers repopulate actor RAM before dispatching startup messages. The [initialization contract](docs/initialization.md) describes the supported source subset, CPU and proxy behavior, and reset tests.

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
