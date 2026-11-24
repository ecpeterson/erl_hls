# Facade entry points and bundles

`hls_compile_cli` implements the standalone `hlsc` command using `hls_cli` for options and shared structured diagnostics. `hls_compile:actor/3` is the equivalent Erlang facade: it delegates source analysis and computation synthesis to `hls_compile`, then asks `hls_target` to publish the retained artifact bundle. `hls_compile:topology/2` coordinates compiler acquisition with the `hls_fabric` topology renderer.

`hls_fabric_cli` implements `hls-fabric plan`, `emit` and `profile`. `hls_build`, `hls_source_build` and `hls_scheduler_build` select and inspect a checked backend request, while lower applications retain their own policy and products. Facade orchestration does not make compiler, Fabric or target internals part of this application.

`hls_target`'s `hls_artifact_bundle` owns fresh output directories, support-tree snapshots and the hashed `source-build.json` manifest. The emitter supplies literal codegen flags and descriptive metadata; publication does not run external tools. The target-owned driver consumes the published bundle explicitly.

Compiler passes belong to [`hls_compile`](../../../hls_compile/README.md), logical communication planning to [`hls_fabric`](../../../hls_fabric/README.md), physical materialization to [`hls_target`](../../../hls_target/README.md), and runtime sessions to [`hls_runtime`](../../../hls_runtime/README.md). `hls_spacetime` remains a separate process-free optimizer/analysis application, not a callback used by this facade.
