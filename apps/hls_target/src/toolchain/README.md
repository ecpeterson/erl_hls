# Hardware build frontends

The `erl_hls` facade owns `hls_fabric_cli`, `hls_build`, `hls_source_build` and `hls_scheduler_build`. Those entry points choose a backend and coordinate compiler, communication and target products. This directory owns only the target-side support and publication functions they call.

`hls_source_config` checks trusted target configuration shape; backend/source owners validate semantics. Compiler-owned `hls_build_sources` compiles declared Erlang sources in memory with their source context. `hls_build_profile` records placement, frame ABI and supported schedules and renders literal tool flags; it does not discover tools or claim timing.

`hls_generated_files` composes emitted file sets and writes only at an explicit publication boundary. `hls_build_support` combines compiler, Fabric and target support libraries. Target-owned `hls_artifact_bundle` freezes the portable manifest for an explicit external driver, and `hls_source_build_receipt` checks the returned request, products, implementation and retained bytes before an observer uses their correlation identity. Source emission and receipt validation do not run XLS, simulate hardware or program a board.

Put target semantics in [planning](../planning/README.md) or [backend](../backend/README.md), runtime sessions in [`hls_runtime`](../../../hls_runtime/src/fabric/README.md), and facade orchestration in [`erl_hls`](../../../erl_hls/src/toolchain/README.md). Keep this layer responsible for target support selection, physical-profile encoding and artifact publication.
