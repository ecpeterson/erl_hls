# Hardware build frontends

`hls_fabric_cli` implements `hls-fabric plan`, `emit` and `profile` using the compiler's `hls_cli` and `hls_diagnostic` helpers. Erlang callers use `hls_build:plan/1`, retain the result, inspect it, then call `write/2`. Backend selection is explicit:

- `hls_source_build` selects a source-protocol composition: transport, network, boundary, application, bridge, deployment or mixed.
- `hls_scheduler_build` retains a channel-scheduler generation plan, actor interfaces and RAM bindings for one configured placement.

`hls_source_config` checks trusted configuration shape; backend/source owners validate semantics. `hls_build_sources` compiles declared Erlang sources in memory with their source context. `hls_build_profile` records placement, frame ABI and supported schedules and renders literal tool flags; it does not discover tools or claim timing.

`hls_generated_files` composes emitted file sets and writes only at an explicit publication boundary. `hls_build_support` combines compiler and fabric support libraries, while compiler-owned `hls_artifact_bundle` freezes the portable manifest. The independent external driver consumes that bundle; source emission does not run XLS, simulate hardware or program a board.

Put source semantics in [planning](../planning/README.md) or [backend](../backend/README.md), runtime sessions in `runtime/`, and application presets in [examples](../examples/README.md). Keep this layer responsible for commands, checked build selection, inspection and packaging.
