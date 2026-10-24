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

## Source toolchain

```sh
_build/default/rel/hls/bin/hls-fabric emit --kind application --config application.config --output /path/to/fresh-output
_build/default/rel/hls/bin/hls-repetition --width 6 --split 3 --output /path/to/fresh-repetition
```

`emit` accepts `transport`, `network`, `boundary`, `application` (default), `bridge`, `deployment` and `mixed`. Its trusted Erlang configuration is the corresponding builder's map; paths are relative to the caller's working directory. Add `dslx_path => [Directory, ...]` for application-provided DSLX imports. The output parent must exist and the output itself must be absent. Errors return nonzero and retain partial output; `HLS_DEBUG=1` includes the Erlang stack.

`hls-repetition` is a separate example frontend in `phi_protocol_cli`. It constructs native Erlang terms in `phi_protocol_config:repetition/2`, then calls the same `hls_source_build:emit/3` API as `emit`. Its placement, inspection and shared-arithmetic bounds are documented in [source protocol](source-protocol.md). It is an application example, not an application-specific branch of the compiler.

The direct API is `hls_source_build:emit(Kind, Config, Output)`. It calls the existing source builder, supplies fabric-specific unit schedules and delegates packaging to the compiler-owned `hls_artifact_bundle`: relative paths, emitter `metadata`, generated input hashes, DSLX entry points, RTL module names, required code-generation options and final RTL file lists. Shared DSLX libraries, pin adapters and supplied import trees are copied into `support/`; moving the emitted directory before external compilation is supported. `config.erl` records the original trusted source configuration for inspection; its source paths are not rewritten as a portable source-recompilation recipe. Native source-plan/deployment terms are trusted local artifacts.

## In-process build stages

The source transport builder has explicit preparation, placement and emission stages:

```erlang
Program = hls_protocol_transport:prepare(SourceConfig),
North = hls_protocol_transport:plan(Program, #{native_actors => NorthActorIds}),
South = hls_protocol_transport:plan(Program, #{native_actors => SouthActorIds}),
Descriptor = hls_protocol_transport:descriptor(North),
hls_protocol_transport:emit(North, "/path/to/fresh-north").
```

`prepare/1` loads the declared Erlang modules, executes the trusted topology constructor and checks one source program. `plan/2` derives a transport placement and its receiver artifacts from that program; its only options are `native_actors` and `arithmetic_groups`. Neither stage creates output files. Planning reads backend templates but does not reread application source. `plan/1` combines preparation and placement for a single build; `write/2` remains the convenience API that also emits. These opaque values are trusted in-process stages, not a serialized cache: retain them unchanged and keep their loaded source modules until the build finishes.

`hls_protocol_network:emit/3`, `hls_protocol_boundary:emit/3` and `hls_protocol_bridge:emit/3` consume the planned transport, renderer options and a fresh output directory. Their named results carry the transport descriptor alongside the emitted manifest, so application, mixed and deployment builders do not read their own ETF outputs back. Source/placement options cannot be changed through these emission APIs. ETF outputs remain available for inspection and host consumers.

A deployment prepares the source program once, validates complete disjoint ownership and return endpoints, and plans all roles before creating its output directory. This removes repeated source analysis per role; capture's independent source check still runs during preparation. Boundary/bridge checks, cross-role codec/relay checks and file writes still occur during emission, so later failures can leave partial output. This is not yet a dry-run API for an entire deployment. No XLS schedule, generated hardware behavior or admission policy changes at this boundary.

## Optional external compilation

XLS execution is separate from source emission. Use another build system to consume `source-build.json`, or use the standard-library-only convenience driver with Python 3.12 or newer:

```sh
_build/default/rel/hls/bin/compile-source-build /path/to/xls /path/to/emitted-output
```

The release launcher delegates to `erl_hls`'s `priv/tools/compile_source_build.py`, also packaged as a standalone command by the compiler. That driver needs only its script, the emitted bundle and XLS (`ir_converter_main`, `opt_main`, `codegen_main`, `xls/dslx/stdlib`). It verifies input hashes, runs each unit's conversion/optimization/codegen once, and writes command logs, `compiled.json` and a `files.f` per role. Required scheduling options belong to the emitted clock interface; they are not a physical timing estimate. Failed or partial compilations are preserved and cannot be silently retried in place. The manifest is a trusted build record, not an untrusted command-execution format. Emission and XLS compilation establish neither application admission nor hardware timing.

## Legacy test drivers

Existing simulation/report drivers still use Python and shell. Build their declared profile before calling fixtures; `source tools/backend_env.sh test` selects a test build and `default` selects an ordinary build. The helper replaces `ERL_AFLAGS`; unrelated VM flags belong in `ERL_FLAGS`. These helpers are unnecessary for `hls-fabric`.

Compiler-dependent legacy Python drivers still use `compiler_paths` to import the compiler's unpackaged Python helpers. Report-only helpers are independent of it. Porting the remaining older experiment drivers is separate from the source toolchain.

## Complete decoder example

Install Icarus Verilog (`iverilog` and `vvp`) on `PATH`. Provide an XLS bundle containing `ir_converter_main`, `opt_main`, `codegen_main`, `interpreter_main` and `xls/dslx/stdlib`:

```sh
python3 experiments/snowflake/actors/build.py --xls /path/to/xls --profile
```

This runs protocol checks, lowers the full actor graph, compiles it, verifies 128 sheets against frozen expected corrections, and produces profiles. Use `--sheets 8` for a shorter diagnostic run. Output defaults to a timestamped directory in the [external artifact archive](artifacts.md); `--output` selects another fresh directory.

The default configuration is `experiments/snowflake/actors/configurations/collector.json`. Add `--configuration experiments/snowflake/actors/configurations/indexed-snapshots.json` to place typed snapshot gathers in separate member storage and publish up to two independent effects per router clock. Both configurations use the ordinary actor compiler.

Profiles distinguish reservation-ticket acceptance, loader acceptance and executor acceptance, so moving a buffer cannot hide its waiting time. Older captures without a reservation observation show only the load-to-retirement interval.

Indexed profiles include ownership, missing-member and read/release observations, and join emitted effects through router and receiver handshakes to member stores. Donor expansion uses a compiled pure observer; `channel_probe.py --ancestry-evaluator interpreter` retains the independent interpreter diagnostic. `--profile-timeout` sets the per-command limit in seconds (default 7,200).

`tools/compile_backend.py` compiles other prepared topologies. Its optional executor-result budget is passed to XLS's native channel scheduling interface; it is expressed in the selected delay model's units, not a physical timing guarantee. Optional completion LUTRAM preserves FIFO depth, ports and latency while legalizing accepted payload writes. Unknown FIFO forms fail the build. These choices, source/tool hashes and postprocessing identities are recorded in the immutable release. Simulation and physical measurements consume that same release; no executor modules are transplanted between separate RTL builds.

`--optimizer-pipeline /path/to/pipeline.txtpb` selects an explicit XLS optimization pipeline in `tools/compile_backend.py`, the decoder build command and its RTL replay tool. The build freezes the configuration, records its hash and the original optimizer hash, and leaves the tool installation untouched. Replaying a compiled image requires the same requested pipeline. With no option, the supplied tool's default policy is used. Pipeline files are tool-version-specific; qualify their area, timing and behavior before adopting them.

For local profile inspection, use a small window: `channel_profile.py --epoch N` defaults to focused output; `--focus-only` selects it explicitly. Both select summary records before constructing the activation/indexed overlays and apply the same window to JSON, Perfetto and SVG. Repeat `--actor V` to restrict receiver details while retaining common command/barrier context. Cut dependencies are counted separately from retained causal and resource edges; aggregate observation totals still describe the full recording. `--full-recording` explicitly requests the entire graph and can require substantial memory and storage. Focused rendering streams large summary arrays, but still retains channel/pressure logs and a thin activation/port index proportional to recording length; it is not a constant-memory reader for arbitrarily large captures. Prefer small captures or a process memory cap on local machines.

To investigate collection contention without rebuilding RTL, run `experiments/snowflake/actors/collection_communication.py --ancestry RUN/delivery-ancestry.json --output REPORT.json.gz`. It accepts losslessly compressed inputs, verifies capture hashes, and requires an exact baseline replay before trying receiver policies. Arrivals, actor transitions and row lifetimes stay fixed: reported collection gains are conditional, not round-speedup predictions. A violated producer capacity or missed consumer acquisition invalidates that trial; it does not establish a hardware deadlock. The eligibility decoder currently supports the healthy Snowflake snapshot protocol. Unmodeled controller stalls can cause baseline rejection; no counterfactuals are reported for a mismatched baseline.

`collection_placement.py --ancestry RUN/delivery-ancestry.json --output DIRECTORY` proposes equal-size groups from observed member traffic. It balances receiver demand before minimizing cross-group edges; unobserved traffic is outside its cost model. Pass its `vertex-order.json` to `run.py --vertex-order FILE` to measure the full application. The permutation assigns groups; normal slot normalization determines order within each group. Actor identities, logical routes and barrier membership remain unchanged. Compare simulation and physical results before adopting a placement.
