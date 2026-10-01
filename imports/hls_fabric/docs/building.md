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

## Complete decoder example

Provide an XLS bundle containing `ir_converter_main`, `opt_main`, `codegen_main` and `xls/dslx/stdlib`:

```sh
python3 experiments/snowflake/actors/build.py --xls /path/to/xls --profile
```

This runs protocol checks, lowers the full actor graph, compiles it, verifies 128 sheets against frozen expected corrections, and produces profiles. Use `--sheets 8` for a shorter diagnostic run. Output defaults to a timestamped directory in the [external artifact archive](artifacts.md); `--output` selects another fresh directory. The checked configuration is `experiments/snowflake/actors/configurations/collector.json`.

`tools/compile_backend.py` compiles other prepared topologies. Its optional executor-result budget is passed to XLS's native channel scheduling interface; it is expressed in the selected delay model's units, not a physical timing guarantee. Optional completion LUTRAM preserves FIFO depth, ports and latency while legalizing accepted payload writes. Unknown FIFO forms fail the build. These choices, source/tool hashes and postprocessing identities are recorded in the immutable release. Simulation and physical measurements consume that same release; no executor modules are transplanted between separate RTL builds.
