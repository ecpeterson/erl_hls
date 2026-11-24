# erl_hls: umbrella facade

`erl_hls` is the user-facing OTP application for command-line and Erlang build orchestration. It coordinates computation artifacts from `hls_compile`, communication plans from `hls_fabric` and physical products from `hls_target`, then publishes them through the retained compatibility APIs. It does not own compiler passes, logical routing, target adapters or runtime processes.

Start here to compile an actor or topology. The [standalone toolchain guide](../../docs/toolchain.md) shows the packaged `hlsc` commands; the [telemetry project](src/examples/telemetry/README.md) shows a complete small source layout. Use `hls_runtime` directly when consuming an already-built deployment without compiler or target code.

[`src/toolchain`](src/toolchain/README.md) contains the `hlsc` and `hls-fabric` command paths plus cross-application build coordination. [`src/examples`](src/examples/README.md) contains small facade fixtures. Deployed actor execution and virtual nodes belong to [`hls_runtime`](../hls_runtime/README.md); shared value contracts belong to [`hls_core`](../hls_core/README.md).

Lower applications never depend on this facade. System optimization supplies core `hls_implementation_plan` and `hls_characterization` values across explicit boundaries rather than calling facade commands.
