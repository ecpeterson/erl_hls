# Incremental XLS compilation

`tools/compile_xls.py` compiles a prepared flat directory of DSLX modules through IR conversion, optimization, and RTL generation. It runs on Linux and macOS with Python 3.9+ and an installed XLS toolchain. The runner checks the three executables and standard library before compiling; it does not install or rebuild XLS.

For the generated `regsvc` example:

```sh
stage="$PWD/_build/xls_sim/regsvc"
bash tools/prepare_xls_sim.sh "$stage"
python3 tools/compile_xls.py "$stage/regsvc.x" "$ERL_HLS_XLS_ROOT" \
    --output "$stage/regsvc-build"
compiled=$(cd "$stage/regsvc-build" && pwd -P)
```

The ordinary `remote_xls_sim.sh` regression uses this runner for `regsvc`, then exports its single Verilog file into the multi-service simulation stage. A cache hit does not skip the DSLX tests, RTL simulations, or bridged Erlang tests. The other services in that regression retain their existing compilation commands.

## Reuse and dependency identity

Each compiler stage has a separate cache key:

| Stage | Inputs that determine reuse |
| --- | --- |
| IR conversion | Every staged `.x` file, the complete DSLX standard library, converter binary, top, and conversion arguments |
| Optimization | Input IR contents, optimizer binary, and arguments |
| RTL generation | Optimized IR contents, codegen binary, and arguments, including pipeline stages, II, and RAM configuration |

Keys also include the recipe version and host OS/architecture. Inputs are copied to a private attempt directory before compilation, including the standard library and any supplied wrapper/RAM assets. The converter resolves imports against that snapshot. Binary hashes follow executable symlinks, and a tool replacement during compilation fails the attempt. Paths to the original source and compiler installation do not affect the keys; the same staged contents can reuse work after relocation.

The source snapshot deliberately includes **all flat `.x` files**, including unused modules, rather than approximating DSLX's import parser. This covers transitive imports and added/removed shadowing modules conservatively; editing an unrelated staged module can rerun conversion. Optimization and codegen can still reuse their results if conversion produces identical IR. This interface expects the project's prepared flat module directory, not arbitrary external DSLX search paths. Prepare inputs in an isolated stage before building; do not run a source generator concurrently against that stage.

Only the changed compiler stage and downstream stages whose actual input contents change need to run. Changing codegen pipeline stages or II reuses conversion and optimization. Changing only wrapper/RAM Verilog or application metadata republishes the artifact bundle without rerunning XLS.

The cache is checked against output hashes before reuse; existence of a file or completion marker is insufficient. Damaged entries are retained with a `.damaged-…` suffix and recomputed. The installed toolchain and loader environment must remain consistent; use a fresh cache after changing system libraries or compiler runtime dependencies that are outside the tracked binaries and DSLX library.

## Publication and failures

`--output` names a managed symlink to a complete release directory. The release contains IR, optimized IR, RTL, a `<name>.build.json` manifest, per-stage commands/logs/timings, captured DSLX sources and standard library, and supplied assets. Publication switches that one symlink only after all compiler stages succeed and their outputs are checked. A failed conversion, optimization, codegen, timeout, or handled interruption leaves the previous release selected.

Resolve the symlink **once**, as in the `compiled` assignment above, before reading several artifacts or starting simulation. An already-running consumer can keep using that release while another build publishes its successor. Do not write into a published release. Source preparation and compiler outputs live in separate directories.

`<output>.run.json` beside the symlink describes the latest attempt, including its status, total elapsed time, and which stages actually compiled or reused results. Each completed compiler process records wall time, user/system CPU time, and peak RSS in bytes; interrupted stages retain elapsed time and termination status. Cached stages retain their original compilation timings separately and have no new execution time; those original timings are not the cost of the current invocation.

Failed attempts retain the captured inputs, commands, stderr, partial output, and timing information under `.xls-cache/attempts/`; the failed run report points to the directory and active stage. `--timeout` bounds each compiler invocation and accepts seconds or durations such as `5m` and `2h`. Cancellation stops the compiler process group. An uncatchable host crash can leave an unfinished attempt on disk, but it cannot publish an incomplete release; a later build reuses only completed, checked stages.

One writer owns each output. A competing build of that output fails promptly; independent output directories can share a cache and publish concurrently. Identical concurrent cache misses may both compile before converging on a checked entry. XLS can assign different internal node IDs on repeated runs; the first complete cached result wins, and subsequent stages consume those exact bytes. A losing concurrent compiler result is marked `adopted` in the run report, with its execution cost still recorded. `--cache` selects an explicit shared cache; otherwise it is `.xls-cache` beside the output. Cache entries can be removed when no builds are active without removing published releases. Releases remain available for pinned consumers and measurement provenance; there is no automatic garbage collection.

## Decoder profile

The decoder helper publishes its generated RTL, RAM implementation, wrapper, source snapshot, and profile metadata together:

```sh
inputs="$PWD/_build/d3-profile"
ERL_HLS_PHI_PROFILE_SHARDS=3 bash tools/prepare_xls_sim.sh "$inputs"
bash tools/compile_phi_decoder_profile.sh "$inputs" "$ERL_HLS_XLS_ROOT"
compiled=$(cd "$inputs/compiled" && pwd -P)
python3 experiments/07-openxc7/phi_timing.py "$compiled" \
    --stage "$PWD/_build/d3-simulation" --phase simulate
```

The helper's optional positional arguments remain `TIMEOUT SHARDS PIPELINE_STAGES II`, with defaults `2h 3 2 1`. Profile simulation and actor-debug commands pin the published directory before consuming RTL. `run_phi_decoder_profile.sh` includes the latest build's cache/execution report in its metrics. Physical comparisons consume the pinned release and retain the usual profile/RTL hash checks. See the [D3 probe budget](../experiments/07-openxc7/phi-timing.md#choose-the-probe-budget) before launching synthesis or routing.

## Regression checks

```sh
python3 tools/test_compile_xls.py
python3 tools/test_compile_xls.py --xls-root "$ERL_HLS_XLS_ROOT"
```

Fault-injected compilers exercise cold/warm reuse, relocation/output naming, import/stdlib/tool changes, codegen settings, asset/metadata changes, damaged cache entries and releases, failed-stage retry, timeout/cancellation, input snapshots, concurrent publishers (including nondeterministic compiler output), and the copied decoder helper. With `--xls-root`, a real `regsvc` compilation must produce byte-identical Verilog to the direct commands, compile with Icarus, reuse all stages on repeat, and rerun only codegen after a pipeline-setting change. CI runs both forms of coverage through the second command.

The [D3 compilation measurement](../experiments/08-phi-scheduler/incremental-build-2026-09-14.md) records one cold build and three cached repeats, unchanged RTL, and both maintained profile checks.
