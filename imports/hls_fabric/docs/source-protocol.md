# Source-protocol inspection and transport

Inspect the actual repetition/noise application before proposing specialized transport or storage. This command produces a source and topology inventory, including unresolved ownership obligations. It does not remove fields, emit hardware or select a backend.

Prepare the pinned compiler dependency with `python3 tools/prepare_compiler.py`, then run:

```sh
bash tools/inspect_phi_protocol.sh /path/to/fresh-output
```

The shell entry point compiles this checkout's default profile and selects its backend/compiler beams explicitly. The escript compiles the six actor modules and two topology modules from the selected compiler sources, obtains complete ordinary source plans, and normalizes the N2/N3/N6 periodic repetition and D3 noise topologies. It invokes `hls_protocol_topology:elaborate/2` to materialize at most 64 actors and `hls_protocol_inventory:inspect/2` to inventory every route, send alternative and callback family. Application callbacks are analyzed, not run; only the topology constructors execute.

Elaboration retains startup, explicit recipients, spatial coordinates, external streams and lane metadata. Unknown families, duplicate ownership or recipients, out-of-range coordinates and excess population reject. Inventory diagnoses missing source plans, unknown producers/consumers, undeclared ports/boundaries, incomplete or duplicate output routing, retained calls and unexpanded topology shapes. Each actor also retains unresolved generation ownership, per-sender ordering, snapshot lifetime, bounded reservation and boundary obligations. A structurally clean report still has `eligible: false`; it is not permission to replace a mailbox or elide payloads.

`summary.json` records populations, diagnostic/obligation counts and exact source/backend identities. Each topology's `.etf` bundle retains its normalized and expanded topology, freshly compiled source artifacts and complete inventory; `.txt` exposes channels and structural diagnostics for review. ETF files are trusted local build data, never network input. The command requires a fresh output directory, exits nonzero on compilation/elaboration errors or structural diagnostics, and preserves any partial output for diagnosis. Unresolved temporal obligations are expected inspection results, not successful qualification.

The inspection call path is:

```text
tools/inspect_phi_protocol.sh
  → tools/inspect_phi_protocol.escript
    → ordinary source compilation + hls_topology:normalize/1
    → hls_protocol_topology:elaborate/2
    → hls_protocol_inventory:inspect/2
    → application bundles + diagnostic summary
```

The lower-level inventory API expects artifacts from the same fresh compilation; the command establishes that relationship. It does not validate arbitrary caller-constructed or stale artifacts. Future lowering must discharge its own source, capacity, ordering and progress obligations before using these bundles. The transport command below consumes freshly compiled sources directly. Actor receipt domains and scheduling remain separate.

`bash tools/test_source_protocol.sh /path/to/fresh-stage` invokes the production command, then checks all four freshly generated application bundles against independent population/coordinate expectations and their complete compiler artifacts. It exercises malformed topology and missing-binding diagnostics and verifies retained file hashes. These are source-analysis regressions, not RTL witnesses, QEC validation or physical measurements.

## Generate publication and capture transport

After preparing the pinned compiler and an XLS tool distribution, write a trusted Erlang configuration containing explicit source files, their compiler options, a topology constructor and an actor population limit. For example, from the repository root:

```erlang
#{sources => [{"test/hls_protocol_capture_fixture.erl", []},
              {"test/hls_protocol_transport_topology.erl", []}],
  topology => {hls_protocol_transport_topology, topology, []},
  actor_limit => 3}.
```

```sh
bash tools/emit_protocol_transport.sh /path/to/xls /path/to/transport.config /path/to/fresh-output
```

This compiles connected DSLX transport through XLS, not an executable actor application. The source list and topology constructor execute as trusted build code. The command selects this checkout's backend/compiler, reloads the declared sources, checks the topology and rejects incomplete routing or unsupported delivery modes. Direct routes and independently buffered fanout are supported; coupled, queued and best-effort fanout reject. Output directories must be fresh. A failure during writing retains partial output.

```text
emit_protocol_transport.sh → emit_protocol_transport.escript
  → hls_protocol_transport:write/2
    → local_actor:compile/2 + topology normalization/elaboration + inventory
    → capture:plan/2 + transactions:plan/2
    → source:plan/3 (projection + codec)
    → inbox:plan/1 → fabric:plan/2
    → local_actor:write/2 (same compiled actors, source functions + manifests)
    → xls_protocol_transport:write/2
      → parametric protocol_transport.x + generated topology composition
      → sv_protocol_ports:write/3 (pin packing only)
  → compile_protocol_transport.py → XLS conversion, optimization and code generation
```

Each internal source/port/schema/destination gets one fixed capture slot. `hls_protocol_capture:plan/2` independently compiles each producer and joins **every** matching send across all entry phases and conditional alternatives. It removes only whole fields that ordinary lowering makes the same literal constant everywhere; startup values, state invariants and partial constants do not authorize whole-field omission. The build checks both source-plan identities agree and rejects any projection needing an additional invariant. `hls_protocol_source:plan/3` is the codec's hardware consumer: it projects the retained ordinary snapshot directly into compact typed link payloads. External outputs retain full 128-bit ordinary frames.

A **source snapshot** is the evaluated values needed for one ordinary entry’s outgoing effects, together with its layout selector. It is not the actor’s entire state, a debugger snapshot or an application readout. For example, if B accepts a send while C stalls, the source retains that batch’s values until C also accepts. A **capture slot** then retains one recipient’s compact message until acquisition and last-read release.

Publication, capture ownership, sender order, selectors, projections and topology composition are DSLX. `protocol_transport.x` uses static payload, destination and slot parameters; heterogeneous slots retain their individual widths. XLS creates the registers. The generated `protocol_fabric` Verilog wrapper only packs named pins into the proc’s input record and unpacks its output record; `sv_protocol_ports` contains no state machine, arbitration or selection. The proc samples every clock with channel-valid/ready tied high. Recipient stalls are fields in that sample, so they cannot stop other recipients or releases. The required XLS schedule is one stage with input/output flops disabled. Changing that schedule changes the clock contract.

The 128-bit **ordinary frame ABI** is separate from these variable storage widths: `axis::Frame` is currently `FrameN<3>`, comprising a 32-bit header and capacity for three 32-bit payload words. The header records the actual payload length. `axis::FrameN<PAYLOAD_WORDS>` already supports other static boundary capacities, but the ordinary actor compiler and its frame analysis currently select three words. Generated DSLX asserts that this ABI agrees with the projection planner. Widening it requires a coordinated compiler/adapter ABI change, not a transport-only knob. Internal capture payloads omit the proved header, padding and whole-field constants.

The generated top is `protocol_fabric`. `transport.etf` retains exact source, projection, slot and wiring plans; `summary.json` records source-plan identities, direct DSLX inputs, XLS executable identities, the schedule and emitted RTL hashes. `dslx/commands.json` retains each compiler invocation and its result. `files.f` lists the RTL files for synthesis or simulation. ETF files are trusted local build data. Lower-level planning APIs expect internally consistent source-bound plans; the public build command establishes those relationships.

| Port group | Owner's obligation |
| --- | --- |
| `source_N_valid/ready/layout/payload` | Offer an evaluated ordinary entry snapshot; hold it stable until accepted. The publisher retains it until all recipients accept their source-ordered subsequences. A subsequent snapshot cannot overtake it. Invalid layouts backpressure and latch `source_N_fault` until reset. |
| `link_N_eligible/take/selected` | Supply source-correct receipt eligibility; acquire the oldest eligible message from this sender. An ineligible postponed message remains pending while later eligible messages may be acquired. Different senders have separate histories. |
| `link_N_available/leased/payloads/release_valid` | Read the exact fixed slot slice from the plan. Acquisition changes FULL to LEASED; release only after the consumer's last read. A repeated send to that class waits for release. |
| `boundary_N_M_valid/ready/data` | Accept an ordinary external frame using ready/valid. Each source/destination has independent backpressure. |
| `reset` | Synchronously cancel all snapshots, pending history and leases in this common clock domain. Also retire corresponding external controller tokens; this is not an independent-device reset protocol. |

Storage is local: one evaluated snapshot per source, one payload and ownership state per typed channel, and a pairwise precedence matrix per logical sender/destination. Each pair accepts at most one arrival and acquisition per clock; slots have independent last-read releases. An S-slot pair requires S² precedence bits plus S pending bits and two ownership bits per slot, in addition to payloads. The pair limit is 255 classes; a source subsequence has at most 256 entries, matching its ordinary eight-bit effect index. These are structural costs, not mapped area or throughput estimates. There is no global payload allocator or cross-sender arrival order.

Generation leaves `eligible: false`: actor controllers, external ingress, generation guards, sufficient capacity and network progress still need integration and admission. In particular, one slot per class can stall an application that requires more buffered messages. This command does not replace existing backends or run FPGA synthesis.

## Source actor functions

The same transport build now writes `actors/actor_N.x` and its `.json` manifest for each distinct source module. These are the ordinary activation functions from the exact compilation used to plan publication. Actor instances share function definitions, not mutable state. `summary.json` binds module names, relative paths, source-plan identities, DSLX hashes and machine/effect layouts. The generated transport RTL remains separate: it does not instantiate these functions or own actor state.

For a single actor without a topology:

```sh
# options.term contains one Erlang compiler-options list, for example [].
bash tools/emit_local_actor.sh source.erl options.term /path/to/fresh/actor.x
```

Generated modules use the ordinary DSLX runtime libraries plus the provider modules listed in `source_imports`. When invoking XLS, supply the compiler/fabric library directories and the application provider directory; Phi actors also need the compiler’s `src/examples/phi_decoder` directory for `phi_field.x`. These outputs do not bundle or compile those libraries.

The command builds the selected checkout, calls `hls_local_actor:compile/2`, then `write/2`; it accepts source and preprocessing options, not a saved plan or selected callbacks. Source errors and retained synchronous calls reject. Both the DSLX output and JSON sidecar must be absent. Failed writes leave partial output for diagnosis.

`local_initial` supplies reset state; `local_pending_at` and `local_observe` inspect it; `local_step_at` executes one ordinary activation; `local_effect` decodes its evaluated batch in source order. The step result contains the next machine, effect payload/layout/count, effect validity, dispatch/directive, phase-boundary and egress-blocked flags. The caller owns the selected mailbox frame, state and publication reservation, commits once, and keeps a batch until its last effect is accepted. These pure functions allocate no clocked storage and provide no scheduler, lease handling or progress admission. Their use by an integrated owner follows separately.

The source-actor regression invokes the public command, verifies source/DSLX and interface bindings, and rejects existing outputs and missing sources. The activation regression checks source arithmetic, guards, phases and projected state with the XLS interpreter/JIT, and lowers scalar reduction and indexed gather fixtures. These are finite semantic witnesses and compilation checks.

```sh
python3 tools/test_local_actor.py /path/to/fresh-actor-stage
bash tools/test_local_execution.sh /path/to/xls /path/to/fresh-activation-stage
```

## Transport checks

```sh
bash tools/test_protocol_codecs.sh /path/to/xls /path/to/fresh-codec-stage
bash tools/test_protocol_transport.sh /path/to/xls /path/to/fresh-transport-stage
```

The connected finite witness compares full reconstructed frames with the ordinary compiler's independently generated entry decoder. It exercises conditional layouts, unaligned and constant fields, independent recipient stalls, sender ordering across ports, postponement, leases and two resets over at most 2,000 cycles. Negative builds reject missing sources/routes, excess population, duplicate sources, unsupported coupled fanout and existing output directories. Real N2/N3/N6 repetition and D3 noise transports are emitted and elaborated; their actor controllers are not simulated by this check. These are finite RTL witnesses and structural checks, not an unbounded progress proof, QEC validation or physical measurement.

## Collection receipts and callbacks

The same `emit_local_actor.sh` command now includes `local_protocol_at` and `local_slow_step_at`. The direct generation path is `hls_local_actor:compile/2` → `hls_local_protocol:ports/1`; the transport command inherits both functions through its existing actor builder. The ordinary `local_step_at` remains available as the complete reference. These are source-derived functions, not an enabled runtime or a hardware-admission decision.

`local_protocol_at` returns `(handled, deferred_completion, private_machine, dispatched, directive)`. It uses the ordinary source contribution extractors and tag, failure and pending-work checks. It either recognizes a collection receipt or leaves the frame to the callback path. A handled non-deferred receipt equals a complete activation with no effects. A final indexed-gather receipt instead captures the last value into **private intermediate state**: retain the selected mailbox head and ignore its placeholder directive. Execute `local_slow_step_at(private_machine, 0, false, effects_reserved, slot)` and use that complete result to commit state/effects and retire or postpone the original head. No other activation may observe or overwrite the intermediate state.

For unhandled work, the slow port omits incoming collection updates. Its caller must intercept every handled receipt and suppress `received` while `local_pending_at` is true. It retains complete-gather, continuation, scalar-completion, entry and failure priority. It returns the same nine result fields as `local_step_at` under that domain. These obligations are also listed in the actor manifest; merely calling the function does not establish them. The transport circuit still has no actor owner that enforces this protocol.

The behavior lives in DSLX templates because `ActorState`, collection types and callback functions belong to each generated actor module. Erlang binds those declarations and reuses the ordinary compiler's callback/failure generators; it does not rewrite emitted program text.

Run `python3 tools/test_local_protocol.py XLS_ROOT FRESH_OUTPUT` with Yosys available after preparing the compiler. The regression invokes the public actor command for plain, scalar-reduction and indexed-gather/continuation fixtures. It checks receipt equality, deferred completion and the slow-port domain for every finite-width input valuation using combinational SAT, including invalid frames and failure states. Deliberately discarded receipts, stale final-gather state and dropped internal work must produce counterexamples. These fixture-specific proofs trust source extraction, XLS and Yosys/ABC/SAT; they do not establish runtime ownership, network progress, arbitrary-program equivalence or physical performance.
