# Building the backend

Use OTP 28 and rebar3 3.24.0. Erlang compilation and source emission require neither Python nor XLS:

```sh
rebar3 compile
rebar3 eunit
rebar3 dialyzer
rebar3 release
_build/default/rel/hls/bin/hls-fabric --help
```

`rebar.config` and `rebar.lock` select the public `erl_hls` revision. Rebar fetches and compiles it normally. For deliberate compiler development, put its checkout in `_checkouts/erl_hls`; rebar gives that explicit override precedence. Checkouts are not locked, so remove the override when qualifying the pinned dependency. There is no second compiler manifest, Python dependency preparer or managed checkout cache. Existing legacy caches are left untouched and can remain explicit overrides until their owners retire them.

The release directory `_build/default/rel/hls/` contains the CLI, resolved BEAM dependencies, headers, templates and example sources. Copy the **whole directory**, not just `bin/hls-fabric`, to use it elsewhere with a compatible OTP 28 runtime. `include_src` retains the example sources that the HLS compiler consumes. The tiny shell launcher supplies the release's fixed library directory; all argument handling, configuration and source compilation run in Erlang. It does not start a fabric node or invoke rebar at runtime.

The compiler itself owns `hlsc` for ordinary actor lowering, source preprocessing, the shared bundle schema and optional XLS invocation. This project owns `hls-fabric`, deployment roles, adapters and their required schedules. Repetition settings live in the example frontend, not either generic command.

## One build boundary, two execution models

Select the backend in the build request. The application declares actor semantics and logical routes; its backend configuration declares physical ownership and the supported schedule.

| Backend | Configuration | Generated boundary |
| --- | --- | --- |
| `source_protocol` (default) | Source composition plus `--kind` | Source-bound owners, compact captures and connected application/deployment adapters. |
| `channel_scheduler` | Source modules, topology and `placement`; optional `schedule` | Dedicated actors and shared executors connected by ordinary ready/valid channels. |

These are different checked execution models. A scheduler placement is not a source-protocol configuration, and choosing a backend does not translate unsupported constructs. `source_protocol` accepts kinds `transport`, `network`, `boundary`, `application` (default), `bridge`, `deployment` and `mixed`. `channel_scheduler` has one topology boundary and rejects `--kind`.

The two-counter example uses the same actor and topology with both backends. Run from the repository root after `rebar3 release`; choose fresh output directories:

```sh
_build/default/rel/hls/bin/hls-fabric plan --backend source_protocol --kind application \
    --config src/examples/counter/source.config --stage profile
_build/default/rel/hls/bin/hls-fabric emit --backend source_protocol --kind application \
    --config src/examples/counter/source.config --output _build/counter-source
_build/default/rel/hls/bin/hls-fabric plan --backend channel_scheduler \
    --config src/examples/counter/scheduler.config --stage profile
_build/default/rel/hls/bin/hls-fabric emit --backend channel_scheduler \
    --config src/examples/counter/scheduler.config --output _build/counter-scheduler
```

`hls_counter_example` owns two independent totals, addressed through one rectangular ingress and reported on separate outputs. `source.config` asks for a framed native application; `scheduler.config` leaves both counters as dedicated channel actors, with no shared-executor group or external state/mailbox RAM. Neither command runs a simulation. Both produce the compiler-owned `source-build.json` bundle consumed by the same [external compilation command](#optional-external-compilation). Component and application tests use this public emission/compilation boundary too; they add their own bounded execution assertions.

To share one executor, use the same actor/topology with the alternative RAM-backed placement:

```sh
_build/default/rel/hls/bin/hls-fabric plan --backend channel_scheduler \
    --config src/examples/counter/scheduler-ram.config --stage placement
_build/default/rel/hls/bin/hls-fabric emit --backend channel_scheduler \
    --config src/examples/counter/scheduler-ram.config --output _build/counter-scheduler-ram
```

This variant selects `block_ram` for both state and mailbox storage. Its core exposes RAM ports and emits the connection fragments described below; an enclosing shell must connect the physical RAMs.

Both configurations are trusted Erlang maps, or filenames containing exactly one map. Paths are relative to the caller's working directory, including source paths inside a configuration file. Add `dslx_path => [Directory, ...]` for application-provided DSLX imports. The output itself must be absent; missing parent directories are created. Backend planning and rendering finish before output is created; filesystem or support-packaging failures can retain partial output. Later scalar options override earlier values, including backend, output/configuration paths, builder kind, plan stage/format and diagnostic format; flags may repeat. Errors return nonzero. Expected input failures name their stage, diagnostic code and relevant field/source/actor/role. `--diagnostics json` emits the same diagnostic as JSON on stderr; `HLS_DEBUG=1` adds the original stack. Unexpected exceptions always retain their class, reason and stack so compiler bugs remain visible.

The common Erlang API follows the same path:

```erlang
Request = #{backend => channel_scheduler,
    configuration => "src/examples/counter/scheduler.config"},
Plan = hls_build:plan(Request),
Profile = hls_build:inspect(Plan, profile),
Descriptor = hls_build:descriptor(Plan),
hls_build:write(Plan, "/path/to/fresh-output").
```

For source protocol, use `#{backend => source_protocol, kind => application, configuration => Config}`. `hls_build:plan/1` also accepts a trusted filename containing that whole request. Retain plans unchanged in process with source modules loaded; they are not saved-artifact input formats. Planning loads trusted source and invokes its topology constructor. Source-protocol planning retains checked structure for later rendering; scheduler planning also retains generated DSLX. Neither creates output or invokes XLS, and writing either plan does not recompile source.

Low-level scheduler callers prepare `Generation = xls_shared_topology_dslx:plan(Topology, Placement)` once. `artifact_requirements/1`, `descriptor/1` and `emit/1` consume that plan; `analysis/1` supplies its checked scheduler, profile and interface catalog to `xls_scheduler_ram_v:bindings/3`. `xls_scheduler_debug:projection(Generation, Artifacts)` uses the same ownership, frame layout and observation options. These retained consumers do not reload actor source or repeat placement analysis. A fresh plan still checks current actor interfaces; logical topology validation and actor compilation remain separate stages. Compact family loops and materialized instance graphs retain their distinct representations.

`xls_shared_machine_layout` defines the complete packed actor row, including optional reduction, gather, continuation and retained-reply storage. Its typed fields drive the generic struct codec, RAM widths and observation offsets. Projected data is reconstructed using the selected actor slot and phase; external gather payload RAM remains separate from the row, which stores only gather progress in that mode. Local actor descriptors report the same complete width in `machine_layout.width` and `machine_bits`.

`hls_source_build` and `hls_scheduler_build` own their backend-specific checks. The scheduler configuration requires `sources`, `topology` and `placement`; `schedule`, `dslx_path` and `frame_payload_words` are optional. Declare every actor and topology-constructor module in `sources`. Placement uses `xls_shared_topology_profile`, including dedicated actors or shared scheduler groups, queue bounds and reduction placement. The shared counter example selects external block RAM for both state and mailbox storage. Schedule options are `pipeline_stages` (default 2), `initiation_interval` (default 1; explicit `tool_default` omits the XLS option), `delay_model` (default `unit`) and `executor_result_delay` (default 0). Result delay affects XLS scheduling, not pipeline depth or measured physical time. Unsupported fields fail instead of being ignored.

Source feedback clocks retain one stage with input/output flops disabled. The application gateway has its separate two-stage channel schedule with output flops enabled. Source configurations cannot override these contracts: adding registers to the feedback boundary changes the hardware transition. `hls_build_profile` owns the policies consumed by this public build frontend and standalone source owners. Its profile records the selected ordinary actor ABI, defaulting to a 32-bit header plus 96-bit payload. Compact captures and bridge envelopes have their own layouts. Actual XLS executable and library hashes are recorded by external compilation, not guessed during planning. Rebar's `default`/`test` profiles select BEAM dependencies; they are distinct from this hardware policy.

Packaging delegates relative paths, metadata, generated input hashes, DSLX entry points, RTL module names, required codegen options and RTL file lists to the compiler-owned `hls_artifact_bundle`. Support libraries and supplied import trees are copied into `support/`, so a completed bundle can move before external compilation. The recorded source configuration remains inspection data, not a rewritten portable source-recompilation recipe.

A scheduler bundle contains `scheduler/topology.x`, generated actor modules with `.x.json` sidecars containing their byte hash and allocated failure codebook, `profile.json`, and RAM binding/fragments under `ram/`. The dedicated-actor counter example needs no external state/mailbox RAM. With `block_ram` placement, the compiled core exposes its RAM channels; `wires.vh`, `application_ports.vh` and `instances.vh` describe their connection to the support RAMs. These fragments are for an application shell, not independently compiled RTL. The generic scheduler build does not invent a framed host gateway, board pinout or complete application wrapper.

`hls-repetition` remains an application-owned convenience frontend. It constructs native Erlang terms in `phi_protocol_config:repetition/2`, then uses the source-protocol builder. For example:

```sh
_build/default/rel/hls/bin/hls-repetition --width 6 --split 3 --output /path/to/fresh-repetition
```

Its placement, inspection and shared-arithmetic bounds are documented in [source protocol](source-protocol.md).

### Ordinary frame capacity

Both backend configurations accept `frame_payload_words => N` (`1..255`, default `3`). This is a build choice, not an application message-field width. The compiler-owned layout checks that all declared messages and startup values fit, and it determines ordinary frame ports, mailbox rows, projections and host codecs. Profiles and source bundles record the selected ABI; the bundled `frame_config.x` supplies the matching `axis::FrameN` alias to every hardware unit. Do not combine units or host plans from different frame layouts. The scheduler also accepts this field in its low-level placement profile; an explicit top-level value takes precedence.

Debug replies, SHA-256 identities, compact capture payloads and fixed bridge/rectangle envelopes remain independent. Framed adapters check their own envelope limits and zero padding before converting to the selected native frame. The legacy partition application gateway accepts at most eight ordinary payload words for events; its rectangle commands retain their separate three-word limit. Narrowing the ordinary capacity reduces canonical storage and interfaces; constant-eliding compact captures may already be narrower and need not shrink further. This is a representation choice, not a physical area or throughput claim.

## Inspecting a build

Use the same backend, configuration and source composition kind for planning and emission:

```sh
_build/default/rel/hls/bin/hls-fabric plan --kind deployment --config deployment.config
_build/default/rel/hls/bin/hls-fabric plan --kind deployment --config deployment.config --stage placement --format json
_build/default/rel/hls/bin/hls-fabric plan --kind deployment --config deployment.config --stage schedule
```

`plan` checks the entire selected build and prints a report without creating a bundle or invoking XLS. The default `summary` shows the units and roles or scheduler populations. `configuration` shows inputs and build context; `source` shows source identities and backend requirements; `topology` shows the logical graph; `placement` shows checked physical ownership; `composition` shows static interfaces and retained hardware wiring; `profile` shows backend, frame ABI and structured scheduling policy; `schedule` shows the exact retained compilation-unit recipes. These are views of one successful plan, not switches that bypass later validation. In-process callers use `hls_build:inspect(Plan, Stage)` to inspect repeatedly without preparing sources again.

Reports are diagnostic data, not serialized executable plans. JSON preserves tuples as `{"$tuple": [...]}`, maps with non-string or colliding keys as `{"$map": [[key, value], ...]}`, and non-text binaries as `{"$binary_hex": "..."}`. Atom keys and text binaries become ordinary JSON strings; atoms used in tagged map keys retain an explicit `$atom` tag. Every proper list remains an array, including Erlang character lists in the original configuration, so integer indices never change representation based on their values. Configuration field paths are explicit lists; source line/column locations are retained when the source pass supplies them. Configuration terms do not carry per-key locations, so those errors use the config filename and field path rather than inventing a line number.

The public source-build boundary rejects missing, unknown and malformed configuration fields before compiling sources. Semantic checks remain in their owning planners: overlapping ownership names the actor and roles, unsupported mixed routes name their actor/port/destination, and unsupported frame sizes name the source record and capacity. `hls_diagnostic:with_context/2` adds outer build context only to deliberately tagged diagnostics; it never converts a `badmatch`, `badkey` or unexpected provider exception into an input error.

## In-process build stages

The source transport builder separates preparation, placement, emission and writing:

```erlang
Program = hls_protocol_transport:prepare(SourceConfig),
North = hls_protocol_transport:plan(Program, #{native_actors => NorthActorIds}),
South = hls_protocol_transport:plan(Program, #{native_actors => SouthActorIds}),
Static = hls_protocol_transport:descriptor(North),
Generated = #{files := Files, result := Final} = hls_protocol_transport:emit(North),
hls_generated_files:write(Generated, "/path/to/fresh-north").
```

`prepare/1` loads the declared Erlang modules, executes the trusted topology constructor and retains one checked source snapshot. `plan/2` derives placement, owner interfaces and receiver layouts from that snapshot; its only options are `native_actors` and `arithmetic_groups`. Planning neither reads hardware templates nor renders owner or receiver modules. `plan/1` combines preparation and placement. Static descriptors retain source identities, layouts and the transport transition, without rendered actor DSLX or generated-byte hashes. Keep opaque plans unchanged in process with compatible provider type and encoding contracts; they are not serialized caches or saved-artifact inputs.

`emit(Plan)` renders from the retained source and layouts, reading templates and support libraries without rereading application source. A protocol builder returns `#{files => #{RelativeFilename => IOData}, result => BuildResult}` because it produces DSLX, pin adapters and manifests together. The final result adds hashes calculated from those bytes. `hls_generated_files:write/2` validates relative filenames, writes a fresh directory and returns `BuildResult`. Builder `write(Plan, Directory)` functions combine emission and writing. These stages create no temporary output directory.

Every protocol builder's `emit/1` and `write/2` also accepts a trusted source configuration map or a filename containing exactly one such map. These conveniences perform preparation and planning first, including source reads and trusted constructor execution. Source/include paths are relative to the caller's working directory, not the config file's directory. Saved ETF plans are not configuration inputs.

Configuration maps have per-builder types in `hls_source_config`: for example, `network()` describes source/placement/mode fields, whereas `deployment()` also requires device roles and queue limits. `:=` denotes a required map field and `=>` an optional one. Public loading functions additionally accept a filename; internal planning options are typed maps. A configuration is not the opaque checked `plan()` returned by a builder. Static descriptor types describe the checked interfaces; emitted result types add the identities derived from generated bytes. These specs support Dialyzer and code navigation; they do not replace runtime checks when consulting a configuration file or establishing semantic constraints such as disjoint ownership.

Network, boundary and bridge each expose `plan/2` over an existing transport placement and that layer's options:

```erlang
Boundary = hls_protocol_boundary:plan(North, #{activation => explicit_start}),
#{inputs := Inputs, outputs := Outputs, externals := Endpoints} =
    hls_protocol_boundary:descriptor(Boundary),
BoundaryFiles = hls_protocol_boundary:emit(Boundary).
```

These plans fix wiring, packed ports, endpoint ownership and state costs before hardware rendering. Network/boundary `inspection` is the mode (`none` or `process`) in the static descriptor; emission adds its catalog. `emit(Build, Options)` combines composition planning and emission, and `write(Build, Options, Directory)` also writes the files. Their bundle results retain the finalized transport descriptor alongside the composition manifest. Options cannot change the source snapshot or placement.

`hls_protocol_application`, `hls_protocol_deployment` and `hls_protocol_mixed` expose `plan(ConfigOrFilename)`, `descriptor(Plan)`, `emit(Plan)` and `write(Plan, Directory)` for complete compositions. Planning checks host codecs, external schemas and supported host routes against the same source snapshot and static interfaces. Descriptors expose the complete binding before attachment identities and support-library hashes exist; they are for build inspection, not runtime attachment.

A deployment prepares sources once, validates complete disjoint ownership and return endpoints, then checks every role's bridge layout and cross-role routing before rendering any role. `hls_protocol_deployment:routing(Plan)` returns the retained `hls_protocol_routing:plan()`; `roles/1` and `routes/1` inspect its checked ownership and paired crossing codecs without sessions or credits. Runtime attachment independently validates the serialized deployment when opening an incarnation. A validation or rendering failure leaves output absent; an I/O failure can retain partial output. These boundaries do not change XLS schedules, generated hardware behavior or admission policy.

### Following the implementation

Start at `hls_build:plan/1`. It selects `hls_source_build` or `hls_scheduler_build`; each owns preparation and lowering while `hls_build_profile` owns scheduling policy. For a source deployment, the complete path inside the selected backend is:

```text
hls_source_build:plan(deployment, Config)
  → hls_protocol_deployment:plan(Config)
    → hls_protocol_transport:prepare(CommonConfig)          one source snapshot
    → placement(Devices, Actors)                           checked actor → role ownership
    → hls_protocol_transport:plan(Program, RoleOptions)     once per role
    → hls_protocol_bridge:plan(Transport, BridgeOptions)    each role's composition
    → hls_protocol_routing:plan(Interfaces)                 checked cross-role routes
    → hls_protocol_application_binding:bind(...)            source record/host bindings
hls_source_build:write(Plan, Directory)
  → hls_protocol_deployment:emit(DeploymentPlan)
    → hls_protocol_bridge:emit(RolePlan)                    all role files in memory
  → hls_generated_files:write(...)
  → hls_artifact_bundle:snapshot/2, finish/3                support files and tool manifest
```

The internal authorities are deliberately small:

| Fact | Owner | Consumer |
| --- | --- | --- |
| Compiled source, whole topology and publication analysis | Transport `program()` | Every placement shares this snapshot. |
| Native receiver identity, source and inbox layout | One private transport receiver record | Static descriptors and emitted files derive from that same record; list position does not bind them. |
| Actor-to-role ownership | Deployment placement check | The application binding uses the checked map. |
| Eligibility, acquisition and release slices | Receiver inbox layout, joined to links during network planning | `xls_protocol_network` retains the checked connections for both offer and retirement rendering. |
| Host record fields and widths | Compiler `hls_records` queries | Application binding checks codecs against source records without inspecting Erlang AST tuple positions. |
| Serialized descriptors and generated identities | The composition's emitted result | Runtime attachment checks these separately; it never consumes private build records. |

For mixed placement, `hls_protocol_mixed:plan/1` derives native/host indices, binds host actor outputs and startup, then checks crossing codecs and command targets. It retains the same transport and bridge plans used by emission. A builder named `hls_protocol_*` owns source/placement checks; `xls_protocol_*` elaborates checked connections into DSLX. The clock transition itself lives in `protocol_network.x.in`: observe old state, select, advance receivers, then commit transport. Mechanical `sv_protocol_*` adapters only connect packed pins.

Hardware generation retains decisions before printing syntax. `xls_protocol_transport:plan/1` fixes source shapes, slot projections and structured observe/select/crossing/commit expressions; its renderer consumes those same expressions through the compiler’s `xls_dslx` nodes. Publication and heterogeneous capture algorithms live in `protocol_transport_source.x.in` and `protocol_transport_link.x.in`, with named state fields. The network plan separately retains actor order, inbox slices, arithmetic grants, sparse host retirement bits and activation faults. The source build’s `composition` view exposes role-indexed `transport_transitions` and, for a network build, `network_phases`.

For channel schedulers, `xls_shared_topology_dslx:plan/2` chooses the representation once. `xls_topology_scheduler_plan` prepares shared ownership, dense addresses, prepacked startup records, producer lanes, reduction capture and effect-window domains before rendering. The scheduler build’s `composition` view includes this `generation` descriptor. Fixed rectangle control and startup sender algorithms live in DSLX templates. Dedicated compact families retain the compiler renderer’s bytes; materialized topologies retain their physical lane graph. These explicit cases avoid implying that every backend already uses a common hardware IR.

These plans expose dependencies for inspection and focused tests; they do not prove generated hardware equivalent, establish progress or measure timing. Top-level declarations, concrete widths and heterogeneous field lists still require generation. The shared syntax nodes describe the transition expressions, not a parser or replacement for XLS’s typed IR.

The runtime route continues at [host owner decisions](source-protocol.md#host-owner-decisions); build ownership and live queue ownership are separate types and lifetimes.

## Optional external compilation

XLS execution is separate from source emission. Use another build system to consume `source-build.json`, or use the standard-library-only convenience driver with Python 3.12 or newer:

```sh
_build/default/rel/hls/bin/compile-source-build /path/to/xls /path/to/emitted-output
compiled=$(cd /path/to/emitted-output/compiled && pwd -P)
```

The release launcher delegates to the compiler-owned `compile_source_build.py` and shared `compile_xls.py` executor. For detached use, copy both scripts into one directory; keep the companion name `compile_xls.py`. They need only the Python standard library, emitted bundle and XLS (`ir_converter_main`, `opt_main`, `codegen_main`, `xls/dslx/stdlib`). Add `--dry-run` for a read-only JSON preview: it verifies frozen inputs and tool/stdlib identities and prints the exact per-unit schedules and commands. Relative command arguments, outputs and logs refer to the private source snapshot used during execution.

Compilation leaves the source bundle and `source-build.json` frozen. The default `SOURCE/compiled` symlink selects a complete immutable release; `--output` selects another managed symlink. Resolve it once before opening RTL or host metadata, as above. That release includes the source metadata and copied dependencies, per-unit IR/RTL and `commands.json`, `compiled.json`, and each role's `files.f`. Entries in `files.f` are relative to its parent directory; RTL paths in `compiled.json` are relative to the release root.

All units must finish before publication. A failure preserves the previous release and retains the private attempt's inputs, commands, logs and partial products. Repeating the command reuses completed stages after hash checks, including earlier units, and an unchanged success keeps the same release. `<output>.run.json` records the latest attempt and cache/execution costs. `--cache` selects a shared cache; `--timeout` bounds each XLS stage (default 300 seconds).

The executor preserves literal emitted schedules: sampled-clock source units use one stage with input/output flops disabled, while the shared gateway retains its two-stage channel schedule. These are interface contracts, not physical timing estimates. The manifest is a trusted build record. Emission and XLS compilation establish neither application admission nor hardware timing. The common build frontend resolves both backend profiles before emitting this manifest. Public source bundles, standalone source owners and prepared Snowflake/Phi experiments resolve policy through `hls_build_profile`. Prepared experiments retain their existing flat source/input manifests and use the profile sidecar described below; they share the external executor without pretending to be newly elaborated public source bundles.

## Prepared experiment policy

For experiment DSLX already emitted through a specialized frontend, resolve channel scheduling and completion storage without recompiling its sources:

```sh
_build/default/rel/hls/bin/hls-fabric profile --output /path/to/fresh-policy.json \
    --pipeline-stages 2 --initiation-interval tool_default \
    --delay-model unit --executor-result-delay 0 --completion-storage registers
```

This command only writes a fresh versioned JSON policy. It reads no source or XLS installation. Its defaults are two pipeline stages, initiation interval one, the unit delay model, zero result delay and register completion storage. Explicit `tool_default` omits XLS's initiation-interval option; it preserves an intentionally unspecified tool setting instead of silently treating it as one. Later options take precedence, as in `plan` and `emit`.

`hls_build_profile:experiment/1` owns the same policy for in-process callers. Its `prepared_source` placement label records that source elaboration and placement happened elsewhere; it does not invent a checked topology. The record contains the structured channel schedule, completion-storage legalization and the rendered codegen flags. External adapters retain that record with their source/tool evidence and consume its flags; `tools/backend_build_profile.py` is the thin emission/reading bridge. The detached reader needs only Python's standard library. This command cannot select or retime a sampled source-owner clock.

The Snowflake orchestrator emits this policy after source preparation; replay checks the same sidecar, literal schedule, placement assets and compiled RTL. The Phi source builder emits a default `phi_decoder_profile.build-profile.json` alongside its checked geometry and RAM inputs. Local orchestrators may emit another policy and select it with `compile_phi_decoder_profile.py STAGE XLS --build-profile POLICY`; the detached adapter consumes that file and no longer chooses stages, intervals or delay models. A nondefault `xc7_7030` model requires its separately hashed `--delay-table`; the Phi adapter rejects completion-storage legalization it does not implement. Copy `compile_phi_decoder_profile.py`, `compile_xls.py` and `backend_build_profile.py` with the emitted stage for detached compilation. None of those readers needs Erlang on the execution host.

These profiles describe the supported backend interfaces and prepared application builds. Isolated component tests, timing ablations and historical diagnostic scripts can still invoke XLS with an explicit experimental recipe; those invocations do not define another public backend policy. Source-shape transformations and transport/debug component generation remain separate from profile resolution.

## Experiment and diagnostic drivers

Experiment-specific simulation/report drivers still use Python and shell, with their own input and measurement policies. They are separate from the public build boundary above. Build their declared rebar profile before calling fixtures; `source tools/backend_env.sh test` selects a test build and `default` selects an ordinary build. The helper replaces `ERL_AFLAGS`; unrelated VM flags belong in `ERL_FLAGS`. These helpers are unnecessary for `hls-fabric`.

External Python drivers select a compiler when invoked, using their declared rebar profile or an explicit `--erl-hls` checkout. Compiler sources, Python helpers and BEAM files must come from that selection; a missing build is an error, with no fallback to a different profile. The shell helper also accepts an explicit checkout: `source tools/backend_env.sh test /path/to/erl_hls`. `ERL_HLS_ROOT` is an output of that selection, not an implicit Python override.

Compiler helpers live in the compiler's `erl_hls_tools` package. Fabric loads them in a namespace specific to the selected checkout, so two compilers can be used in one Python process without sharing helper modules. Importing the compiler package or production modules in `tools/` does not select a compiler or change `sys.path` or the environment. Shared build, artifact and finite-witness support is independent of test entry points; tests and experiment drivers call that support.

## Complete decoder example

Install Icarus Verilog (`iverilog` and `vvp`) on `PATH`. Provide an XLS bundle containing `ir_converter_main`, `opt_main`, `codegen_main`, `interpreter_main` and `xls/dslx/stdlib`:

```sh
python3 experiments/snowflake/actors/build.py --xls /path/to/xls --profile
```

This runs protocol checks, lowers the full actor graph, compiles it, verifies 128 sheets against frozen expected corrections, and produces profiles. Use `--sheets 8` for a shorter diagnostic run. Output defaults to a timestamped directory in the [external artifact archive](artifacts.md); `--output` selects another fresh directory.

The default configuration is `experiments/snowflake/actors/configurations/collector.json`. Add `--configuration experiments/snowflake/actors/configurations/indexed-snapshots.json` to place typed snapshot gathers in separate member storage and publish up to two independent effects per router clock. Both configurations use the ordinary actor compiler.

Profiles distinguish reservation-ticket acceptance, loader acceptance and executor acceptance, so moving a buffer cannot hide its waiting time. Older captures without a reservation observation show only the load-to-retirement interval.

Indexed profiles include ownership, missing-member and read/release observations, and join emitted effects through router and receiver handshakes to member stores. Donor expansion uses a compiled pure observer; `channel_probe.py --ancestry-evaluator interpreter` retains the independent interpreter diagnostic. `--profile-timeout` sets the per-command limit in seconds (default 7,200).

`tools/compile_backend.py SOURCE XLS --output OUTPUT --build-profile POLICY` compiles prepared topologies using the emitted policy. The profile’s executor-result budget is passed to XLS's native channel scheduling interface; it is expressed in the selected delay model's units, not a physical timing guarantee. Optional completion LUTRAM preserves FIFO depth, ports and latency while legalizing accepted payload writes. Unknown FIFO forms fail the build. These choices, source/tool hashes and postprocessing identities are recorded in the immutable release. Backend finalization runs on the private candidate before the common executor hashes its products and publishes; legalization failure keeps the previous release selected. Simulation and physical measurements consume that same release; no executor modules are transplanted between separate RTL builds.

`--optimizer-pipeline /path/to/pipeline.txtpb` selects an explicit XLS optimization pipeline in `tools/compile_backend.py`, the decoder build command and its RTL replay tool. The compiler freezes the configuration as `optimizer_pipeline.txtpb`, passes it directly to the actual optimizer, and records separate pipeline/tool hashes. No generated executable wrapper or alternate tool installation is involved; changing this input reruns optimization while allowing IR conversion reuse; later stages reuse only when their own inputs still match. Replaying a compiled image requires the same requested pipeline. With no option, the supplied tool's default policy is used. Pipeline files are tool-version-specific; qualify their area, timing and behavior before adopting them.

For local profile inspection, use a small window: `channel_profile.py --epoch N` defaults to focused output; `--focus-only` selects it explicitly. Both select summary records before constructing the activation/indexed overlays and apply the same window to JSON, Perfetto and SVG. Repeat `--actor V` to restrict receiver details while retaining common command/barrier context. Cut dependencies are counted separately from retained causal and resource edges; aggregate observation totals still describe the full recording. `--full-recording` explicitly requests the entire graph and can require substantial memory and storage. Focused rendering streams large summary arrays, but still retains channel/pressure logs and a thin activation/port index proportional to recording length; it is not a constant-memory reader for arbitrarily large captures. Prefer small captures or a process memory cap on local machines.

To investigate collection contention without rebuilding RTL, run `experiments/snowflake/actors/collection_communication.py --ancestry RUN/delivery-ancestry.json --output REPORT.json.gz`. It accepts losslessly compressed inputs, verifies capture hashes, and requires an exact baseline replay before trying receiver policies. Arrivals, actor transitions and row lifetimes stay fixed: reported collection gains are conditional, not round-speedup predictions. A violated producer capacity or missed consumer acquisition invalidates that trial; it does not establish a hardware deadlock. The eligibility decoder currently supports the healthy Snowflake snapshot protocol. Unmodeled controller stalls can cause baseline rejection; no counterfactuals are reported for a mismatched baseline.

`collection_placement.py --ancestry RUN/delivery-ancestry.json --output DIRECTORY` proposes equal-size groups from observed member traffic. It balances receiver demand before minimizing cross-group edges; unobserved traffic is outside its cost model. Pass its `vertex-order.json` to `run.py --vertex-order FILE` to measure the full application. The permutation assigns groups; normal slot normalization determines order within each group. Actor identities, logical routes and barrier membership remain unchanged. Compare simulation and physical results before adopting a placement.
