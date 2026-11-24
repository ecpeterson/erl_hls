# Umbrella facade and orchestration

`erl_hls` is the user-facing application. It selects the computation, communication and target libraries for a build, owns the command-line entry points and publishes their retained products. It does not own source analysis, routing policy, physical target adapters or deployed execution.

| Location | Owns | Main entry points |
| --- | --- | --- |
| [toolchain](toolchain/README.md) | Build and compile orchestration, CLI parsing and cross-application publication | `hls_build`, `hls_compile`, `hls_fabric_cli`, `hls_source_build`, `hls_scheduler_build` |
| [examples](examples/README.md) | Small compileable applications and host drivers | `regsvc`, `packed_samples`, `telemetry`, counter configurations |
| [`hls_compile`](../../hls_compile/README.md) | Erlang source acquisition, process analysis and computation synthesis | `hls_source`, `hls_topology`, `xls_parse` |
| [`hls_fabric`](../../hls_fabric/README.md) | Communication planning, logical routing and protocol projection | `hls_protocol_wait_graph`, `hls_protocol_codec_plan`, `hls_host_codec_plan` |
| [`hls_target`](../../hls_target/README.md) | Target-specific materialization, external-tool support and physical characterization adapters | `hls_build_profile`, `hls_build_support`, `hls_target_physical` |
| [`hls_runtime`](../../hls_runtime/README.md) | CPU actor execution, device sessions, virtual nodes and wire codecs | `hls_domain`, `hls_node`, `hls_fabric` |
| [`hls_core`](../../hls_core/README.md) | Shared logical-system, proposed-implementation and characterization contracts | `hls_logical_topology`, `hls_implementation_plan`, `hls_characterization` |

The intended dependency direction is facade → target → fabric → compile, with each of those applications also consuming process-free contracts from `hls_core` and execution descriptors from `hls_runtime` where required. Static package checks reject reverse dependencies from compile to later stages, from fabric to target or optimization, and from target to optimization or this facade.

The command path retains each boundary: computation synthesis produces compiler artifacts, communication planning derives routes and protocol projections, and target materialization prepares physical source and tool inputs. `hls_spacetime` may propose or revise an `hls_implementation_plan` from supplied characterization, but lower applications do not call it. Deployed runtime code consumes retained schemas and bindings without loading the facade or any synthesis application.

The parse transform remains in `hls_compile` because it uses source analysis to embed metadata. Generated BEAM codecs and service contracts use core and runtime APIs after compilation. Board programming and deployment artifact selection are separate responsibilities.
