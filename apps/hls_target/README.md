# hls_target: physical target integration

`hls_target` owns physical implementation boundaries: target-specific planning and materialization, generated-source composition, external-tool support, physical catalogue import and timing-sidecar validation. It consumes computation artifacts from `hls_compile`, communication plans from `hls_fabric` and shared proposed-implementation contracts from `hls_core`.

The library is process-free and has no application callback. Planning or emission does not start a device, run a tool or deploy an artifact. `hls_build_support` locates the complete installed compiler, Fabric and target resource set; explicit tool drivers consume the resulting bundles. Physical characterization adapters validate evidence but do not choose optimizer policy.

[`src/planning`](src/planning/README.md) owns target-interpreted partition, protocol and scheduler bindings. [`src/backend`](src/backend/README.md) materializes XLS and SystemVerilog sources. `src/characterization/` owns native physical tables and SDF validation. `src/toolchain/` owns target profiles, resource layouts and artifact publication; `priv/` contains installed target templates, simulator support and tool adapters.

The [`erl_hls` facade](../erl_hls/src/README.md) coordinates these functions for CLI users. [`hls_runtime`](../hls_runtime/README.md) consumes retained deployment bindings without depending on this package. [`hls_spacetime`](../hls_spacetime/README.md) may propose or revise placement and scheduler requests, but target code never calls it; the optimizer supplies a checked `hls_implementation_plan` across the core contract instead.
