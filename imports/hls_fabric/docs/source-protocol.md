# Source-protocol inspection and transport

Inspect the actual repetition/noise application before proposing specialized transport or storage. This command produces a source and topology inventory, including unresolved ownership obligations. It does not remove fields, emit hardware or select a backend.

Build the pinned compiler dependency with `rebar3 compile`, then run:

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
emit_protocol_transport.sh → hls-fabric emit --kind transport
  → hls_source_build:write/3 → hls_protocol_transport:write/2
    → transport:emit/1
      → transport:prepare/1
        → local_actor:compile/2 + topology normalization/elaboration + inventory
        → capture:plan/2 + transactions:plan/2 → source:plan/3
        → inbox:plan/1 → fabric:plan/2
      → transport:plan/2 (placement, arithmetic and receiver artifacts)
      → local_actor:emit/2 (same compiled actors and receivers)
      → xls_protocol_transport:emit/1 (DSLX composition + mechanical pin adapter)
    → hls_generated_files:write/2 (persist the complete generated bundle)
  → compile_source_build.py → XLS conversion, optimization and code generation
```

Each internal source/port/schema/destination gets one fixed capture slot. The build lowers each distinct actor module once into an opaque `xls_actor_program`; inventory, transaction planning, capture analysis and actor emission share that unchanged source snapshot. `hls_protocol_capture:plan/2` accepts these programs and joins **every** matching send across all entry phases and conditional alternatives. It removes only whole fields that ordinary lowering makes the same literal constant everywhere; startup values, state invariants and partial constants do not authorize whole-field omission. There is no constructor from supplied specs or selected alternatives. Changing source requires a new preparation; existing prepared programs remain snapshots and do not reread files. The build rejects any projection needing an additional invariant. `hls_protocol_source:plan/3` is the codec's hardware consumer: it projects the retained ordinary snapshot directly into compact typed link payloads. External outputs retain full 128-bit ordinary frames.

A **source snapshot** is the evaluated values needed for one ordinary entry’s outgoing effects, together with its layout selector. It is not the actor’s entire state, a debugger snapshot or an application readout. For example, if B accepts a send while C stalls, the source retains that batch’s values until C also accepts. A **capture slot** then retains one recipient’s compact message until acquisition and last-read release.

Publication, capture ownership, sender order, selectors, projections and topology composition are DSLX. `protocol_transport.x` uses static payload, destination and slot parameters; heterogeneous slots retain their individual widths. XLS creates the registers. The generated `protocol_fabric` Verilog wrapper only packs named pins into the proc’s input record and unpacks its output record; `sv_protocol_ports` contains no state machine, arbitration or selection. The proc samples every clock with channel-valid/ready tied high. Recipient stalls are fields in that sample, so they cannot stop other recipients or releases. The required XLS schedule is one stage with input/output flops disabled. Changing that schedule changes the clock contract.

The 128-bit **ordinary frame ABI** is separate from these variable storage widths: `axis::Frame` is currently `FrameN<3>`, comprising a 32-bit header and capacity for three 32-bit payload words. The header records the actual payload length. `axis::FrameN<PAYLOAD_WORDS>` already supports other static boundary capacities, but the ordinary actor compiler and its frame analysis currently select three words. Generated DSLX asserts that this ABI agrees with the projection planner. Widening it requires a coordinated compiler/adapter ABI change, not a transport-only knob. Internal capture payloads omit the proved header, padding and whole-field constants.

The generated top is `protocol_fabric`. `transport.etf` retains exact source, projection, slot and wiring plans; `summary.json` records source-plan identities and direct DSLX inputs. `source-build.json` packages the source inputs and required schedule; `compiled.json` records XLS executable identities, commands and emitted RTL hashes. `dslx/commands.json` retains each compiler invocation and its result. `files.f` lists the RTL files for synthesis or simulation. ETF files are trusted local build data. Lower-level planning APIs expect internally consistent source-bound plans; the public build command establishes those relationships.

| Port group | Owner's obligation |
| --- | --- |
| `source_N_valid/ready/layout/payload` | Offer an evaluated ordinary entry snapshot; hold it stable until accepted. The publisher retains it until all recipients accept their source-ordered subsequences. A subsequent snapshot cannot overtake it. Invalid layouts backpressure and latch `source_N_fault` until reset. |
| `link_N_eligible/take/selected` | Supply source-correct receipt eligibility; acquire the oldest eligible message from this sender. An ineligible postponed message remains pending while later eligible messages may be acquired. Different senders have separate histories. |
| `link_N_available/leased/payloads/release_valid` | Read the exact fixed slot slice from the plan. Acquisition changes FULL to LEASED; release only after the consumer's last read. A repeated send to that class waits for release. |
| `boundary_N_M_valid/ready/data` | Accept an ordinary external frame using ready/valid. Each source/destination has independent backpressure. |
| `reset` | Synchronously cancel all snapshots, pending history and leases in this common clock domain. Also retire corresponding external controller tokens; this is not an independent-device reset protocol. |

Storage is local: one evaluated snapshot per source, one payload and ownership state per typed channel, and a pairwise precedence matrix per logical sender/destination. Each pair accepts at most one arrival and acquisition per clock; slots have independent last-read releases. An S-slot pair requires S² precedence bits plus S pending bits and two ownership bits per slot, in addition to payloads. The pair limit is 255 classes; a source subsequence has at most 256 entries, matching its ordinary eight-bit effect index. These are structural costs, not mapped area or throughput estimates. There is no global payload allocator or cross-sender arrival order.

Transport generation leaves `eligible: false`: its source and capture ports need owners, and external ingress, generation guards, sufficient capacity and network progress need integration and admission. The network command below connects ordinary owners for source-initialized topologies. In particular, one slot per class can stall an application that requires more buffered messages. This command does not replace existing backends or run FPGA synthesis.

## Source actor functions

The same transport build now writes `actors/actor_N.x` and its `.json` manifest for each distinct source module. These are the ordinary activation functions from the exact compilation used to plan publication. Actor instances share function definitions, not mutable state. `summary.json` binds module names, relative paths, source-plan identities, DSLX hashes and machine/effect layouts. The generated transport RTL remains separate: it does not instantiate these functions or own actor state.

For a single actor without a topology:

```sh
# options.term contains one Erlang compiler-options list, for example [].
bash tools/emit_local_actor.sh source.erl options.term /path/to/fresh/actor.x
```

Generated modules use the ordinary DSLX runtime libraries plus the provider modules listed in `source_imports`. When invoking XLS, supply the compiler/fabric library directories and the application provider directory; Phi actors also need the compiler’s `src/examples/phi_decoder` directory for `phi_field.x`. These outputs do not bundle or compile those libraries.

The command builds the selected checkout, calls `hls_local_actor:compile/2`, then `write/2`; it accepts source and preprocessing options, not a saved plan or selected callbacks. Source errors and retained synchronous calls reject. Both the DSLX output and JSON sidecar must be absent. Failed writes leave partial output for diagnosis.

`local_initial` supplies reset state; `local_pending_at` and `local_observe` inspect it; `local_step_at` executes one ordinary activation; `local_effect` decodes its evaluated batch in source order. The `LocalStepResult` struct names the next `machine`, `effect_payload`, `effect_layout`, `effect_count`, `effects_valid`, `dispatched`, `directive`, `phase_boundary` and `egress_blocked`. `LocalEffect` names the decoded `port` and `frame`; `LocalObservation` names `initial_machine`, `pending` and `failure`. `LocalCycleResult` groups `observation`, `step` and `effect`; the decoded effect belongs to the supplied outbox batch, independently of the new step. The caller owns the selected mailbox frame, state and publication reservation, commits once, and keeps a batch until its last effect is accepted. These pure functions allocate no clocked storage and provide no scheduler, lease handling or progress admission. The single-actor clock owner below enforces action and publication ownership; network integration remains separate.

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

The same `emit_local_actor.sh` command now includes `local_protocol_at` and `local_slow_step_at`. The direct generation path is `hls_local_actor:compile/2` → `hls_local_protocol:ports/1`; the transport command inherits both functions through its existing actor builder. The ordinary `local_step_at` remains available as the complete reference. These source-derived functions also feed the clocked owner below; emission does not select a backend or admit a network.

`local_protocol_at` returns a `LocalProtocolResult` struct with named `handled`, `deferred_completion`, `private_machine`, `dispatched` and `directive` fields. It uses the ordinary source contribution extractors and tag, failure and pending-work checks. It either recognizes a collection receipt or leaves the frame to the callback path. A handled non-deferred receipt equals a complete activation with no effects. A final indexed-gather receipt instead captures the last value into **private intermediate state**: retain the selected mailbox head and ignore its placeholder directive. Execute `local_slow_step_at(private_machine, 0, false, effects_reserved, slot)` and use that complete result to commit state/effects and retire or postpone the original head. No other activation may observe or overwrite the intermediate state.

For unhandled work, the slow port omits incoming collection updates. Its caller must intercept every handled receipt and suppress `received` while `local_pending_at` is true. It retains complete-gather, continuation, scalar-completion, entry and failure priority. It returns the same `LocalStepResult` as `local_step_at` under that domain. These obligations are also listed in the actor manifest; merely calling the function does not establish them. The transport circuit still has no actor owner that enforces this protocol.

The behavior lives in DSLX templates because `ActorState`, collection types and callback functions belong to each generated actor module. Erlang binds those declarations and reuses the ordinary compiler's callback/failure generators; it does not rewrite emitted program text.

`local_slow_step_at` directly composes two exported ports: `local_action_at(raw, frame, received, slot)` returns a `LocalAction` struct with named `private_machine`, `dispatched`, `directive` and `phase_boundary` fields, and `local_enter_at(action, effects_reserved, slot)` evaluates entry and returns `LocalStepResult`. Both are emitted by the existing actor and transport commands. The receipt/pending-work domain above still applies; this split adds no scheduling policy.

A caller separating those evaluations must retain **all four action fields**, the same actor slot and the selected mailbox head. The action is private intermediate state, not a committed actor state. Reserve publication storage before accepting effects. If `egress_blocked` is true, retain the action and retry only `local_enter_at`; do not redispatch, retire the head or allow another activation to overwrite it. Payload fields are inactive unless `effects_valid` is true. The current slow path calls both ports immediately; these ports add no registers or owner and make no timing claim.

Run `python3 tools/test_local_protocol.py XLS_ROOT FRESH_OUTPUT` with Yosys available after preparing the compiler. The regression invokes the public actor command for plain, scalar-reduction and indexed-gather/continuation fixtures, then imports each emitted module to exercise its public types and functions across the file boundary. It checks receipt equality, deferred completion and the slow-port domain for every finite-width input valuation using combinational SAT, including invalid frames and failure states. It also checks that blocked publication preserves the action machine and that replay with reserved storage matches the ordinary result. Deliberately discarded receipts, stale final-gather/action state, lost action disposition and dropped internal work must produce counterexamples. These fixture-specific proofs trust source extraction, XLS and Yosys/ABC/SAT; they do not establish runtime ownership, network progress, arbitrary-program equivalence or physical performance.

## Compile a clocked source actor

The actor builder also emits `local_owner_clock`, whose direct call path is `local_owner_tick` → receipt interception or `local_action_at` → registered action → `local_enter_at`. `hls_local_actor:compile/2` appends this DSLX owner to the same ordinary source compilation; no handwritten Verilog controller implements its behavior.

```sh
bash tools/emit_local_actor.sh source.erl options.term /path/to/fresh/actor.x
python3 tools/compile_local_actor.py /path/to/xls /path/to/fresh/actor.x /path/to/fresh/owner
```

The second command checks the emitted DSLX hash and compiles the proc into `owner/actor.v`, with top module `local_actor`. `commands.json` retains tool invocations and output hashes; `owner.json` retains the actor manifest and schedule. Existing output directories reject and failures retain diagnostics. The source artifact and compiler libraries are trusted build inputs. Add application provider directories with `--dslx-path DIR` when needed.

The core samples packed `_commands` (`LocalOwnerInputs`) and emits `_observations` (`LocalOwnerOutputs`) in their declared DSLX field order. Tie `_commands_vld` and `_observations_rdy` high, and connect the active-high reset both to the core's `reset` and to the command record's `reset`. The command fixes one pipeline stage and disables input/output flops. After reset, one startup clock installs the ordinary source initialization result with all handshakes suppressed; provider initializers need not be DSLX compile-time constants. Handshakes describe the edge about to commit; adding stalls to the XLS channels or changing the schedule invalidates this contract.

| Input/output | Contract |
| --- | --- |
| `received`, `frame`, `slot`, `input_ready` | Offer one already-selected mailbox head. On acceptance, reserve that head until `head_done` or reset; keep the actor's instance slot fixed. The owner stores the resulting action rather than another frame copy. |
| `head_done`, `dispatched`, `directive` | End that reservation. Apply consume/postpone only when `dispatched`; otherwise leave the message in its mailbox. A failed source can leave a message unconsumed. |
| `phase_boundary` | Wake postponed messages on a committed boundary, including boundaries reached by internal work. Mailbox selection and per-sender ordering remain the enclosing runtime's responsibility. |
| `output_valid`, `effect`, `output_ready` | Accept one ordinary port/frame pair per clock in source order. Both remain stable while stalled. The owner retains one complete immutable publication batch. |
| `failure` | Observe the committed source failure code before this edge. Failure stops new actions but permits previously committed output to drain. Reset cancels local action/output ownership; the enclosing runtime must also cancel its mailbox reservation. |

Handled receipts commit without reserving another batch and can overlap draining prior output. A final gather receipt instead supplies private state to completion and holds its original head. All other actions execute once and register the complete `LocalAction`; entry retries that value until publication room exists. No new head or internal action can overwrite it. The committed raw machine changes only at completion. Outbox reservation uses old state, so its last-drain edge does not simultaneously admit a new publication batch.

This baseline retains at most one action and one publication batch: `2*M + P + 63` declared state bits (including the startup flag) for an M-bit machine and P-bit payload, before XLS optimization. One clock can update one actor state/action and advance one output index; there is no shared state allocator or additional mailbox. This is a structural storage bound, not a mapped-area, throughput or native-timing claim. The transport command compiles its separate proc; the receiver below supplies mailbox selection and the network command connects complete batches. Declared startup records use the receiver below; ingress, capacity and progress admission remain separate.

`python3 tools/test_local_owner.py XLS_ROOT FRESH_OUTPUT` compares each completed transaction with the original unsplit executor for plain, two-effect-batch, scalar-reduction and indexed-gather/continuation fixtures, including publication stalls, postponement, failure and reset positions. The whole-test XLS JIT executes the assertions, and all four clocked owners are compiled and simulated against independent frame/retirement scoreboards. These are finite witnesses, not an arbitrary-program refinement or progress theorem.

## Connect sender-local captures to an actor

The same transport build command now emits `actors/receiver_I.x` for each elaborated actor, listed in `summary.json` under `receivers`. The direct path is `hls_protocol_transport:write/2` → `hls_protocol_transport:emit/1` → `hls_protocol_inbox:attach/5` → `hls_local_actor:emit/2`. Each receiver includes the ordinary actor owner and source-derived codecs for its exact incoming capture links. Compile a receiver with the existing command:

```sh
python3 tools/compile_local_actor.py XLS_ROOT BUILD/actors/receiver_I.x FRESH_RTL_OUTPUT
```

Its manifest selects `local_inbox_clock`. The one-stage schedule, permanently enabled XLS channels and shared active-high reset contract are the same as for the ordinary actor owner. One masked startup clock installs source initialization. These are standalone receiver modules with ordinary effect outputs. The network command below instead transfers their complete outbox batches to publishers; external ingress, capacity and progress admission remain separate. The transport summary therefore continues to report `actor_runtime: false` and `eligible: false`.

`LocalInboxInputs` lists `reset`, `output_ready`, optional `host_valid`/`host_frame`, then each incoming link's `selected`, `available` and packed `payloads`. Wire these to that exact transport instance. `LocalInboxOutputs` groups four masks and the existing `LocalOwnerOutputs` under `owner`. Masks follow the manifest's `inbox.slots` order; each row identifies its link, capture slot, payload slice and destination-frame codec.

| Output | Connection and meaning |
| --- | --- |
| `eligible` | Split by link and drive its eligibility input. It depends only on registered actor/reservation/postponement state, so transport selection cannot feed back combinationally into eligibility. |
| `accepted` | Records reservation of a pending head. This is an observation, **not** a transport `take`. |
| `take` | OR the bits for each link into its `take` input. Asserted only when that selected source dispatch commits with `consume`; postponed messages remain pending. |
| `release` | Split by link into `release_valid`. This is `take` delayed by one clock: the capture becomes leased at consume, then frees after the final read. |
| `owner` | Ordinary ordered effect/ready handshake and source status. Its `head_done` ends the local reservation; the masks already apply the source disposition. |

Each pair supplies its oldest eligible pending slot. A circular selector chooses among those requests without inventing cross-sender arrival order. It advances only on acceptance. The saved identity remains the pair's only eligible slot through publication stalls, so later arrivals cannot replace it. A postponed head becomes ineligible until a source phase boundary, which wakes all postponed heads. Source failure stops new selection; reset cancels actor, reservation, postponement and delayed release together with the transport. Pending payloads must stay stable, and the transport must implement its declared capture/order contract; these are internal connected interfaces, not arbitrary external inputs.

The added state is `3*N + max(1, ceil(log2(N))) + 1` bits for postponed, reserved and delayed-release masks, cursor and startup flag, plus the existing `LocalOwnerState`. No frame or payload copy is added. There is one selected dispatch per actor per clock and no shared allocator. `N` is the total number of incoming capture, declared startup and optional host slots, limited to 256; zero-input actors use one tied-unavailable dummy slot. The startup consumed mask described below adds one bit per declared record. This is a structural bound, not a native area or timing result.

`python3 tools/test_protocol_inbox.py XLS_ROOT FRESH_OUTPUT` connects real generated transport and receiver RTL to independent sender-age, disposition and source-value scoreboards. Its finite schedule covers early postponement, wakeup, repeated sends, publication stalls, delayed release and reset during ownership, followed by two complete incarnations; early-consume and undelayed-release wiring controls must fail its independent scoreboard. Combinational SAT checks circular priority for all request masks and legal cursors at 1, 3 and 8 slots; an ignored-cursor control must fail. Those checks trust XLS lowering and Yosys/ABC/SAT and establish selection only, not sequential refinement or network progress. Local XC7 selector counts are capacity screens, not Vivado forecasts. The existing transport regression also lowers each distinct source/codec/width receiver shape across its real repetition and D3 populations.

## Build a network with source initialization and declared startup

For topologies driven by ordinary source initialization and internal messages, the network command connects all owners and transport in one DSLX proc:

```sh
bash tools/emit_protocol_network.sh XLS_ROOT CONFIG FRESH_OUTPUT
```

It accepts the same trusted source/topology configuration as the transport command. Declared `startup` records are delivered by the ordinary inbox as described below. One declared rectangle `ingress` is supported as described below; other interface shapes reject explicitly. External destinations remain separate ready/valid streams, ordered per logical source and recipient, without a global output order. All owners and transport share one clock and reset. This command does not implement independent-device reset, a board interface or application admission.

```text
emit_protocol_network.sh → hls-fabric emit --kind network
  → hls_source_build:write/3 → hls_protocol_network:write/2
    → hls_protocol_network:emit/1
      → hls_protocol_transport:plan/1 (fresh sources, exact inboxes and transport)
        → hls_protocol_control:plan/1 + hls_protocol_schema:domains/2
        → hls_protocol_inbox:attach/5 (checked host slot)
      → hls_protocol_network:plan/2 (checked wiring and packed interface)
      → hls_protocol_network:emit/1 (unchanged composition plan)
        → hls_protocol_transport:emit/1 (prepared actor and transport files)
        → xls_protocol_network:emit/2
          → receiver_I::local_inbox_batch / local_inbox_batch_tick
          → transport::tick → named state/output result
          → sv_protocol_ports:emit/4 (mechanical pin packing)
    → hls_generated_files:write/2
  → compile_source_build.py → shared sampled-clock XLS schedule
```

`local_inbox_batch` exposes the old outbox's complete evaluated payload and layout. `local_inbox_batch_tick` reuses ordinary selection, receipt and action completion, but disables single-effect draining: `output_ready` accepts the entire old batch. Use this interface from reset, never interleave it with serial-effect draining. A stalled batch stays unchanged, and its acceptance edge cannot also reuse that outbox for a new entry. The publisher then retires each recipient's ordered subsequence independently.

Without host ingress, composition adds no state: each actor retains its existing `LocalInboxState`, and transport retains its existing publications/captures. There is one complete old-batch reader per publisher and one selected capture reconstruction per receiver. Offers and eligibility use old registered state. The network first obtains transport observations, computes receiver transitions, then supplies their actual take/release inputs to the transport transition. Those observations are independent of take/release and boundary readiness; the first call's unused next state is discarded by XLS. There is no combinational readiness loop or same-edge credit reuse.

`network/manifest.json` describes the pins and binds direct component DSLX hashes. `source-build.json` records copied imports and the fixed one-stage schedule; `compiled.json` records RTL/tool hashes; `network/commands.json` retains invocations and failures. `files.f` lists top `protocol_network` and its core. The original transport `summary.json` continues to describe the standalone transport; the network manifest records `actor_runtime: true`, `eligible: false`. Supply additional provider imports with `dslx_path => [Directory, ...]` in the trusted source configuration. Inputs and manifests are trusted local build products. Source-rendering failures create no output; filesystem, packaging or XLS failures can retain partial output.

Run `python3 tools/test_protocol_network.py XLS_ROOT FRESH_OUTPUT` with Icarus and Yosys available. The three-actor RTL witness uses actual source owners for three batches per producer and ordinary sink results as feedback. Public output scoreboards check ordered changing payloads, independent stalls and reset interruption followed by two complete incarnations. Deliberately dropped stalled batches and disconnected feedback must fail. Combinational SAT quantifies all finite state/input valuations of this fixture's transport to check the observation dependency cut; a deliberately incorrect reset-independence claim yields a counterexample. These checks trust source extraction, XLS and Yosys/ABC/SAT; they establish neither arbitrary-program refinement nor sufficient application capacity/progress. A whole-fixture XC7 resource screen is local synthesis evidence, not routed or native performance.

The generated clock composition has three layers. `protocol_network.x.in` observes old actor state, previews transport, advances receivers, then applies their take/release decisions. `protocol_boundary.x.in` inserts external-output arbitration between a child preview and its final transition. `protocol_bridge.x.in` does the same for framed inter-board transfers. Their `xls_protocol_*` emitters supply application-specific fields, dimensions and connections; reusable ownership algorithms live in the imported DSLX libraries. Inbox attachment owns slot order: `hls_protocol_inbox:link_bindings/1` checks that indexed slots agree with the link catalogue and returns the spans shared by eligibility, take and release wiring. Numeric link IDs do not define mask offsets.

## Source-network partitions

Set `native_actors => [left, sink]` in the same network configuration to compile only those logical actors and their destination-owned captures. The list must be a nonempty proper subset with no duplicates or unknown IDs; omitting it builds the whole network. Build complementary roles from the same sources/topology. Global actor/link indices are preserved, including holes in the host retirement mask. This is a raw sampled-clock interface for adapter development. Every role and carrier must share clock/reset; it is not yet a physical board interface or an independently resettable network.

The direct call path is `hls_protocol_transport:write/2` → `hls_protocol_partition:plan/5` after fresh capture and fabric planning → `xls_protocol_transport:emit/1` → `xls_protocol_partition` codecs and static DSLX `protocol_partition` control. `xls_protocol_network:emit/2` exposes these crossing pins:

| Direction relative to this role | Inputs | Outputs |
| --- | --- | --- |
| Incoming link I | `remote_I_valid`, `remote_I_slot` (8 bits), `remote_I_frame` (128 bits) | `remote_I_ready`, `remote_I_fault`, `remote_I_free` (one bit per class) |
| Outgoing link I | `remote_I_ready` | `remote_I_valid`, `remote_I_slot` (8 bits), `remote_I_frame` (128 bits) |

Frames use the destination's ordinary operation numbering and schema. The manifest's `crossings` records global source/destination indices, direction, slot codecs and canonical masks; generated codec inputs are content-bound before compilation. Each sender must hold valid, slot and frame unchanged until handshake, preserve link order, and deliver exactly once. A carrier that accepts a frame before the destination does must retain it and cancel it on the same common reset. Application endpoints and separate links have no global chronology.

Incoming validation checks the slot, ordinary header, padding and every source-proved omitted constant before capture. A malformed valid offer is accepted into a sticky link fault without capture; that link then stops until reset. A canonical offer waits for its own destination slot's credit. The read-only `free` mask observes unowned native classes before the current edge; it adds no state. Each incoming crossing adds one fault bit, reported as `crossing_state_bits`; payload, ordering and lease state remain in the original destination captures. Outgoing frames reconstruct from the source's held publication and add no state. Remote readiness affects retirement, not the current outgoing offer. Other local traffic continues independently.

Host commands are delivered separately to each role. Coordinates/selectors retain the full topology meaning; a command selecting no native recipient retires normally. `startup_done` and explicit activation are local to that role, so the caller coordinates whole-network setup/start. `inspection => process` with a cut and `native_actors` in the framed application builder currently reject explicitly. The raw network and merged-output boundary builders expose crossing ports; the existing application gateway cannot carry them.

`python3 tools/test_protocol_partition.py XLS_ROOT FRESH_OUTPUT` builds two independent roles with native indices `[0,2]` and `[1]`. A finite RTL witness covers real source feedback, early postponement, per-sender frame order, independently stalled test carriers and external outputs, interrupted common reset followed by two complete incarnations, and host retirement through sparse masks. Each complete incarnation produces 39 checked frames and final sum 60; a disconnected carrier must fail. Combinational SAT quantifies all fixture state/input bits for canonical admission and retained observation cuts with old state, reset and receive eligibility held fixed, with an intentionally false acceptance claim as a negative control. These checks trust fresh source/schema extraction, DSLX/XLS and the simulator/SAT tools; they do not establish arbitrary-program refinement, temporal progress, independent reset retirement or multi-board admission. Connected XC7 counts include the two test carriers and remain local diagnostics.

## Framed source partitions

Use `bash tools/emit_protocol_bridge.sh XLS_ROOT CONFIG FRESH_OUTPUT` for a framed partition. The config extends the raw network config with `native_actors`, positive 16-bit `host`/`service` addresses, `control => rectangle` and explicit activation. The builder plans the source transport, then `hls_protocol_bridge:plan/2` checks its network/boundary layout, control ports, crossing indices and contender budget. Only after these checks does `hls_protocol_bridge:emit/1` render the boundary and call `xls_protocol_bridge:emit/3`. These return an in-memory file bundle; the outer `write` persists it after all bridge checks succeed. The generated wrapper binds the application's incoming/outgoing link IDs, capture classes, external streams, identity and control adapter. `protocol_bridge.x` owns sessions, credits and delivery reservations; `protocol_framing.x` owns word assembly/serialization; `protocol_rectangle.x` owns the existing rectangle command grammar. The older application gateway shares the latter two modules. `hls_protocol_envelope:fields/1` owns the fixed packet and rectangle wire layouts: `hls_record` packs their host fields, and `xls_struct_codec` generates the checked-in `protocol_envelope.x` structs and codecs. Regenerate that library with `file:write_file(Path, hls_protocol_envelope:emit())` after changing a schema; EUnit checks that it matches. Rectangle validation remains in `protocol_rectangle.x`, which returns a typed spatial frame for either gateway and adapts it to native ingress only at the source boundary. The rectangle adapter is currently the only supported application-control binding; the transport core has no rectangle fields or decoder.

`bridge.etf` contains the trusted local descriptor, `bridge/manifest.json` binds generated inputs, library hashes and state costs, and `files.f` lists the complete RTL. Attachment identity uses canonical source identities and exact generated boundary hardware hashes, never the raw planning term or analysis reports. Changes to the control adapter or framing library change the build identity. Supply source-provider imports with `dslx_path => [Directory, ...]` in the configuration; `hls-fabric emit --kind bridge` copies them into the source bundle. Generated Verilog outside XLS is pin packing only.

The top has `clk`, `reset`, `retire`, word-aligned 32-bit `s_app_*`/`m_app_*` ready/valid/last streams, `fault` and `running`. A complete routed frame is the common broker route word, header and payload words. Attachment binds one nonzero 64-bit session and the exact build identity. Setup and one-shot start follow in input order; the start receipt acknowledges the actual source start handshake. The existing single-network application gateway retains its separate sessionless protocol.

The bridge retains one receive frame and one transmit frame per device. Each incoming native class advertises capacity once and grants it again only after final native release. Data must match an issued class credit, canonical destination frame, session and the next nonwrapping logical-link sequence. An outgoing link retains a reservation until its frame finishes physical transmission and the peer returns the exact sequence/class acknowledgment. Arbitration can pass another blocked link but cannot reorder one link. Invalid framing, identity, credit, sequence or native faults terminate the incarnation; there is no in-place retry. Sequence `0xffffffff` is reserved. The 128-bit ordinary actor frame and fixed envelope widths remain the current wire ABI.

The core's `tick` reads the old state through `inspect_receive` and `decide_transmit`, then computes `commit` and `observe_outputs` separately. `Reception` names validated receive classes and matching owners; `Transmission` names reply selection, a new grant and physical completion. These are pure intermediate values, not registers or additional pipeline stages. The transition priorities are:

| Observed event | State change at this edge | Same-edge restriction |
| --- | --- | --- |
| Recognized attach/start | Wait, or bind/start and reserve reply when TX is empty (and start is ready) | No ordinary transmit grant, including while waiting |
| Valid setup with control readiness | Consume the command | An unrelated transmit grant remains possible |
| Credited incoming data | Consume credit and advance that link's sequence | Cannot advertise the just-consumed credit again |
| Matching ACK for a previously sent frame | Release its outgoing owner | Cannot reuse that owner for another grant |
| Final physical output beat | Clear TX and mark its actor owner sent | Cannot refill TX or accept an ACK relying on this completion |
| Reset | Clear all bridge state and mask transfers | Overrides all decisions; coordinated transport retirement is still required |
| Retirement, child fault or malformed complete input | Latch fault and mask transfers | No retry or ownership cancellation without reset |

A stalled setup/start stays in RX until its handshake; incoming data without the required native readiness is an error. RX consumption and the next input beat likewise occupy different edges. Credit/data grants advance the event sequence, while external events do not. At the reserved sequence limit the bridge drains any held TX, then latches its terminal fault; the fault output reflects that newly latched condition on the following edge. `test/rtl/protocol_bridge_transitions.x` exercises these boundaries with short concrete schedules in the component tier.

`hls_protocol_stream` connects the deployment's brokers through one bounded physical writer and `hls_protocol_relay_queue`. Build participants from the same sources/topology with disjoint, collectively complete native actor sets, then load their descriptors. Device identifiers are arbitrary map keys; this example uses two devices:

```erlang
{ok, A} = file:read_file("WEST/bridge.etf"),
{ok, B} = file:read_file("EAST/bridge.etf"),
West = binary_to_term(A), East = binary_to_term(B),
Deployment = #{actors => maps:get(actors, West),
               devices => #{west => West, east => East},
               limits => #{crossings => 8, commands => 16, events => 32}},
{ok, Stream} = hls_protocol_stream:start_link(
    Deployment, #{west => WestBroker, east => EastBroker},
    #{west => 101, east => 102}),
{ok, 1} = hls_protocol_stream:submit(Stream, start).
```

Routes come from actor ownership: an outgoing link's destination actor identifies its receiving device, whose incoming descriptor must match the link and codecs exactly. There is no “other board” rule. Each device supplies its host/service addresses. Return pairs `{Service, Host}` must be unique across this owner because broker deliveries identify the route without the broker; ambiguous configurations reject before route registration. Brokers must be fresh, distinct connections with `rx_route_limit => 1`.

The sole caller submits `{control, Binary}` using the bound adapter's encoding, currently the source-bound `hls_partition_wire` rectangle ABI. The relay checks envelope capacity; the hardware adapter and native ingress check command meaning and schema. `next/2` returns `{ok,application,{started}}` after every participant acknowledges start, then `{ok,{Device,ExternalIndex},CanonicalFrame}`. The caller decodes application records with the matching source schema. Commands reach every participant in order, without atomic cross-device delivery.

The deployment explicitly declares positive crossing/command limits and an event limit of at least two. One retained data record per directed logical link bounds crossing storage. One event slot is reserved for the aggregate started notification; each device can hold one broker receipt, and the deployment has one physical writer. The conservative retained-record bound is `crossings + commands + events + device_count + 1`, excluding ERTS mailboxes and OS buffers. Membership is fixed for an incarnation. Increasing a limit or changing a topology does not establish application progress or hardware fit.

These synchronous cores require a lossless ordered carrier. After any participant failure, reconnect, ambiguous write or independent reset, retire every deployment route and transport, await every descriptor lease, then reset all participants and choose fresh distinct sessions. `stop/1` waits for the current write and ends the route owner; the caller must still stop the brokers and call `hls_fabric:await_closed/2`. Session labels detect stale traffic under that discipline; they do not authenticate peers or recover a partially delivered transaction. Process inspection, CDC and physical board I/O remain separate.

`python3 tools/test_protocol_bridge.py XLS_ROOT FRESH_OUTPUT` retains the two-device real-broker/RTL integration case. Two finite fresh incarnations each check 39 per-sender records, 27 cross-device messages, ordinary-source feedback, final sum 60, sparse rectangle delivery, independent output stalls and descriptor closure. Public-port checks interrupt attachment, setup and stalled output, exercise retirement, and reject stale sessions/wrong identities. Component SAT quantifies every state/input bit at one incoming link, two classes, one outgoing link and one external stream for reset, retained-output, credit, early-ACK and terminal cancellation properties; an intentionally false admission assertion must produce a counterexample. The complete pair also receives a local XC7 area screen. Separate host-model tests use three arbitrary device keys, irregular endpoints, one source with two destinations, bounded command admission, delayed forwarding completion, aggregate start and collective retirement. Those model tests establish no three-device RTL claim. The witnesses and component proofs trust source extraction, DSLX/XLS, simulators and Yosys/ABC/SAT; they do not establish arbitrary application progress, source refinement, native timing, board fit or N6 repetition qualification. Eligibility stays false.

### Host owner decisions

The deployment relay (`hls_protocol_stream`) and mixed BEAM/RTL owner (`hls_protocol_mixed_stream`, described below) retain different delivery obligations. Both reserve one typed write decision before `issue_write/1` sends it through the broker. A pending physical writer prevents further issue; receipt admission and application delivery can still advance within their bounds.

| Boundary | Deployment relay | Mixed BEAM/RTL owner |
| --- | --- | --- |
| One work pass | Notify → admit each role's held frame once → notify → choose one write | Notify → admit held frame → try reverse admissions → try one source handoff → notify → choose one write → schedule capacity recheck |
| Write priority after attachment | Head command's remaining device fanout → eligible relay ACK → credited pair data | Admitted reverse ACK → head command's BEAM recipients and native write → credited source data |
| Blocked head command | Remaining device fanout retains command order | Busy BEAM recipient retains the unadmitted suffix; later commands and source data wait |
| Start event | Wait for every role, then deliver aggregate start before early output | Append native started response in ordinary event order |
| Graceful retirement | Stop new work; finish only the outstanding write | Same, then retire BEAM admission monitors as well |
| Participant or write failure | Retire the whole incarnation without replay | Same, including source actor and virtual-node connection failures |

A relay transfer follows **source packet → destination credit → reserved destination write → physical success → eligible source ACK → physical ACK success → released pair**. The source may see that ACK and send its next packet before our completion callback arrives; the owner retains that next packet under broker receipt credit until the old pair reservation retires.

A mixed reverse transfer follows **native packet → retained decoded record → destination BEAM admission → eligible ACK → reserved ACK write → physical success**. Admission is a public mailbox barrier, not actor consumption. A full actor retains its reverse record while other actors can admit theirs. Command admission also performs BEAM effects: successful recipients leave the retained command cursor before a busy recipient is retried. Only the capacity check repeats; successful deliveries and failed writes do not replay.

These orders are intentional and implemented by separate schedulers. `hls_protocol_relay_tests` and `hls_protocol_mixed_stream_tests` exercise the actual owners with controlled broker completions; these are finite host witnesses, not hardware or general progress proofs.

## Declared startup messages

The network command accepts the ordinary topology `startup` list, for example `startup => [{receiver, [#value{n=2}, #open{key=7}, #value{n=3}, #value{n=3}]}]`. It does not run a special configuration callback or assume those messages will succeed. The production path is `hls_protocol_transport:write/2` → `hls_protocol_inbox:attach/5` → `hls_protocol_schema:frames/2`, using the receiving actor's fresh source schema, followed by the same `local_inbox_batch_tick` used for internal traffic.

The encoder checks the record tag and arity, packs each value exactly with its typed provider and uses the ordinary 128-bit frame codec. Inexact values, oversized payloads and unsupported codecs reject before receiver emission. Built-in numeric/boolean codecs and full-width integer bit-cast providers are supported; custom wire transforms are not. The fixed frame capacity is the existing ABI, not a new configuration width.

Each declared message has a separate immutable slot, including identical records. Slots follow capture slots in the receiver masks; the manifest records `inbox.startup.offset`, `count` and exact `frames`. They form one logical sender per actor in declaration order. `protocol_startup::head` offers its oldest eligible unconsumed record, and the existing circular selector arbitrates between it and internal sender heads. There is no cross-sender chronology. All startup records become pending after source initialization: an early record may postpone while a later record changes phase, then the earlier record wakes. Configuration is not required to finish before internal messages can run, which permits startup readiness exchanges.

Reservation does not retire a startup message. Its consumed bit changes only when the ordinary owner completes a dispatched `consume`; postponement, publication stalls and source failure preserve it. Shared reset clears these bits and all matching owner/transport state, replaying the declared list for the new incarnation. Startup frames are constants, with no payload registers or dynamic queue. The additional consumed state is S bits for S startup records, alongside the receiver's `3*N + max(1, ceil(log2(N))) + 1` mask/cursor/initialization bits. There is still one selected dispatch per actor per clock. Zero-startup dummy fields are constant and pruned by XLS.

The network's `startup_done` output is true after every declared record has committed consume in this reset incarnation. It reads old registered state, is suppressed during reset/initialization, and does **not** mean application readiness, internal messages drained, output delivery complete or quiescence. With no startup records it becomes true after source initialization. Host ingress uses this flag to open admission. Application-specific capacity/progress admission remains separate; `eligible` remains false.

`python3 tools/test_protocol_startup.py XLS_ROOT FRESH_OUTPUT` exercises the public build command and a two-actor source feedback network. Independent public-output scoreboards cover early postponement, repeated identical records, exact sender order, independent output stalls, real peer acknowledgments and three reset interruptions followed by two complete incarnations. Retiring on acceptance or reordering fixed records must fail the same scoreboard. A canonical but source-invalid value separately checks failure without retirement. Combinational SAT checks oldest eligible selection for every consumed/eligible/valid mask at widths 1, 4 and 8; an eligibility-ignoring negative yields a counterexample. These finite witnesses and combinational properties trust source extraction, XLS and the simulator/SAT tools; they are not a general startup termination or network progress proof. Local XC7 counts are a capacity screen, not native implementation measurements.


## Shared scalar completion

The network build config accepts `arithmetic_groups => [[ActorId0, ActorId1, ActorId2], ...]`. Each group contains two or three distinct logical actor IDs, all native to this build and all compiled from the same source module. Groups cannot overlap. That module must have scalar reductions and no indexed gathers or retained calls. An absent or empty list keeps completion local. The application definition is unchanged; grouping is an explicit build choice.

The call path is `hls_protocol_network:write/2` → `hls_protocol_network:emit/1` → `hls_protocol_transport:plan/1` → `hls_protocol_arithmetic:plan/3`. Validation uses the freshly compiled sources and resolved placement before writing hardware. `receiver/3` selects the shared owner for exactly those members; `xls_protocol_network` then calls `xls_protocol_arithmetic` to connect their grants and completion actions. No supplied IR, kernel manifest or source invariant authorizes this path.

One round-robin arbiter selects a pending, idle actor **before** its scalar completion executes. There is one source-completion call per group. The selected actor registers the result in its existing named `LocalAction`, then retries entry/publication through the ordinary owner. Ungranted actors retain their committed state and may drain an older publication. They cannot accept a new mailbox head or execute another action while completion is pending. Failure, entry and continuation priority remain ahead of scalar completion. All group members share clock/reset; reset masks grants and cancels owner state. A persistent request receives a grant within at most the group size in grant opportunities, assuming the network continues ticking. This is not an application-progress guarantee.

Each group adds one cursor bit for two members or two bits for three. It reads one selected machine and writes one selected action per clock; no operand queue, copied machine bank or delayed return tag is added. The complete scalar callback is combinational between the existing owner registers. Arbitrating it can reduce replicated arithmetic and can lengthen a path; DSP savings alone do not establish throughput or board fit. `network/manifest.json` records the resolved groups, cursor widths and aggregate additional state. Fresh source/DSLX identities bind deployment and admission to this build.

For the periodic example, `python3 tools/emit_protocol_repetition.py XLS_ROOT 3 FRESH_OUTPUT --share-arithmetic` shares completion among its three Phi actors. This convenience option currently supports whole N2/N3 applications; explicit configs can place multiple disjoint groups. Run `python3 tools/test_protocol_arithmetic.py XLS_ROOT FRESH_OUTPUT` for source-completion SAT checks, two/three-actor RTL contention/stall/reset witnesses and a matched connected XC7 resource screen. `python3 tools/test_protocol_repetition.py XLS_ROOT FRESH_OUTPUT --width 3 --share-arithmetic` compares the resulting framed application with the ordinary BEAM oracle.

The locality campaign's earlier shared-arithmetic measurement used a separate four-edge pipeline, compact returned deltas and a Verilog owner. Those frozen results remain historical experimental evidence; they do not qualify this DSLX schedule. That pipeline's IR rewriting and controller are not supported build paths here. A future pipelining change needs its own dependency, ownership, cycle and routed-period evidence.


## Host rectangle input

The same `emit_protocol_network.sh` command connects a single ordinary rectangle ingress. Declare one to four topology targets, each with explicit nonempty schemas and recipients. For example:

```erlang
ingresses => [{host, {rectangle, [3,2]}, [
    {cells, [work], [{actor,a,{at,[0,0]}}, {actor,b,{at,[2,1]}}]},
    {first, [work], [{actor,a,{at,[0,0]}}]}
]}]
```

`hls_protocol_transport:prepare/1` calls `hls_protocol_control:plan/1` once on its freshly compiled bundle. `hls_protocol_schema:domains/2` derives each target's complete header/length/padding masks from the recipients' ordinary source codecs. All recipients of one target must agree on those encodings and the ordered source field names/types; equal masks alone cannot establish schema compatibility. Unsupported codecs, ambiguous recipients, missing schemas and unsupported shapes reject before hardware emission. The shared schema module also encodes startup records; it does not infer a domain from fixture traffic or source-state invariants.

That checked control plan owns both native and host bindings. `hls_protocol_control:project/2` restricts native recipients without renumbering global actor indices; `hls_protocol_transport:control/1` retains the whole plan for application, multi-device and mixed BEAM/native host binding. Host selection and packing share `hls_partition_ingress:select/5`, also used by the scheduler's partition client. The mixed runner only filters selected indices by BEAM ownership. Coordinates belong to each target, so the same actor can occupy different points in different targets without host/hardware disagreement.

For framed builds, `hls_protocol_control:framed/2` checks the selected adapter and explicit activation, then supplies the decoder, ordered gateway, activation wiring, port widths and support-file dependencies. The builders validate the emitted boundary against that contract. The optional XLS driver resolves the emitted support paths; it does not choose control semantics. Rectangle is still the only supported adapter, with its existing fixed wire format. Adding a different interface requires its checked plan, host codec and hardware implementation, not just a new width setting.

`xls_protocol_network:emit/2` calls `xls_protocol_ingress:emit/1` to emit source-bound constant tables. The static parametric `protocol_ingress.x` performs decoding and the registered transition. The network wires its held frame into the addressed receivers' ordinary host inbox slot, and each receiver's committed `take` bit back to that recipient's pending bit. `accepted` is only reservation and must never retire a command. All behavior is DSLX; Verilog remains the mechanical pin adapter.

The network exposes `ingress_data[193:0]`, `ingress_valid`, `ingress_ready` and `ingress_fault`. Data uses the existing flattened `hls_spatial_router::SpatialFrame`: inclusive rectangle `(x0,y0,x1,y1)`, two-bit target selector in declaration order, then the ordinary `axis::Frame` struct. It is **not** the actor-facing 128-bit bit codec with a rectangle prepended; `axis::bits_from_frame` supplies that conversion. Dimensions are 1..65536. Bounds, target, schema header, length and zero padding must all be canonical. All represented payload values remain admissible at this boundary; source callbacks still determine semantic failures.

An accepted canonical command registers one immutable 128-bit frame and one pending bit per selected actor. Recipients consume independently, preserving host order at each actor without claiming atomic broadcast. The boundary accepts no later command until all selected recipients commit source `consume`; reservation, publication stalls, postponement and source failure retain the affected bit. A valid empty selection completes without delivery. There is no refill on the last-consume edge. Malformed accepted input delivers nothing and latches `ingress_fault`, blocking admission until shared reset. Reset cancels the pending command and fault together with all owner/transport state.

Admission opens only after `startup_done`; internal traffic remains active during startup. This is one outstanding host command, **not** an unbounded mailbox: a postponed command can block a later host command needed to wake it. Applications must establish their own finite sequencing and capacity/progress obligations. The command makes no independent-device reset or live-board claim and keeps `eligible: false`.

The ingress adds `128 + A + 1` logical state bits for A elaborated actors; unaddressed pending bits can be pruned. Each addressed receiver adds one host slot after its capture and startup slots, recorded in `inbox.host`. That slot extends the existing reservation/postponement/release masks and may widen the cursor; it adds no payload copy. `network/manifest.json` retains the checked ingress tables, state budget and exact generated component hashes. Frame-width parametrization remains a separate compiler/adapter task.

`python3 tools/test_protocol_ingress.py XLS_ROOT FRESH_OUTPUT` builds two actual source recipients plus a feedback relay. Its finite public-pin scoreboards exercise point/broadcast/empty selections, two targets, source postponement and real feedback, per-recipient ordering, independent output stalls, three reset interruptions, two complete incarnations, eight malformed commands and canonical source failure. Early-retirement and live-frame-bypass controls must fail. Combinational SAT quantifies all finite three-recipient state/input patterns for retirement, admission, reset and malformed behavior, and all finite generated fixture state/input patterns for the registered host-input cut, plus every 194-bit command for the fixture’s two-target geometry and ordinary ABI; a false retirement control yields a counterexample. These checks trust source extraction, XLS and Yosys/ABC/SAT. They are finite witnesses and specified combinational properties, not arbitrary-program refinement or application admission. The whole-fixture XC7 screen is local synthesis, not native implementation performance.

### Explicit activation after setup

Set `activation => explicit_start` in the same network build config to expose `start_valid`, `start_ready` and `running`. `hls_protocol_network:write/2` validates this option before building sources; `xls_protocol_network:emit/2` calls the static DSLX `protocol_activation` functions in the generated clock. Unknown modes reject. Omission or `automatic` keeps the existing automatic behavior and adds no activation state or pins.

Explicit mode adds one running bit. While it is clear, only internal capture eligibility is masked: source initialization, local entry work, declared startup records, host setup and publications still execute. Pending internal captures retain their ownership and order. `start_ready` requires consumed startup records, no pending host recipients, no offered host command and no observed actor/publisher/ingress fault. Thus a new host command wins over a concurrent start request, and the last setup-consume edge cannot also accept start. No host ingress means those host conditions are trivially satisfied. A handshake sets running for the following clock; repeated starts have no effect. Common reset clears running and cancels all component ownership.

This is a consumption boundary, not an application-ready or quiescence assertion. Pending entry work, publications and internal messages need not be drained. In particular, setup that waits for an internal reply can keep the single host command pending and prevent start indefinitely; such work belongs after start. Running is monotone until reset and remains asserted if a later source fault stops progress. Host software must follow the application's setup protocol; this option does not establish network capacity or progress eligibility.

`python3 tools/test_protocol_activation.py XLS_ROOT FRESH_OUTPUT` exercises two actual source setup recipients and a feedback relay. Public-pin RTL scoreboards retain internal messages before start, distinguish pre-start setup from later feedback, check competing requests, independent output stalls, four reset interruptions and two complete incarnations, then reject malformed, failed and postponed setup. Ungated-capture and premature-start controls must fail. A second network covers explicit activation without a host ingress. Combinational SAT covers all activation control bits, masks of widths 1/3/8/257 and all generated three-actor fixture state/input bits for the registered start cut and pending-command exclusion. These finite witnesses and specific combinational properties trust source extraction, XLS and Yosys/ABC/SAT; they do not prove arbitrary-program refinement or application progress. Local XC7 area is a capacity screen, not native performance.


## Shared external output endpoints

Use `bash tools/emit_protocol_boundary.sh XLS_ROOT CONFIG FRESH_OUTPUT` with the same source-network config to expose **one stream per declared external endpoint**, including unused declarations. The production path is `hls_protocol_boundary:write/2` → `hls_protocol_boundary:plan/2` (network ports and endpoint fan-in) → `hls_protocol_boundary:emit/1` → `hls_protocol_network:emit/1` → `xls_protocol_boundary:emit/2` → static DSLX `protocol_egress`, followed by the shared file-bundle writer. The shell command uses `hls_source_build:write/3` to package that output and its support libraries, then invokes the compiler’s `compile_source_build.py`. That driver verifies the complete `source-build.json` input inventory and follows its one-stage clock schedule. `files.f` lists the resulting core and mechanical Verilog pin adapter.

The boundary replaces separate producer pins with `external_I_valid`, `external_I_data[127:0]` and `external_I_ready`. All startup, host, explicit-start and fault pins pass through. Data is meaningful only while valid, except that unused endpoints always drive zero. `boundary/manifest.json` maps each index to its canonical normalized topology ID (printed Erlang term text) and exact producer membership. Indices follow normalized topology order, not source declaration order. The underlying network manifest retains both its separate producer streams and their endpoint indices.

An empty endpoint is always invalid with zero data. A singleton directly exposes its existing network publication and adds no state. Multiple producers use round-robin arbitration; the selected producer remains held while the sink stalls, and only that producer receives acceptance. The sources retain their valid/frame until accepted, so arbitration copies no payload. Cursor advancement occurs only on transfer. Different endpoints have independent readiness and ownership. This preserves per-logical-sender/destination order, with no cross-sender chronology or whole-network progress guarantee. Common reset cancels arbitration ownership together with the matching source/transport state.

For N=2..256 producers, each endpoint adds `2*ceil(log2(N))+1` state bits: cursor, held owner and held flag. It reads N valid bits and selects one existing 128-bit payload, accepting at most one frame per clock. Fan-in above 256 rejects before writing any output. Frame capacity remains the existing ABI; global width parametrization is deferred. The wrapper previews the network with producer readiness cleared and uses arbiter acceptance only for the final transition. This composition requires network observations to be independent of live producer readiness.

`python3 tools/test_protocol_boundary.py XLS_ROOT FRESH_OUTPUT` checks actual source-generated frames against ordinary BEAM callbacks/codecs. Its finite public-pin RTL witness covers shared/single/empty endpoints, late arrivals behind a stalled selection, independent stalls, host/start passthrough, four reset interruptions and two complete incarnations. Dropping the lock or acknowledging every producer must fail. Combinational SAT checks all legal component state and input bits at fan-ins 1/3/8/36 for acceptance, transition, readiness independence and retained output under the producer hold assumption; a false multi-accept claim yields a counterexample. Persistent-request service is a finite witness, covering every initial cursor and one full round of accepted grants with interleaved stalls. Separate all-state/input cuts check the generated fixture network and a network with real internal feedback. These checks trust source extraction, DSLX/XLS and the simulator/JIT/Yosys/SAT tools. Local XC7 component and connected capacity screens are not native area or routed timing. The 36-producer LUT screen is diagnostic: its unchanged budget and pass/fail verdict are retained separately from functional qualification. A failed capacity screen does not establish an admissible implementation. Application wire framing, semantic capacity/progress admission and live-board qualification remain separate; `eligible` stays false.


## Framed application build

`bash tools/emit_protocol_application.sh XLS_ROOT CONFIG FRESH_OUTPUT` connects a fresh source boundary to the existing application broker protocol. Add `device` and `host` (1..65535) to the boundary configuration. Explicit activation is required and selected by default; this builder rejects `automatic`. For a runnable four-producer example:

```erlang
#{sources => [{"test/hls_protocol_boundary_fixture.erl", []}],
  topology => {hls_protocol_boundary_fixture, topology, []},
  actor_limit => 4, device => board, host => 1}.
```

The concrete call path is `hls-fabric emit --kind application` → `hls_source_build:write/3` → `hls_protocol_application:write/2` → `hls_protocol_application:emit/1` → `hls_protocol_boundary:plan/2` → host codec binding → `hls_protocol_boundary:emit/1`, followed by `hls_generated_files:write/2`. The builder binds the same elaborated actor identities, rectangle ingress, loaded source codecs and canonical external endpoint order into `deployment.etf`. Shared event selectors must agree on field names/order, types and canonical framing, not merely payload width. The application requires one rectangle ingress and at least one external endpoint. Its SHA-256 identity covers canonical compiler content identities, normalized topology, placement, arithmetic groups, emitted boundary DSLX/Verilog and the boundary/wire binding. Fresh builds in different processes or relocated source trees retain the same identity when their preprocessed semantics and relative source/include layout agree. Source, startup, placement, host bindings or generated boundary hardware changes invalidate it. This is a build-mismatch check, not authentication or native equivalence.

Attachment identity is separate from package byte integrity. Diagnostic paths, build-local references, output directories and optional model reports do not enter it. Path-sensitive source values such as `?FILE` remain significant, as do failure locations and preprocessing options. The bridge additionally binds its framing/control library hashes. The enclosing source package records exact generated/support-file hashes; attachment identity is not a cache key for a complete XLS toolchain, external provider implementation or bitstream.

`xls_protocol_application` instantiates the existing `hls_partition_io::OrderedBoundary`; `sv_protocol_application` only connects pins and converts actor frame bit ordering to the gateway's DSLX struct ordering. It reuses the existing `hls_partition_activation.sv` bridge unchanged. There is no new framing or activation state machine. The compiler builds the boundary with its single-stage sampled-clock schedule and the shared gateway with its established two-stage channel schedule. `files.f` lists the complete application RTL; `source-build.json` records both compilation units and their copied dependencies; `compiled.json` records the source-bundle hash, tool identities, per-unit commands and complete RTL dependencies.

Use the returned deployment directly with the existing host client:

```erlang
{ok, Bytes} = file:read_file("BUILD/deployment.etf"),
Deployment = binary_to_term(Bytes), % trusted local build artifact only
{ok, Stream} = hls_partition_stream:start_link(Deployment, #{board => Broker}, #{}),
{ok, 1} = hls_partition_stream:submit(Stream, {host, cells, {0,0,0,0}, {cfg,1}}),
{ok, 1} = hls_partition_stream:submit(Stream, {host, cells, {1,0,1,0}, {cfg,2}}),
{ok, 1} = hls_partition_stream:submit(Stream, start).
```

Consume events with `next/2`; `{ok, board, application, {started}}` confirms the actual network start handshake. Startup/setup publications may arrive before that reply. Host queue admission is not execution, and the source's consumed setup is not a general readiness proof. The single ordered command channel prevents start from overtaking earlier setup. Source faults remain exposed on the application top's diagnostic pins; they are distinct from a gateway framing-fault packet. Reset must cover gateway, activation bridge, boundary, actors and physical transport before fresh attachment. See [application streams](application-streams.md) for credit, timeout and descriptor-retirement contracts.

`python3 tools/test_protocol_application.py XLS_ROOT FRESH_OUTPUT` builds this path from source and connects actual `hls_fabric` brokers and `hls_partition_stream` clients to public RTL ports. Two finite incarnations check 24 events each against ordinary BEAM callbacks, independent per-producer host feedback, setup/start ordering and output stalls. Public-wire tests interrupt attachment, setup and a blocked output with coordinated reset; wrong identity poisons the gateway until reset. These are simulation witnesses trusting source extraction, XLS, Verilator/Icarus and the host runtime. They establish neither arbitrary application progress nor native throughput. The build remains opt-in, with `eligible: false`; decoder-specific admission and device capacity remain separate from merging this functional integration.

## Finite repetition application

After `rebar3 release`, `_build/default/rel/hls/bin/hls-repetition --width 3 --output FRESH_OUTPUT` emits the periodic example without Python or XLS. Add `--split 3` with width 6, `--mixed`, `--inspect` or `--share-arithmetic` within the bounds below. The configuration is owned by `phi_protocol_config:repetition/2`. [The source build manifest](building.md#source-toolchain) supplies a separate external compiler with copied imports, entry points and required schedules.

As an optional combined emission/XLS convenience, `python3 tools/emit_protocol_repetition.py XLS_ROOT 3 FRESH_OUTPUT` builds a periodic line using the pinned compiler's ordinary Phi, phenomenological data and syndrome actors. The public source-application builder emits `FRESH_OUTPUT/build/deployment.etf` and the complete RTL list at `FRESH_OUTPUT/build/files.f`. Width counts data sites: each width-N line has 3N actors. The command accepts N=2..16; only the exercised instances have the evidence below, and emission does not establish board fit or semantic admission.

Attach that deployment with `hls_partition_stream`, then call `phi_protocol_repetition:run(Stream, 3, 8, 123, 60000)`. The arguments are width, first noise-free round, readout request ID and timeout in milliseconds. The helper sends the cutoff before explicit start, returns every correction through the same ordered command stream, waits for a common round where every Phi actor reports quiet and empty, then queries all data cells. Its result contains the fence round, per-source events, corrections and sorted X-basis replies. Noise is generated by the source actors; the host does not supply precomputed fault samples.

Use a fresh explicit-start stream with the matching width/codecs and enough host queue capacity. The demonstration limits cutoff and observed rounds to 0..511, the request to u32, and requires a positive timeout. It aborts on queue rejection, timeout or unexpected events or duplicate statuses/readouts without retrying; retire the stream and reset the complete application before another run. The quiet fence relies on each source's correction-before-status ordering and the ordered correction/query lane. It does not claim decoder convergence, general deadlock freedom or QEC accuracy.

`python3 tools/test_protocol_repetition.py XLS_ROOT FRESH_OUTPUT` builds N2 and N3 serially, runs an independent ordinary-BEAM actor graph, and runs the production helper through real brokers and public RTL ports. It compares the common fence, correction set, every sender's ordered events through that fence, and final readout; the shared simulator stalls output and observes every actor's public fault pins. It also checks stream/descriptor retirement. These are finite application witnesses. The existing application regression supplies framing/reset/identity-rejection coverage; native timing and physical capacity remain separate. The networked deployment below exercises independent RTL roles.


## Networked repetition deployment

`python3 tools/emit_protocol_repetition.py XLS_ROOT 6 FRESH_OUTPUT --split 3` places data, syndrome and Phi actors at coordinates 0..2 on device 0 and 3..5 on device 1. Both roles run the source backend; BEAM hosts only the typed application loop and packet relay. Each role has its own framed port, identity and session. The output contains `build/role0/files.f`, `build/role1/files.f` and one trusted `build/deployment.etf`. `--split K` accepts any nonempty two-way placement for N=2..16; the regression below exercises N6/3+3. Process inspection is currently unavailable on this framed path.

For other applications or participant sets, call `hls_protocol_deployment:write/2` (or `hls-fabric emit --kind deployment --config CONFIG --output FRESH_OUTPUT`) with the ordinary sources/topology, `control => rectangle`, and:

```erlang
#{devices => #{north => #{native_actors => [left,sink], host => 2, service => 29},
               south => #{native_actors => [right], host => 3, service => 31}},
  limits => #{crossings => 8, commands => 128, events => 128}}.
```

This is the placement portion of a configuration, not a standalone application. Device IDs are arbitrary terms; each configured actor must belong to exactly one device. The builder emits fresh numbered role directories, derives and checks crossing codecs, and records the device-to-directory map. Each role currently requires incoming/outgoing crossings and an external endpoint. Source-record layouts are checked against loaded host codecs through `hls_protocol_application_binding`, also used by the single-device application builder. Event decoding permits only that device's actual producers at the emitted external index. The completed deployment remains `eligible => false`.

`hls_protocol_routing:plan/1` checks complete actor ownership, one outgoing/incoming descriptor per crossing, matching codecs, nonempty unique class slots, wire index bounds and the declared crossing limit. Deployment generation runs this static check before bridge rendering; `hls_protocol_stream` runs it again on the loaded descriptor before registering broker routes. Only then does `hls_protocol_relay_queue:new/2` bind fresh sessions and initialize credits, sequences and retained records. Static routing is independent of an incarnation; session uniqueness, transport retirement and reset remain runtime obligations.

Attach the emitted repetition deployment to two already opened brokers:

```erlang
{ok, Bytes} = file:read_file("BUILD/deployment.etf"),
Deployment = binary_to_term(Bytes), % trusted local build artifact only
{ok, Stream} = hls_protocol_stream:start_application(
    Deployment, #{0 => Broker0, 1 => Broker1}, #{0 => FreshSession0, 1 => FreshSession1}),
Result = phi_protocol_repetition:run(hls_protocol_stream, Stream, 6, 8, 123, 120000),
ok = hls_protocol_stream:stop(Stream).
```

`start_application/3` adds typed commands/events to the existing bounded relay; it adds no process, queue or hardware state. The same `submit/2` now accepts `{Ingress,Target,Bounds,Record}`. Source codecs validate it before admission, then the relay broadcasts the shared global rectangle to every role; native sparse masks ignore unowned targets. `next/2` returns `{ok,Device,External,Record}`, with `{ok,application,application,{started}}` first after every role acknowledges activation. There is no atomic multi-device update. Raw `start_link/3` retains its raw-frame API.

The repetition helper reuses its existing cutoff, correction-feedback, common-fence and readout loop. The caller must subsequently close **every** broker and await all transport leases before coordinated hardware reset and fresh sessions. Reaching the application's quiet fence does not drain ongoing Phi communication: stopping the deployment intentionally cancels remaining chatter. An uncertain or partial write must never be replayed.

`python3 tools/test_protocol_deployment.py XLS_ROOT FRESH_OUTPUT` builds two independent N6 roles and compares two fresh incarnations with an independently executed ordinary-BEAM reference. Real brokers carry every cross-role message and every correction/query; the simulator accesses only public ports and applies independent output stalls. The comparison checks each logical sender through the common fence, all corrections and final readout. Shutdown requests collective retirement, checks that it masks public handshakes, and closes both peer endpoints; both transport leases must then close before a new incarnation. This is a finite integration witness, not a throughput test, general progress proof or live-device result. `--area` additionally maps the complete connected pair under the preregistered 60000-LUT/36000-FF local XC7 screen; passing it does not establish Zynq-7030 fit or routed timing. The new regression has its own bounded CI job.


## Mixed BEAM/native repetition

`python3 tools/emit_protocol_repetition.py XLS_ROOT 3 FRESH_OUTPUT --mixed` places the three ordinary data/noise actors in BEAM and the six syndrome/Phi actors in one native partition. The native side reuses the framed DSLX bridge unchanged. Output includes `build/mixed.etf` and `build/files.f`; `--mixed` excludes `--split` and `--inspect`.

The concrete source path is `hls-repetition --mixed` → `phi_protocol_config:repetition/2` → `hls_source_build:write/3` → `hls_protocol_mixed:write/2` → `hls_protocol_mixed:emit/1` → `hls_protocol_bridge:plan/2` → host route/codec checks → `hls_protocol_bridge:emit/1`, followed by `hls_generated_files:write/2`. The mixed builder derives the complementary BEAM actors, startup records, routes and crossing codecs from the fresh source bundle. `hls_protocol_application_binding` checks loaded host codecs against those sources. For another application, supply the ordinary bridge configuration with `native_actors`, `control => rectangle`, `host` and `service`. Every BEAM output must have exactly one native or external recipient; BEAM-to-BEAM routes and inspection are unsupported. The build remains `eligible => false`.

Create disconnected ordinary actors from the trusted local plan, open the application broker, then bind the stream owner to a dedicated virtual node:

```erlang
{ok, Bytes} = file:read_file("BUILD/mixed.etf"),
Plan = #{actors := Actors} = binary_to_term(Bytes),
Pids = maps:map(fun(_, #{module := M}) -> {ok, P} = M:start_link(), P end, Actors),
{ok, Stream} = hls_protocol_mixed_stream:start_link(Plan, AppBroker, Pids, FreshSession, #{}),
Service = hls_protocol_mixed_host:service(Plan, Stream, Pids),
{ok, Node} = hls_node:start_link(VirtualNodeName,
    #{application => AppBroker, debug => DebugBroker}, [Service], #{}),
pong = net_adm:ping(VirtualNodeName),
Result = phi_protocol_repetition:run(hls_protocol_mixed_stream, Stream, 3, 8, 123, 60000).
```

Use a distributed BEAM VM with the compiled application modules loaded, a fresh matching hardware session after coordinated reset, and the existing node adapter's broker prerequisites. `hls_node` still requires a distinct debug broker, although this source service does not use it or expose native inspection. The integration fixture supplies an inert lifetime broker for that requirement. The caller owns actor/node/broker shutdown: stop the stream, stop the virtual node and actors, close the brokers and peer endpoints, and await transport leases before another reset/session. `stop/1` alone does not reset hardware or stop actors.

The stream is the exclusive input writer for those BEAM actors. It admits startup and typed controls through public `hls_statem:info/2` barriers, then connects their outputs to virtual native/external PIDs before explicit native start. ERTS supplies the real sender PID; the node permits one authenticated handoff at a time. The owner checks each sender and route, then queues canonical frames per logical pair. Native class credits govern capture reuse. Reverse messages are acknowledged only after the destination BEAM actor has admitted the cast; admission does not mean consumption. A full actor can postpone one pair while other actors advance.

There are at most 64 outbound records, 16 commands, 32 application events and 12 reverse pairs, with one record per reverse pair. Together with the single distribution handoff, broker receipt and physical writer, owner storage is bounded by 128 records. ERTS outbound queues and actor mailboxes are separate. The exclusive-writer assumption requires trusted processes not to bypass the owner; cookie authentication does not isolate malicious local code. Finite callbacks, fair consumers and sufficient application-level mailbox capacity remain obligations. An actor, owner, connection or transport failure retires the incarnation; ambiguous writes or casts cannot be replayed, and reconnect is unsupported.

`python3 tools/test_protocol_mixed.py XLS_ROOT FRESH_OUTPUT` runs this production path for N3 over two fresh incarnations, using actual BEAM data actors, ERTS distribution, brokers and public RTL ports. It compares per-sender events, correction feedback, the common quiet fence and readout against a fresh ordinary-BEAM reference; it also checks output stalls, public retirement and descriptor closure. Host regressions cover selective postponement, independent actor capacity, timeout ambiguity, sender authentication, order and owner/connection death. These are finite witnesses, not QEC validation, throughput estimates or general progress proofs. `--area` additionally screens the complete native partition against 36000 LUTs, 24000 FFs and zero BRAM/DSP in local XC7 mapping; passing does not establish routed timing or Zynq-7030 fit.

## Application-owned dependency models

A source configuration may request `protocol_model => {Provider, Options}`. Omit it (or use `none`) for an unannotated build. `Provider` is trusted application code on the build VM's code path, implementing `hls_protocol_model`: `derive(Inventory, Options)` returns a map with `nodes` and `edges` plus application annotations; `summary(Model)` returns a JSON-encodable map. The inventory comes from the fresh source compilation. The provider must reject source shapes its model does not cover; this interface does not infer that coverage or certify source refinement.

The call path is the chosen source builder → `hls_protocol_transport:prepare/1` → `hls_protocol_model:check/2` → `Provider:derive/2` → `hls_protocol_wait_graph:check/2` → `Provider:summary/1`. Both callbacks run once during preparation. Placements share the checked report, and `hls_protocol_model:emit/1` adds it to the in-memory file bundle without calling the provider again. The outer writer persists that bundle. Invalid graphs and callback/summary-encoding errors fail before hardware emission. The backend contains no application role or message-schema selection.

The shared checker requires unique nodes, known edge endpoints and an acyclic zero-lag subgraph. Zero-lag waits must decrease the computed finite rank; older-generation edges retain their initial-marking/source-transition obligations. A successful check establishes a property of the supplied finite graph only. It does not establish source execution refinement, startup marking, guard agreement, fairness, convergence or physical timing.

`BUILD/protocol-model.etf` retains the provider, complete `model`, `application` summary, separate `analysis` result (including ranks), and `inventory_sha256`; the same report appears in `transport.etf`. ETF is trusted local build data. `protocol-model.json` keeps the application summary separate from the generic graph counts and unresolved checker obligations. `analysis.whole_protocol_eligible` stays false. No report is a certificate or input to hardware lowering, and analysis does not enter the deployment fingerprint.

### Phi's periodic model

`phi_protocol_config:repetition/2` selects `{phi_protocol_model, ModuleRoles}`. The provider lives beside the Phi application, while `hls_protocol_wait_graph` remains shared. Each used module must have exactly one role (`data`, `syndrome` or `phi`) and its complete source phase list. Phi roles also declare a diffusion `rounds` count from 1 to 256; adjacent Phi roles must agree. These are explicit application hypotheses, not inferred source invariants. The repetition example annotates its twelve diffusion rounds.

The model includes source stages, each labelled source/destination/port/schema capture, slot reuse after the preceding receive, previous-publication retirement (including empty data/syndrome entries), and same-snapshot ordering between ports addressed to one PID. Query prefetch crosses one logical round. It never imposes an arrival order between independent senders. Unsupported phases, schemas, roles, duplicate channels or same-generation dependency cycles reject the build. Source guards, generation keys and publication/receipt refinement, startup marking, local arbitration, finite host work, fair sinks and reset before generation wrap still require qualification. Source failure freedom and decoder convergence remain unestablished.

`rebar3 eunit --module=hls_protocol_model_tests,phi_protocol_model_tests,hls_protocol_wait_graph_tests` exercises the generic provider boundary, a non-Phi source build, fresh N2/N3/N6 and D3 channel multiplicities, cyclic-model rejection and the public Phi application builder. It compares annotated/unannotated DSLX and pin adapters, alpha-equivalent source plans and the deployment ABI. Compiler plans retain unique symbolic references internally, but attachment identities use the compiler's alias-preserving canonical content identity. Optional model reports do not affect attachment or inspection identities. These are finite source/model consistency checks, not RTL witnesses or progress proofs. The same tests run in ordinary EUnit CI without XLS or a release build.

## Passive process inspection

Add `inspection => process` to a source-application configuration, or use `python3 tools/emit_protocol_repetition.py XLS_ROOT 3 FRESH_OUTPUT --inspect`. The default is `none`. `hls_protocol_network:write/2` validates this choice, `hls_protocol_inspection:emit/1` returns source-bound DSLX projections and a catalog, and the application wrapper connects the unchanged debug router/query service on endpoint 2. `files.f` includes those RTL dependencies. This option changes the generated interface, manifest and deployment identity, so attach the matching fresh build.

The top exposes independent 32-bit `s_dbg_*`/`m_dbg_*` ready/valid streams, with keep and last. Clock and reset must cover the application and debug service together. Attach the debug stream to a broker, then bind the trusted local build catalog:

```erlang
{ok, Bytes} = file:read_file("BUILD/network/inspection.etf"),
Plan = #{manifest := Manifest} = binary_to_term(Bytes),
{ok, Client} = hls_debug:start_link(undefined, {fabric, DebugBroker, 2}),
{ok, Session} = hls_protocol_observation:open(Client, Manifest),
Catalog = hls_protocol_observation:catalog(Plan, Session),
{ok, Target} = hls_debug_catalog:actor(Catalog, {actor, {phi, 0, 0}}),
hls_debug:info(Target, [cycle, initialized, phase, failed, reduction, gather]).
```

Use a logical actor identity from this build's catalog; the example is a repetition-code identity. The opener checks the actual hardware INFO fingerprint and actor-only resource layout. The catalog also binds exact source actor identities/modules to resource indices. Its source identities are canonical compiler content identities; raw source paths and preprocessing provenance remain in `transport.etf`, `summary.json` and actor sidecars. ETF is trusted local build data, never network input. Its finite phase/failure/collection codebook supplies atoms to the shared decoder; application modules need not be loaded in the host.

Each query samples one process's committed phase, initialization, failure and collection metadata at the debug service's acceptance edge, before that edge's application update. The existing service retains that coherent value through reply stalls. Queries neither consume actor messages nor stall the application. Different queries are not atomic together. Payloads, mailbox occupancy and continuous event history are unavailable; tracing reports unsupported. The projection adds no per-actor state, but the selection mux and shared reply service have an area/timing cost.

`hls_process_profile:capture(Catalog, Identities, Options)` performs bounded serial queries. Supply all of `#{session => <<"run-1">>, reset_free => true, rounds => 3, timeout_ms => 10000, interval_ms => 0, budget_ms => 60000}`. At most 10000 queries are accepted. The result retains samples, failed attempts and unattempted count; `write/2` saves it as exclusive JSON. The reset-free label is a caller assumption, not something sparse samples prove. Stop and retire the client/transport after reset, clock wrap, reconnect or timeout; create a fresh session after coordinated reset. Timeouts do not cancel device work.

`python3 tools/test_protocol_inspection.py XLS_ROOT FRESH_OUTPUT` exercises the actual build and shared Erlang APIs. Combinational SAT compares plain/scalar/gather projections against ordinary typed-machine fields for every raw machine bit pattern, initialization bit and reset bit; a second check covers every generated N3 network state/input and query address for application noninterference. A false equal-process-observation claim must produce a counterexample. Two finite broker/RTL incarnations run N3 correction feedback and canonical readout against independent ordinary BEAM actors while sampling all nine processes, stalling debug and application outputs independently, and comparing application pins with an unqueried RTL twin each cycle. A separate public-port witness resets four partial/stalled debug transactions and checks fresh INFO and process replies. These checks trust source extraction, XLS, Yosys/ABC/SAT, Verilator/Icarus and the host runtime; they establish neither arbitrary-source refinement, progress, continuous history nor native performance.
