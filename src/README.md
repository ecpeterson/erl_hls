# Compiler source map

Start at `toolchain/hls_compile_cli.erl` for the command path, `toolchain/hls_compile.erl` for actor bundle emission, or `backend/xls/xls_parse.erl` for actor translation. The public module names are flat Erlang names; directories identify responsibility, not separate applications.

| Directory | Owns | Main entry points |
| --- | --- | --- |
| [api](api/README.md) | Actor behaviours, type providers and shared frame vocabulary | `hls_gs`, `hls_statem`, `hls_type`, `hls_frame_layout` |
| [frontend](frontend/README.md) | Source context, declarations, parse transform and analysis | `hls_source`, `hls_pack`, `hls_actor_interface` |
| [backend](backend/README.md) | XLS lowering, generated artifacts and physical representations | `xls_parse`, `xls_actor_program`, `xls_topology_dslx` |
| [topology](topology/README.md) | Logical graph normalization and route compatibility | `hls_topology` |
| [toolchain](toolchain/README.md) | CLI, diagnostics and portable source bundles | `hls_compile`, `hls_artifact_bundle` |
| [runtime](runtime/README.md) | CPU reference state, device sessions and host inspection | `hls_fabric`, `hls_debug` |
| [app](app/README.md) | OTP application bootstrap | `erl_hls_app` |
| [examples](examples/README.md) | Compileable application fixtures and their host drivers | `regsvc`, `packed_samples`, phi/noise actors |

The source path is `hls_source` preprocessing → declaration/callback analysis → XLS lowering → an `xls_emitted` artifact → `hls_artifact_bundle` publication. The separate `priv/tools/` driver invokes external XLS tools on that bundle. Logical topologies feed backend planning alongside actor interfaces; host execution uses retained schemas and runtime helpers.

These are ownership boundaries, not a claim of an acyclic module graph: type providers expose XLS callbacks, the parse transform uses backend analysis to embed interface metadata, and the direct debug catalog validates compiler projections. See each directory guide before adding another dependency. Shared application declarations are under `include/`; shipped DSLX/RTL support is under `priv/`. Neither board programming nor downstream multi-tenant placement is part of this source tree's compiler API.

Production Erlang formatting and source contracts are described in [source-quality](../docs/source-quality.md). Tests live under `test/`; source-adjacent generated fixtures under `examples/` are reviewed outputs, not implementation modules to edit by hand.
