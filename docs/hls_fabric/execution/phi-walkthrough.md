# Phi: from Erlang source to a running application

This walkthrough follows the maintained periodic repetition example through the `source_protocol` backend. Six sites are split into two roles of three sites each. Each role contains data, syndrome and Phi actors; “3+3” therefore means nine logical actors per role, not three actors per FPGA. The same Erlang actors also run on BEAM. The topology, physical placement, hardware build and live attachment are separate objects with separate lifetimes.

The commands below build and emit source locally. XLS compilation is an explicit next step. Programming two boards requires a matching board shell and transport; the source emitter does not provide a universal FPGA installer. The older [XC7 repetition link](../../../platforms/xc7/docs/repetition-link.md) uses channel schedulers and direct Ethernet, so its board results do not establish deployment of this source-protocol bundle.

## 1. Application source and logical topology

The application lives in [hls_phi](../../../apps/hls_phi/README.md). Its three actor families are:

| Source | Role in the repetition experiment |
| --- | --- |
| [`phenom_line_data_cell`](../../../apps/hls_phi/src/phenom_line_data_cell.erl) | Maintains a data site's Pauli state and reproducible phenomenological noise; answers neighboring checks and final readout. |
| [`phenom_line_syndrome_cell`](../../../apps/hls_phi/src/phenom_line_syndrome_cell.erl) | Collects the two neighboring data replies and supplies noisy syndrome measurements. |
| [`phi_line_cell`](../../../apps/hls_phi/src/phi_line_cell.erl) | Exchanges local field values, performs the configured diffusion steps and reports corrections/status. |

The line wrappers include shared application bodies from `apps/hls_phi/include/`. [`phi_repetition_topology`](../../../apps/hls_phi/src/phi_repetition_topology.erl) declares the families, startup values and routes around the periodic line. It also defines how a decoder correction maps back to a data-site Pauli update. This is explicit application structure: the compiler does not run arbitrary `spawn` calls and infer a hardware graph from the resulting process tree.

The actor API describes typed state, callbacks and message records. Source preparation uses the application's include paths and preprocessing context. It reads Erlang source, not BEAM machine instructions; BEAM loading is used for trusted constructors, type providers and the ordinary host implementation. Hardware support is a checked subset of Erlang and the actor behaviors, not an implementation of the whole ERTS runtime. [Compiler actor semantics](../../actor-compilation.md) describe that boundary.

Noise is part of the actor graph. It is not an unrelated host-side stream that happens to resemble decoder input. The finite host loop configures its cutoff and feeds decoder corrections back into the same data actors. The [repetition model](repetition-code.md) explains the arithmetic and distinguishes this correction/readout loop from the scheduler throughput fixture, which observes outputs without feeding corrections back.

## 2. Choose an execution model and placement

From the umbrella checkout, with OTP 28 and rebar3 3.24.0:

```sh
rebar3 release -n hls_examples
_build/default/rel/hls_examples/bin/hls-repetition --help
_build/default/rel/hls_examples/bin/hls-repetition \
    --width 6 --split 3 --output _build/repetition-source
```

Use a fresh output directory. The example release includes computation, communication and target applications plus both decoders and their source inputs. It runs neither synthesis tools nor a fabric node. The generic `hls` build release excludes the decoders; the legacy-named `hls_fabric` runtime release excludes all synthesis and target applications. See [build packaging](../building.md).

[`phi_protocol_cli`](../../../apps/hls_phi/src/phi_protocol_cli.erl) calls `phi_protocol_config:repetition(6, #{split => 3})`. That function returns `{deployment, Config}`. The frontend submits `#{backend => source_protocol, kind => deployment, configuration => Config}` to `hls_build:plan/1`, then writes the resulting plan. The backend is chosen by this build request; the logical actor definitions do not choose it.

The preset establishes these concrete choices:

- Eighteen logical actors: six each of `data`, `syndrome` and `phi`.
- Role `0` owns sites 0–2 of all three families; role `1` owns sites 3–5. These role identifiers are not board serial numbers.
- Host address `1`, with services `7` and `17` for the two roles.
- A host relay bound of eight crossing records, 128 commands and 128 events.
- Default ordinary actor frames: a 32-bit header and three 32-bit payload words. Compact captures and bridge envelopes have their own layouts.

The example frontend supports widths 2–16. Its split form excludes mixed BEAM/native placement, process inspection and shared arithmetic. These are checked restrictions of this preset, not claims that all those combinations are implemented elsewhere. Other build requests can select ordinary `frame_payload_words`; fixed bridge envelopes still impose their own limits. [Frame capacity](../building.md#ordinary-frame-capacity) explains the distinction.

For inspection without creating output, use the same configuration in an Erlang VM with the example release on its code path:

```erlang
{Kind, Config} = phi_protocol_config:repetition(6, #{split => 3}),
Plan = hls_build:plan(#{backend => source_protocol,
    kind => Kind, configuration => Config}),
hls_build:inspect(Plan, summary),
hls_build:inspect(Plan, placement),
hls_build:inspect(Plan, schedule).
```

These are views of one complete checked plan. Retain it unchanged in process while its source modules remain available; it is not an ETF format to load at runtime. `hls_build:write(Plan, FreshDirectory)` renders this plan without repeating source preparation.

## 3. What planning and lowering do

The source deployment takes this path:

```text
phi_protocol_config:repetition/2
  → hls_build:plan/1
    → hls_source_build:plan/2
      → hls_protocol_deployment:plan/1
        → hls_protocol_transport:prepare/1       one source preparation
        → checked actor-to-role ownership
        → hls_protocol_transport:plan/2          one placement per role
        → hls_protocol_bridge:plan/2             one bridge per role
        → hls_protocol_routing:plan/1            checked crossings
        → application record/rectangle bindings
```

`hls_protocol_transport:prepare/1` loads declared sources, invokes the topology constructor and prepares each distinct actor implementation once. It validates publication, capture, startup and optional protocol-model annotations against that source inventory. Both roles use this retained preparation. Placement then checks complete, disjoint actor ownership and derives each role's receiver, inbox and crossing layouts. These checks do not themselves establish progress or application correctness.

There are three useful intermediate levels:

| Representation | Authority and purpose |
| --- | --- |
| Compiler actor program (`xls_actor_program`, with its state-machine plan) | Retains typed callback semantics, source provenance and effects for reuse by different execution backends. |
| Fabric placement and composition plans | Fix actor ownership, capture/inbox layouts, routes, clock boundaries and physical interfaces for the chosen backend. |
| Compiler `xls_dslx` nodes and emitted DSLX | Express target syntax. XLS subsequently parses/types the DSLX and creates its own optimization/scheduling IR. |

A target syntax tree cannot replace the actor semantics or the placement decisions. Conversely, the actor program does not specify a board link, RAM port count or complete generated clock transition. The [build guide](../building.md#following-the-implementation) describes the retained authorities and their consumers in more detail.

For this backend, `hls_local_actor:prepare/3` calls `xls_actor_program:from_file/3`, which retains the `xls_statem_plan` source model and the closed callback specification produced by `xls_statem_lower`. Source preprocessing, reachable helpers, records and callback normalization are compiler responsibilities. This path does not pass through the standalone `xls_parse` facade. Then `xls_activation_codegen` renders the ordinary activation functions; `xls_local_owner` supplies the clocked owner. That owner retains the actor's committed state, pending action and publication batch, plus a reservation for the selected head. The message payload remains in its capture/startup slot; the inbox retains the selection mask rather than copying that payload into actor state. `hls_protocol_capture` and `hls_protocol_inbox` plan typed storage/selection, while `xls_protocol_inbox` connects those interfaces to the lowered actor. Known constants may be reconstructed instead of stored in every compact capture; the checked frame domain and source bindings justify those omissions.

The network transition observes old state, selects work, advances receivers and commits transport. A source effect can publish to several recipients while each recipient retains its own progress. Postponed messages and pending publications therefore need explicit ownership; they are not equivalent to a single ready/valid FIFO between callback functions. `accepted`, source consumption, payload release, physical write completion and a crossing acknowledgment are different events. Releasing one resource does not imply all the others may be reused.

Most behavior is generated DSLX or shared DSLX support. Small `sv_protocol_*` adapters connect packed pins and clocks to those generated interfaces. Physical FIFOs, board I/O and clock-domain crossings remain separate RTL/platform responsibilities. The [source-protocol guide](../source-protocol.md) describes the owner and transport contracts.

## 4. Source bundle, XLS and hardware artifacts

Emission renders the roles and records their descriptors and support dependencies in a fresh directory. Target-owned `hls_artifact_bundle` supplies the shared packaging format. Useful entries include:

| Entry | Consumer |
| --- | --- |
| `source-build.json` | External build driver: hashed inputs, compilation units, import paths, required schedules and RTL lists. |
| `deployment.etf` | Versioned, canonical runtime artifact: roles, identities, routes, limits and application codecs. This is not the in-process compiler plan. |
| `role0/bridge/bridge.x`, `role1/bridge/bridge.x` | Two independent bridge compilation units, each with top `bridge_clock`. |
| `support/` and per-role metadata | Copied compiler/Fabric/target/application support and bindings needed by this bundle. |

The bridge units each use one pipeline stage with input/output flops disabled, as required by their sampled feedback clock. Do not retime that boundary by adding arbitrary codegen flags. Other composition kinds can contain differently scheduled units. A unit delay model describes an XLS schedule, not a measured FPGA clock period.

With a compatible XLS installation containing its tools and DSLX standard library:

```sh
_build/default/rel/hls_examples/bin/compile-source-build \
    --dry-run /path/to/xls _build/repetition-source
_build/default/rel/hls_examples/bin/compile-source-build \
    /path/to/xls _build/repetition-source
compiled=$(cd _build/repetition-source/compiled && pwd -P)
```

The preview verifies input and tool identities and prints the exact commands without executing XLS. The actual driver converts DSLX to XLS IR, optimizes it, schedules it and generates RTL. Both roles use module name `protocol_bridge_core` in separate compilation units; they are independent role builds, not two identically named modules to concatenate into one Verilog namespace.

The source bundle stays unchanged. `compiled` selects a complete immutable output release containing the retained metadata, per-unit IR/RTL, `commands.json`, `compiled.json` and per-role `files.f`. Resolve that symlink once before consuming several files. A failed attempt preserves its inputs/logs and the previous successful release; [the external build contract](../building.md#optional-external-compilation) covers caching and retries.

This is the end of the generic toolchain's hardware build boundary. To deploy physically, supply a shell that connects the role's framed ports, clocks and reset; constrain and implement it for the chosen FPGA; check area/timing; program the board; and expose compatible host I/O. Use the descriptor from the same compiled release when attaching. Existing simulator fixtures do this connection to RTL ports, and platform experiments supply particular shells; neither is a universal board implementation. No ordinary build command establishes routed timing, resource fit or live-device equivalence.

For a complete local simulator setup, the optional integration driver supplies the RTL peers, brokers and retirement sequence:

```sh
python3 apps/hls_phi/tools/test_protocol_deployment.py /path/to/xls /path/to/fresh-stage
```

It builds both roles and compares two fresh incarnations with the ordinary-BEAM reference in [`phi_protocol_repetition_fixture:oracle/2`](../../../apps/hls_phi/test/phi_protocol_repetition_fixture.erl), including independent stalls, correction feedback and readout. This is a larger explicit experiment outside routine CI; `--area` additionally requests a local synthesis screen. Neither mode establishes a live-board result. The attachment skeleton below is the production API used inside that setup.

## 5. Attach roles and run the host loop

The maintained two-role source deployment has this live shape:

```text
Phi host loop
  → hls_protocol_stream (one command/event owner)
    → hls_fabric broker for role 0 → role 0 framed ports
    → hls_fabric broker for role 1 → role 1 framed ports
       cross-role packets return through the same host relay
```

Here `hls_fabric` is the broker module supplied by the umbrella's `hls_runtime` application. That same runtime application supplies deployment streams, live routing and optional virtual-node services; the `hls_fabric` application is process-free communication synthesis. Runtime operations use retained descriptors and codecs; they do not call the compiler or load an Erlang source file to discover the wire format. Type-provider implementations still follow ordinary Erlang code loading; a descriptor is not a promise to freeze all provider code or detect every semantic upgrade mismatch.

The following is an attachment skeleton, after the caller has opened one fresh compatible broker per role and reset/brought up both hardware roles. `Broker0`, `Broker1`, `Session0` and `Session1` are caller-supplied values, not values inferred from the build:

```erlang
{ok, Deployment} = hls_deployment_artifact:load(
    filename:join(CompiledDirectory, "deployment.etf")),
Brokers = #{0 => Broker0, 1 => Broker1},
Sessions = #{0 => Session0, 1 => Session1}, % distinct fresh nonzero sessions
{ok, Stream} = hls_protocol_stream:start_application(Deployment, Brokers, Sessions),
Result = phi_protocol_repetition:run(hls_protocol_stream, Stream, 6, 8, 123, 120000).
```

Broker construction depends on the transport. FIFO-based simulation uses `hls_fabric:start_link(TxPath, RxPath, #{rx_route_limit => 1})`; those paths must already connect to the intended role. The runtime does not start a simulator, open an arbitrary network board, or program an FPGA on behalf of `start_application/3`.

The stream validates routes, binds each role's identity and session, and serializes attachment. A typed rectangle command is encoded from the retained application schema, then delivered in order to its recipients. Admission (`{ok, 1}`) means the stream has accepted the command; it does not mean both roles changed atomically. Aggregate `started` means every participant acknowledged start, not that their clocks advanced simultaneously.

Cross-role messages are encoded and forwarded by the host relay, preserving the supported per-sender ordering and credit rules under independent stalls. The source bridge's protocol acknowledgment, the broker's receive credit and the completion of a physical write have distinct lifetimes. The stream retains at most 267 records for this preset: 128 commands + 128 events + 8 crossings + two held broker receipts + one writer. ERTS mailboxes and OS buffers are outside that count. Read [stream ownership](../source-protocol.md#host-owner-decisions) before changing queue bounds or retry behavior.

`phi_protocol_repetition:run/6` performs a finite application exchange:

1. Set noise cutoff eight through the ordered rectangle control lane, then start the deployment.
2. Consume decoder corrections/statuses, map every correction to its data site and enqueue the corresponding Pauli update.
3. Wait for a common step whose status is quiet/empty at every site, using correction-before-status order from each sender.
4. Send an X-basis query with request id 123 after the admitted corrections; collect exactly one reply per data site.

It returns the fence, source events, corrections and sorted readout. One timeout bounds setup through readout; a timeout or malformed event aborts rather than replaying a possibly partially delivered command. The helper currently accepts cutoff below 512. Running a different finite experiment longer is an application/test change, not evidence that the measured throughput estimate has already been sustained. This loop provides a finite behavioral witness, not a threshold, convergence or unbounded-progress proof.

The quiet/empty application fence is not global transport quiescence. On completion, obtain each broker lease from `hls_fabric:info/1`, stop the stream with `hls_protocol_stream:stop/1`, then stop every broker with `hls_fabric:stop/1`. Close any simulator-side FIFO endpoints and call `hls_fabric:await_closed/2` for every lease before resetting/reusing the roles. [`phi_protocol_deployment_live`](../../../apps/hls_phi/test/phi_protocol_deployment_live.erl) shows the concrete simulation lifecycle. A participant or client failure retires the whole deployment; uncertain writes must not be replayed into it. A new activation needs coordinated reset and fresh sessions. Independent board restart and arbitrary live migration are not supported by this attachment contract.

## 6. Inspection and ERTS-facing services

This split preset does not enable process inspection. The unsplit `--inspect` variant emits a matching process catalog, and other supported frontends expose their own checked observation bindings. Use the manifest-backed debug APIs where supplied; the presence of state in a generated module does not make arbitrary simulator-private signals a stable interface. [Profiling](../profiling.md) distinguishes reusable timing-graph tools from the scheduler-specific captures that currently feed them.

A fake ERTS node is optional. `hls_node` adapts supported device services to external PIDs, names, calls/casts and monitor lifetimes; it is not involved merely because `hls_protocol_stream` sends a frame. Direct service attachment, scheduler actor addressing and mixed BEAM/native source placement each have their own bindings and supported operations. [Device sessions](../device-sessions.md) and [actor addressing](../actor-pids.md) describe those interfaces; there is no general remote `spawn` or full ERTS implementation in the generated role.

## Where to make a change

| Intended change | Owning layer |
| --- | --- |
| Decoder rule, noise model, logical routes or finite correction policy | `apps/hls_phi`: actor source, topology and host loop. |
| Supported Erlang construct, typed record packing or callback lowering | `hls_compile`; runtime packing and transport contracts live in `hls_runtime`. |
| Physical ownership, captures, scheduling, bridges or deployment composition | `apps/hls_target`; preserve checked source and wire contracts. |
| Live command ownership, host relay, recovery or virtual-node behavior | `apps/hls_runtime/src/fabric/runtime/` and `apps/hls_runtime/src/fabric/wire/`, consuming retained descriptors. |
| DSLX optimization/scheduling/code generation | XLS, after the project's source and scheduling contracts are fixed. |
| Pins, CDC, board shell, constraints, programming and device transport | The relevant platform integration. |

The concrete program, placement, source bundle, compiled release and live session should remain distinct in both code and documentation. That separation lets compiler development use small source examples, lowering development inspect a plan without a board, and runtime development exercise retained bindings without bringing the compiler into the deployed process.
