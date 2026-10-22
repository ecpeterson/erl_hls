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
    → fresh ordinary source compilation + topology normalization/elaboration + inventory
    → capture:plan/2 + transactions:plan/2
    → source:plan/3 (projection + codec)
    → inbox:plan/1 → fabric:plan/2
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

## Transport checks

```sh
bash tools/test_protocol_codecs.sh /path/to/xls /path/to/fresh-codec-stage
bash tools/test_protocol_transport.sh /path/to/xls /path/to/fresh-transport-stage
```

The connected finite witness compares full reconstructed frames with the ordinary compiler's independently generated entry decoder. It exercises conditional layouts, unaligned and constant fields, independent recipient stalls, sender ordering across ports, postponement, leases and two resets over at most 2,000 cycles. Negative builds reject missing sources/routes, excess population, duplicate sources, unsupported coupled fanout and existing output directories. Real N2/N3/N6 repetition and D3 noise transports are emitted and elaborated; their actor controllers are not simulated by this check. These are finite RTL witnesses and structural checks, not an unbounded progress proof, QEC validation or physical measurement.
