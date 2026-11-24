# Compiler source map

Start at `toolchain/hls_compile_cli.erl` for the command path, `toolchain/hls_compile.erl` for actor bundle emission, or `backend/xls/xls_parse.erl` for actor translation. These modules belong to the `erl_hls` library application. The separate [`hls_core` library](../../hls_core/README.md) owns shared values and codecs; [`hls_runtime`](../../hls_runtime/README.md) owns actor execution and host processes. Erlang module names remain flat; the application boundary determines which code a deployed system needs.

| Directory | Owns | Main entry points |
| --- | --- | --- |
| [frontend](frontend/README.md) | Source context, declarations, parse transform and analysis | `hls_source`, `hls_pack`, `hls_actor_interface` |
| [backend](backend/README.md) | XLS lowering, generated artifacts and physical representations | `xls_parse`, `xls_actor_program`, `xls_topology_dslx` |
| [topology](topology/README.md) | Compiler summary acquisition and projection into the core logical model | `hls_topology` |
| [toolchain](toolchain/README.md) | CLI and portable source bundles | `hls_compile`, `hls_artifact_bundle` |
| [examples](examples/README.md) | Compileable application fixtures and their host drivers | `regsvc`, `packed_samples`, connected `telemetry`; decoder applications live in hls_fabric |
| [core API](../../hls_core/src/api/README.md) | Type providers, codecs and shared frame vocabulary | `hls_type`, `hls_frame_layout` |
| [core model](../../hls_core/README.md) | Logical identities, process interfaces, topology and retained implementation contracts | `hls_logical_topology`, `hls_process_interface` |
| [runtime API](../../hls_runtime/src/api/README.md) | Actor behaviours and domain control | `hls_gs`, `hls_statem`, `hls_domain` |
| [runtime implementation](../../hls_runtime/src/runtime/README.md) | CPU reference state, device sessions and host inspection | `hls_fabric`, `hls_debug` |

The source path is `hls_source` preprocessing → declaration/callback analysis → XLS lowering → an `xls_emitted` artifact → `hls_artifact_bundle` publication. The separate `priv/tools/` driver invokes external XLS tools on that bundle. Compiler acquisition projects actor summaries into the core logical topology before backend planning. Deployed host execution consumes retained core schemas and manifests through `hls_runtime`, without source analysis or compiler modules.

The shared dependency direction is `erl_hls → hls_core` and `erl_hls → hls_runtime → hls_core → OTP`. Core and runtime declare no application callback or supervisor. Callers explicitly start CPU actors and device sessions; downstream supervised applications own their process lifecycles. The parse transform remains in the compiler because it uses backend analysis to embed metadata; the resulting BEAM record codecs and service contracts use core APIs.

Built-in type lowering lives behind `xls_type` and the `xls_provider_*` compiler companions. Host providers expose widths, defaults and codecs through `hls_type`. Shared layout facts belong to `hls_field_layout`/`hls_frame_layout`; DSLX rendering belongs to `xls_struct_codec`/`xls_frame_layout`. See [provider extensions](../docs/type-providers.md) before adding another cross-boundary callback.

Shared application declarations are under `include/`; shipped DSLX/RTL support is under `priv/`. Board programming and downstream multi-tenant placement are outside this compiler API. Production formatting and source contracts are described in [source-quality](../docs/source-quality.md). Tests live under `test/`; source-adjacent generated fixtures under `src/examples/` are reviewed outputs, not implementation modules to edit by hand.
