# `erl_hls`

Compile bounded Erlang actors into hardware through XLS, and communicate with them from native Erlang through simulation or an FPGA.

Actors use `hls_gs` or `hls_statem` callbacks, typed records and bounded mailboxes. The compiler preserves callback selection, failures, ordered effects, retained replies, internal events, reductions and [indexed gathers](docs/indexed-gathers.md). Each hardware actor has dedicated state and execution. Topologies connect actors and rectangular families; host proxies retain ordinary Erlang message and call interfaces.

Start with the [documentation guide](docs/README.md), [register-service example](src/examples/regsvc/regsvc.erl), or [connected telemetry project](src/examples/telemetry/README.md).

## Packages

This repository builds two library applications. `erl_hls` owns the compiler, parse transform and toolchain assets; [`hls_runtime`](apps/hls_runtime/README.md) owns type providers, retained codecs, CPU actors and device sessions. The compiler depends on the runtime library. Deployed applications can use compiled actors and retained bindings without shipping compiler implementation.

Neither library starts an application supervisor. Actors and sessions have explicit lifecycle APIs; supervised applications decide how to own them. Built-in DSLX callbacks live in compiler companions, while custom providers retain the [extension contract](docs/type-providers.md).

`rebar3 compile` builds both locally. Git consumers select root `erl_hls` and `hls_runtime` from `apps/hls_runtime` using `git_subdir` at the same revision; dependency fetching does not discover sibling applications automatically. Runtime deployments depend on `hls_runtime` alone. The compiler CLI release includes the complete compiler and source assets.

## Build and check

Use OTP 28 and rebar3. The [standalone toolchain](docs/toolchain.md) packages `hlsc` for actor-to-DSLX compilation and an optional independent XLS driver:

```sh
rebar3 release
_build/default/rel/erl_hls/bin/hlsc --help
rebar3 eunit
python3 tools/check_source_contracts.py
rebar3 dialyzer
```

After changing translation, regenerate and review the source-adjacent DSLX with `tools/xls_goldens.sh update STAGE` after preparing `STAGE`. This requires Erlang, not XLS. Generated source comparisons check reproducibility; hardware behavior has separate RTL tests.

`tools/prepare_xls_sim.sh STAGE` prepares a portable hardware test bundle. `tools/remote_xls_sim.sh STAGE XLS_ROOT` converts it and runs Icarus/VPI tests. `tools/run_xls_sim.sh` dispatches to the configured Linux host; override `ERL_HLS_REMOTE_HOST`, `ERL_HLS_REMOTE_ROOT` and `ERL_HLS_REMOTE_XLS` for another machine. [Incremental compilation](docs/incremental-xls-builds.md) also supports native XLS.

[Compiler differential tests](docs/compiler-differential.md) compare generated programs with BEAM and retain minimized failures. [Debug targets](docs/debug-targets.md) expose actor snapshots, physical queue state and stream counters/traces. [Timing profiles](docs/profiling.md) provide reusable SVG and Perfetto views, keeping causal dependencies distinct from observed resource ordering.

For implementation entry points and module ownership, use the [source map](src/README.md).

Contributions follow [STYLE.md](STYLE.md). Application contracts belong in `docs/`; development notes belong in `yap/`.
