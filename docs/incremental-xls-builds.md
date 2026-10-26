# Incremental XLS compilation

`tools/compile_xls.py` compiles a prepared flat directory of DSLX modules; `compile-source-build` consumes the frozen hierarchical, possibly multi-unit bundle described in [the source toolchain](toolchain.md). Both use the same compiler-owned executor for checked stage caches, private snapshots, timeouts, diagnostics and atomic publication. Use Python 3.12+ on Linux or macOS with an installed XLS toolchain. The drivers check the three executables and standard library; they do not install or rebuild XLS. Recipes retain their own entry points, schedules and backend policy. The flat adapter also accepts literal compiler options from an external build-profile frontend; it does not interpret that frontend’s policy.

Reusable Python helpers are exposed through `tools/erl_hls_tools`; importing them does not select a compiler checkout, change Python search paths or alter the environment. The `tools/*.py` command entrypoints remain directly executable. Consumers embedding helpers select that compiler package explicitly. Detached flat-directory stages copy the standalone `compile_xls.py` executor; detached source-bundle stages need both `compile_source_build.py` (packaged as `compile-source-build`) and its adjacent `compile_xls.py`. Both detached forms need only the Python standard library and their supplied inputs/tools.

For the generated `regsvc` example:

```sh
stage="$PWD/_build/xls_sim/regsvc"
bash tools/prepare_xls_sim.sh "$stage"
python3 tools/compile_xls.py "$stage/regsvc.x" "$ERL_HLS_XLS_ROOT" \
    --output "$stage/regsvc-build"
compiled=$(cd "$stage/regsvc-build" && pwd -P)
```

The ordinary `remote_xls_sim.sh` regression uses this runner for `regsvc`, then exports its single Verilog file into the multi-service simulation stage. A cache hit does not skip the DSLX tests, RTL simulations, or bridged Erlang tests. The other services in that regression retain their existing compilation commands.

## Literal options and optimizer pipelines

The flat Python `build(...)` API accepts `codegen_flags=["--pipeline_stages=2", "--delay_model=unit", ...]` as the complete codegen option list. It preserves ordering, repeated options and omitted settings, including II; it does not supply the standalone adapter’s schedule defaults. Do not combine it with nondefault `pipeline_stages`, `initiation_interval`, `delay_model` or `channel_delays` arguments. RAM, module, output and delay-table options remain adapter-owned. Without `codegen_flags`, the existing standalone schedule is unchanged.

A `codegen_flags(snapshot)` callback can read a staged policy sidecar from `snapshot / "assets"`; include that sidecar in `assets`. The callback and application metadata observe frozen inputs rather than the caller’s live files. For the `xc7_7030` delay model, supply `delay_table`; the final `--delay_model` option determines whether that table is required or rejected. The adapter inserts the frozen table path and records the literal options in the build manifest.

`optimizer_pipeline=Path(...)`, also exposed as `--optimizer-pipeline`, snapshots an XLS textproto pipeline and invokes the actual optimizer with `--pipeline_textproto=assets/optimizer_pipeline.txtpb`. The published bundle retains the pipeline alongside its hash, optimizer executable hash and effective arguments. This option affects only the flat adapter; source bundles retain their explicit per-unit command schema.

## Reuse and dependency identity

Each compiler stage has a separate cache key:

| Stage | Inputs that determine reuse |
| --- | --- |
| IR conversion | Every staged `.x` file with its relative path, the complete DSLX standard library, converter binary, top, and conversion arguments including ordered import roots |
| Optimization | Input IR contents, optimizer binary, arguments, and optional optimizer pipeline contents |
| RTL generation | Optimized IR contents, codegen binary, arguments, including pipeline stages, II and RAM configuration, and optional delay-table contents |

Keys also include the recipe version and host OS/architecture. Inputs are copied to a private attempt directory before compilation, including the standard library and any supplied wrapper/RAM assets. The converter resolves imports against that snapshot. Binary hashes follow executable symlinks, and a tool replacement during compilation fails the attempt. Paths to the original source and compiler installation do not affect the keys; the same staged contents can reuse work after relocation.

The flat-directory adapter snapshots **all flat `.x` files**, including unused modules. The source-bundle adapter snapshots every manifest-bound input with its hierarchy and ordered import roots; it rejects changed or unbound DSLX inputs. Neither approximates XLS's import parser. This conservatively covers transitive imports and shadowing, so editing an unrelated staged module can rerun conversion. Optimization and codegen still reuse results if their actual input bytes are unchanged. Prepare source inputs before building; do not run a generator concurrently against that stage.

Only the changed compiler stage and downstream stages whose actual input contents change need to run. Changing codegen pipeline stages, II or delay-table contents reuses conversion and optimization. Changing optimizer pipeline contents reuses conversion; codegen reruns only when optimized IR changes. Changing only wrapper/RAM Verilog or application metadata republishes the artifact bundle without rerunning XLS.

The cache is checked against output hashes before reuse; existence of a file or completion marker is insufficient. Damaged entries are retained with a `.damaged-…` suffix and recomputed. The installed toolchain and loader environment must remain consistent; use a fresh cache after changing system libraries or compiler runtime dependencies that are outside the tracked binaries and DSLX library.

## Publication and failures

`--output` names a managed symlink to a complete immutable release directory. The flat adapter retains IR, optimized IR, RTL, `<name>.build.json`, captured sources/stdlib and assets. Source-bundle compilation defaults to `SOURCE/compiled` and retains the frozen `source-build.json`, inputs, per-unit IR/RTL and `commands.json`, `compiled.json` and each role's `files.f`. Both retain stage commands, logs and original timings. `files.f` paths are relative to the listing's parent; source-bundle `compiled.json` paths are relative to the release root. The source inputs and their frozen manifest remain unchanged.

A recipe's backend finalization runs inside the private snapshot before product hashing and publication. For example, fabric completion-storage legalization updates the candidate RTL and its manifest before the common executor publishes it. Finalization failure leaves the previous release selected, just like conversion, optimization, codegen, timeout or handled interruption. Multi-unit builds publish only after every unit and finalization succeed. There is no intermediate public release of raw RTL awaiting a later mutation.

Resolve the symlink **once**, as in the `compiled` assignment above, before reading several artifacts or starting simulation. An already-running consumer can keep using that release while another build publishes its successor. Do not write into a published release. Source preparation and compiler outputs live in separate directories.

`<output>.run.json` beside the symlink describes the latest attempt, including its status, total elapsed time, and which stages actually compiled or reused results. Each completed compiler process records wall time, user/system CPU time, and peak RSS in bytes; interrupted stages retain elapsed time and termination status. Cached stages retain their original compilation timings separately and have no new execution time; those original timings are not the cost of the current invocation.

Failed attempts retain captured inputs, commands, stderr, partial output and timing information under the selected cache's `attempts/` directory; the failed run report points to the directory and active stage. Retry the same command to reuse checked completed stages, including earlier units of a multi-unit build. An unchanged successful invocation selects the same immutable release. `--timeout` bounds each compiler invocation and accepts seconds or durations such as `5m` and `2h`. Cancellation stops the compiler process group. An uncatchable host crash can leave an unfinished attempt on disk, but it cannot publish an incomplete release; a later build reuses only completed, checked stages.

One writer owns each output. A competing build of that output fails promptly; independent output directories can share a cache and publish concurrently. Identical concurrent cache misses may both compile before converging on a checked entry. XLS can assign different internal node IDs on repeated runs; the first complete cached result wins, and subsequent stages consume those exact bytes. A losing concurrent compiler result is marked `adopted` in the run report, with its execution cost still recorded. `--cache` selects an explicit shared cache; otherwise it is `.xls-cache` beside the output. Cache entries can be removed when no builds are active without removing published releases. Releases remain available for pinned consumers and measurement provenance; there is no automatic garbage collection.

## Regression checks

```sh
python3 tools/test_compile_xls.py
python3 tools/test_source_build_executor.py
python3 tools/test_compile_xls.py --xls-root "$ERL_HLS_XLS_ROOT"
```

Fault-injected compilers exercise cold/warm reuse, relocation/output naming, import/stdlib/tool changes, literal and default codegen settings, optimizer pipeline and delay-table contents, frozen option callbacks, asset/metadata changes, damaged cache entries and releases, failed-stage retry, timeout/cancellation, input snapshots and concurrent publishers (including nondeterministic compiler output). Source-bundle tests also cover hierarchical import shadowing, exact preview/execution arguments, fixed per-unit schedules, relative RTL listings and later-unit failure with cached retry. These test orchestration, not hardware semantics. With `--xls-root`, a real `regsvc` compilation must produce byte-identical Verilog to the direct commands, compile with Icarus, reuse all stages on repeat, and rerun only codegen after a pipeline-setting change. The `--xls-root` invocation runs both the flat-adapter mock suite and its native witness.
