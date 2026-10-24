# Building the backend

Use OTP 28, rebar3 and Python 3.12 or newer. From this repository:

```sh
python3 tools/build.py
python3 tools/build.py eunit
python3 tools/build.py dialyzer
```

The wrapper prepares the pinned `erl_hls` dependency, then passes its arguments to rebar3. The first invocation fetches the public commit pinned in `tools/compiler/manifest.json`; subsequent invocations verify and reuse its sources. No patch is applied. No developer checkout is edited. For an offline first build, supply a local Git repository containing that commit:

```sh
python3 tools/prepare_compiler.py --source /path/to/erl_hls
```

Prepared sources live in disposable `_build/compiler/`, selected by `_checkouts/erl_hls`. An existing developer-selected checkout is left alone and reported as a conflict. Modified prepared sources are rejected: preserve intentional edits before deleting that cache. Removing `_build/` is safe; the next invocation reconstructs the dependency.

The public compiler supplies runtime reduction membership, contribution lowering, live actor observations and native XLS channel scheduling options. Collector ownership and hardware generation live in this repository's `src/backend/` and `priv/xls/templates/` files.

## Erlang build profiles

Tools select the same rebar profile that they compile. Production emitters use `default`; drivers that call compiled test fixtures use `test`. A missing profile is an error with a build instruction. An old `_build/test/` directory cannot select test beams for a production emitter. Checkout beams take precedence over dependency beams within the selected profile.

For a shell session, compile first and select explicitly:

```sh
python3 tools/build.py as test compile
source tools/backend_env.sh test
```

Use `default` after an ordinary build. Sourcing this helper replaces `ERL_AFLAGS` with the selected code paths; keep unrelated VM options in `ERL_FLAGS`. Python callers use `backend_paths.erlang_paths(profile)` for argument lists or `erlang_environment(profile)` for a child environment. Importing these helpers does not modify the environment or Python module path.

`backend_commands` owns shared hashing and bounded command execution. It does not import fixture drivers or require compiler sources. Compiler-dependent tools explicitly import `compiler_paths`; that separate bootstrap still exposes the selected compiler's unpackaged Python tools on `sys.path`. Python packaging of those compiler tools remains separate work.

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
