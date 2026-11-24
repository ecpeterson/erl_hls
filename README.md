# `erl_hls`

Compile bounded Erlang actors into hardware through XLS, and communicate with them from native Erlang through simulation or an FPGA.

Actors use `hls_gs` server or `hls_statem` state-machine callbacks and typed records; state machines declare bounded mailboxes. The compiler preserves callback selection, failures, ordered effects, retained replies, internal events, reductions and [indexed gathers](docs/indexed-gathers.md). Each hardware actor has dedicated state and execution. Topologies connect actors and rectangular families; host proxies retain ordinary Erlang message and call interfaces.

Start with the [documentation guide](docs/README.md), [register-service example](apps/erl_hls/src/examples/regsvc/regsvc.erl), or [connected telemetry project](apps/erl_hls/src/examples/telemetry/README.md).

## Packages

This umbrella builds separate compiler, core, runtime, lowering, Fabric and example applications. [`hls_core`](apps/hls_core/README.md) owns process-free values, logical identities, process interfaces, topology, retained descriptors and provenance keys; `erl_hls` owns source analysis and the compiler; [`hls_runtime`](apps/hls_runtime/README.md) owns CPU actors, domains, brokers and live sessions. Deployed applications can use compiled actors and retained bindings without shipping compiler implementation.

Neither `hls_core` nor `hls_runtime` starts an application supervisor. Actors and sessions have explicit lifecycle APIs; supervised applications decide how to own them. Built-in DSLX callbacks live in compiler companions, while custom providers retain the [extension contract](docs/type-providers.md).

`rebar3 compile` builds the default umbrella applications locally. Runtime deployments include `hls_core`, `hls_runtime`, their application code and any selected transport application. The compiler CLI release includes the complete compiler and source assets.

## Build and check

Use OTP 28 and rebar3. The [standalone toolchain](docs/toolchain.md) packages `hlsc` for actor-to-DSLX compilation and an optional independent XLS driver:

```sh
rebar3 release -n erl_hls
_build/default/rel/erl_hls/bin/hlsc --help
# Complete local CI coverage (native audits, packaging, XLS and RTL):
python3 tools/check.py /path/to/xls
# For a quick native-only iteration:
rebar3 eunit
```

EUnit alone does not run generated DSLX, XLS conversion/JIT, RTL, installed-toolchain or transport checks. The [shared qualification command](docs/ci.md) runs the same recipes as CI, serially, and retains per-command logs.

After changing translation, prepare a fresh stage with `tools/prepare_xls_sim.sh STAGE`, then use `tools/xls_goldens.sh check STAGE` to compare the checked register-service DSLX. Use `update` instead of `check` only after reviewing an intended change. This requires Erlang, not XLS. Other fixture and project writers regenerate their sources in their own tests. Generated source comparisons check reproducibility; hardware behavior has separate RTL tests.

`tools/prepare_xls_sim.sh STAGE` prepares a portable hardware test bundle. `tools/remote_xls_sim.sh STAGE XLS_ROOT` converts it and runs Icarus/VPI tests. `tools/run_xls_sim.sh STAGE` dispatches to the configured Linux host; override `ERL_HLS_REMOTE_HOST`, `ERL_HLS_REMOTE_ROOT` and `ERL_HLS_REMOTE_XLS` for another machine. [Incremental compilation](docs/incremental-xls-builds.md) also supports native XLS.

[Compiler differential tests](docs/compiler-differential.md) compare generated programs with BEAM and retain minimized failures. [Debug targets](docs/debug-targets.md) expose actor snapshots, physical queue state and stream counters/traces. [Timing profiles](docs/profiling.md) provide reusable SVG and Perfetto views, keeping causal dependencies distinct from observed resource ordering.

For implementation entry points and module ownership, use the [source map](apps/erl_hls/src/README.md).

Contributions follow [STYLE.md](STYLE.md). Application contracts belong in `docs/`; development notes belong in `yap/`.
