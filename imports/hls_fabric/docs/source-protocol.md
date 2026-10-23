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

The same transport build command now emits `actors/receiver_I.x` for each elaborated actor, listed in `summary.json` under `receivers`. The direct path is `hls_protocol_transport:write/2` → `hls_protocol_inbox:attach/5` → `hls_local_actor:write/2`. Each receiver includes the ordinary actor owner and source-derived codecs for its exact incoming capture links. Compile a receiver with the existing command:

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
emit_protocol_network.sh → emit_protocol_network.escript
  → hls_protocol_network:write/2
    → hls_protocol_transport:write/2 (fresh sources, exact inboxes and transport)
      → hls_protocol_ingress:plan/1 + hls_protocol_schema:domains/2
      → hls_protocol_inbox:attach/5 (checked host slot)
    → xls_protocol_network:write/2
      → receiver_I::local_inbox_batch / local_inbox_batch_tick
      → transport::tick → named state/output result
      → sv_protocol_ports:write/5 (mechanical pin packing)
  → compile_protocol_network.py → shared sampled-clock XLS compiler
```

`local_inbox_batch` exposes the old outbox's complete evaluated payload and layout. `local_inbox_batch_tick` reuses ordinary selection, receipt and action completion, but disables single-effect draining: `output_ready` accepts the entire old batch. Use this interface from reset, never interleave it with serial-effect draining. A stalled batch stays unchanged, and its acceptance edge cannot also reuse that outbox for a new entry. The publisher then retires each recipient's ordered subsequence independently.

Without host ingress, composition adds no state: each actor retains its existing `LocalInboxState`, and transport retains its existing publications/captures. There is one complete old-batch reader per publisher and one selected capture reconstruction per receiver. Offers and eligibility use old registered state. The network first obtains transport observations, computes receiver transitions, then supplies their actual take/release inputs to the transport transition. Those observations are independent of take/release and boundary readiness; the first call's unused next state is discarded by XLS. There is no combinational readiness loop or same-edge credit reuse.

`network/manifest.json` describes the pins and binds direct component DSLX hashes. `network/compiled.json` records RTL/tool hashes, import paths and the fixed one-stage schedule; `network/commands.json` retains invocations and failures. `files.f` lists top `protocol_network` and its core. The original transport `summary.json` continues to describe the standalone transport; the network manifest records `actor_runtime: true`, `eligible: false`. Additional provider imports can be supplied to `compile_protocol_network.py` with `--dslx-path DIR`. Inputs and manifests are trusted local build products. Failed builds retain partial output.

Run `python3 tools/test_protocol_network.py XLS_ROOT FRESH_OUTPUT` with Icarus and Yosys available. The three-actor RTL witness uses actual source owners for three batches per producer and ordinary sink results as feedback. Public output scoreboards check ordered changing payloads, independent stalls and reset interruption followed by two complete incarnations. Deliberately dropped stalled batches and disconnected feedback must fail. Combinational SAT quantifies all finite state/input valuations of this fixture's transport to check the observation dependency cut; a deliberately incorrect reset-independence claim yields a counterexample. These checks trust source extraction, XLS and Yosys/ABC/SAT; they establish neither arbitrary-program refinement nor sufficient application capacity/progress. A whole-fixture XC7 resource screen is local synthesis evidence, not routed or native performance.

## Declared startup messages

The network command accepts the ordinary topology `startup` list, for example `startup => [{receiver, [#value{n=2}, #open{key=7}, #value{n=3}, #value{n=3}]}]`. It does not run a special configuration callback or assume those messages will succeed. The production path is `hls_protocol_transport:write/2` → `hls_protocol_inbox:attach/5` → `hls_protocol_schema:frames/2`, using the receiving actor's fresh source schema, followed by the same `local_inbox_batch_tick` used for internal traffic.

The encoder checks the record tag and arity, packs each value exactly with its typed provider and uses the ordinary 128-bit frame codec. Inexact values, oversized payloads and unsupported codecs reject before receiver emission. Built-in numeric/boolean codecs and full-width integer bit-cast providers are supported; custom wire transforms are not. The fixed frame capacity is the existing ABI, not a new configuration width.

Each declared message has a separate immutable slot, including identical records. Slots follow capture slots in the receiver masks; the manifest records `inbox.startup.offset`, `count` and exact `frames`. They form one logical sender per actor in declaration order. `protocol_startup::head` offers its oldest eligible unconsumed record, and the existing circular selector arbitrates between it and internal sender heads. There is no cross-sender chronology. All startup records become pending after source initialization: an early record may postpone while a later record changes phase, then the earlier record wakes. Configuration is not required to finish before internal messages can run, which permits startup readiness exchanges.

Reservation does not retire a startup message. Its consumed bit changes only when the ordinary owner completes a dispatched `consume`; postponement, publication stalls and source failure preserve it. Shared reset clears these bits and all matching owner/transport state, replaying the declared list for the new incarnation. Startup frames are constants, with no payload registers or dynamic queue. The additional consumed state is S bits for S startup records, alongside the receiver's `3*N + max(1, ceil(log2(N))) + 1` mask/cursor/initialization bits. There is still one selected dispatch per actor per clock. Zero-startup dummy fields are constant and pruned by XLS.

The network's `startup_done` output is true after every declared record has committed consume in this reset incarnation. It reads old registered state, is suppressed during reset/initialization, and does **not** mean application readiness, internal messages drained, output delivery complete or quiescence. With no startup records it becomes true after source initialization. Host ingress uses this flag to open admission. Application-specific capacity/progress admission remains separate; `eligible` remains false.

`python3 tools/test_protocol_startup.py XLS_ROOT FRESH_OUTPUT` exercises the public build command and a two-actor source feedback network. Independent public-output scoreboards cover early postponement, repeated identical records, exact sender order, independent output stalls, real peer acknowledgments and three reset interruptions followed by two complete incarnations. Retiring on acceptance or reordering fixed records must fail the same scoreboard. A canonical but source-invalid value separately checks failure without retirement. Combinational SAT checks oldest eligible selection for every consumed/eligible/valid mask at widths 1, 4 and 8; an eligibility-ignoring negative yields a counterexample. These finite witnesses and combinational properties trust source extraction, XLS and the simulator/SAT tools; they are not a general startup termination or network progress proof. Local XC7 counts are a capacity screen, not native implementation measurements.


## Host rectangle input

The same `emit_protocol_network.sh` command connects a single ordinary rectangle ingress. Declare one to four topology targets, each with explicit nonempty schemas and recipients. For example:

```erlang
ingresses => [{host, {rectangle, [3,2]}, [
    {cells, [work], [{actor,a,{at,[0,0]}}, {actor,b,{at,[2,1]}}]},
    {first, [work], [{actor,a,{at,[0,0]}}]}
]}]
```

`hls_protocol_transport:write/2` calls `hls_protocol_ingress:plan/1` on its freshly compiled bundle. `hls_protocol_schema:domains/2` derives each target's complete header/length/padding masks from the recipients' ordinary source codecs. All recipients of one target must agree on those encodings and the ordered source field names/types; equal masks alone cannot establish schema compatibility. Unsupported codecs, ambiguous recipients, missing schemas and unsupported shapes reject before hardware emission. The shared schema module also encodes startup records; it does not infer a domain from fixture traffic or source-state invariants.

`xls_protocol_network:write/2` calls `xls_protocol_ingress:write/2` to emit source-bound constant tables. The static parametric `protocol_ingress.x` performs decoding and the registered transition. The network wires its held frame into the addressed receivers' ordinary host inbox slot, and each receiver's committed `take` bit back to that recipient's pending bit. `accepted` is only reservation and must never retire a command. All behavior is DSLX; Verilog remains the mechanical pin adapter.

The network exposes `ingress_data[193:0]`, `ingress_valid`, `ingress_ready` and `ingress_fault`. Data uses the existing flattened `hls_spatial_router::SpatialFrame`: inclusive rectangle `(x0,y0,x1,y1)`, two-bit target selector in declaration order, then the ordinary `axis::Frame` struct. It is **not** the actor-facing 128-bit bit codec with a rectangle prepended; `axis::bits_from_frame` supplies that conversion. Dimensions are 1..65536. Bounds, target, schema header, length and zero padding must all be canonical. All represented payload values remain admissible at this boundary; source callbacks still determine semantic failures.

An accepted canonical command registers one immutable 128-bit frame and one pending bit per selected actor. Recipients consume independently, preserving host order at each actor without claiming atomic broadcast. The boundary accepts no later command until all selected recipients commit source `consume`; reservation, publication stalls, postponement and source failure retain the affected bit. A valid empty selection completes without delivery. There is no refill on the last-consume edge. Malformed accepted input delivers nothing and latches `ingress_fault`, blocking admission until shared reset. Reset cancels the pending command and fault together with all owner/transport state.

Admission opens only after `startup_done`; internal traffic remains active during startup. This is one outstanding host command, **not** an unbounded mailbox: a postponed command can block a later host command needed to wake it. Applications must establish their own finite sequencing and capacity/progress obligations. The command makes no independent-device reset or live-board claim and keeps `eligible: false`.

The ingress adds `128 + A + 1` logical state bits for A elaborated actors; unaddressed pending bits can be pruned. Each addressed receiver adds one host slot after its capture and startup slots, recorded in `inbox.host`. That slot extends the existing reservation/postponement/release masks and may widen the cursor; it adds no payload copy. `network/manifest.json` retains the checked ingress tables, state budget and exact generated component hashes. Frame-width parametrization remains a separate compiler/adapter task.

`python3 tools/test_protocol_ingress.py XLS_ROOT FRESH_OUTPUT` builds two actual source recipients plus a feedback relay. Its finite public-pin scoreboards exercise point/broadcast/empty selections, two targets, source postponement and real feedback, per-recipient ordering, independent output stalls, three reset interruptions, two complete incarnations, eight malformed commands and canonical source failure. Early-retirement and live-frame-bypass controls must fail. Combinational SAT quantifies all finite three-recipient state/input patterns for retirement, admission, reset and malformed behavior, and all finite generated fixture state/input patterns for the registered host-input cut, plus every 194-bit command for the fixture’s two-target geometry and ordinary ABI; a false retirement control yields a counterexample. These checks trust source extraction, XLS and Yosys/ABC/SAT. They are finite witnesses and specified combinational properties, not arbitrary-program refinement or application admission. The whole-fixture XC7 screen is local synthesis, not native implementation performance.
