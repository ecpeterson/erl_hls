# `erl_hls`

Compile bounded Erlang actors into hardware through XLS, and communicate with them from native Erlang through simulation or an FPGA.

Actors use `hls_gs` server or `hls_statem` state-machine callbacks and typed records; state machines declare bounded mailboxes. The compiler preserves callback selection, failures, ordered effects, retained replies, internal events, reductions and [indexed gathers](docs/indexed-gathers.md). Each hardware actor has dedicated state and execution. Topologies connect actors and rectangular families; host proxies retain ordinary Erlang message and call interfaces.

## Choose a starting point

| Goal | Start here |
| --- | --- |
| Understand the value and application boundaries | [Documentation guide](docs/README.md) and [system model](docs/system-model.md) |
| Compile one actor without assembling a deployment | [Standalone toolchain](docs/toolchain.md) |
| Follow a complete small project | [Connected telemetry](apps/erl_hls/src/examples/telemetry/README.md) |
| Exercise calls, casts, records and bounded replies | [Register service](apps/erl_hls/src/examples/regsvc/README.md) |
| Study a complete multi-actor decoder application | [Phi walkthrough](docs/hls_fabric/execution/phi-walkthrough.md) or [Snowflake application](workloads/hls_snowflake/README.md) |
| Inspect saved execution and physical evidence | [`hls_spacetime` viewer](apps/hls_spacetime/README.md) |

## Repository map

The [`apps/`](apps/README.md) directory contains the seven-application architectural spine and its supporting OTP applications. `hls_core` owns shared process-free contracts; `hls_runtime` owns execution and virtual nodes; `hls_compile` owns computation synthesis; `hls_fabric` owns communication synthesis; `hls_target` owns physical materialization; `hls_spacetime` owns pure system-plan policy and offline analysis; `erl_hls` is the CLI/orchestration facade. Static audits enforce their one-way dependencies.

Small teaching and compiler examples live under [`apps/erl_hls/src/examples`](apps/erl_hls/src/examples/README.md). Larger maintained applications live under [`workloads/`](workloads/README.md): `hls_phi` and `hls_snowflake` own their actors, resources and finite integration witnesses, while generic compiler and runtime applications do not depend on them. `router` is an independent multicast/barrier library, while `hls_spacetime_observer` is an optional cross-layer capture adapter.

`hls_runtime` starts the retained virtual-node supervisor; CPU actors, brokers and sessions still use explicit lifecycle APIs. The synthesis, target, optimizer and facade applications start no process. Built-in DSLX callbacks live in compiler companions, while custom providers retain the [extension contract](docs/type-providers.md).

`rebar3 compile` builds the default umbrella applications locally. The `hls` release contains the facade and complete build closure. The `hls_runtime` release contains only `hls_runtime`, `hls_core` and OTP dependencies; deployed code does not ship synthesis, target or optimizer applications.

The [repository-history map](docs/repository-history.md) records the selected source, filtered, merge, landing and retained-tag identities behind the umbrella.

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
