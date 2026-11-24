# Small compiler and runtime examples

These small projects exercise the same [core value API](../../../hls_core/src/api/README.md), [runtime actor API](../../../hls_runtime/src/api/README.md), [source preparation](../../../hls_compile/src/frontend/README.md) and [XLS backend](../../../hls_compile/src/backend/README.md) available to clients. They remain in this repository as compiler and runtime fixtures; they are not generic compiler policies.

- [telemetry](telemetry/README.md): a complete two-actor project with configuration, signed calibration, window statistics, a CPU host and a portable connected hardware build. Start here for project structure.
- [counter](counter/README.md): two addressed state machines and three equivalent source/scheduler configurations. Start here for small build-policy changes.
- [regsvc](regsvc/README.md): server calls/casts, register updates and bounded list replies.
- [packed_samples](packed_samples/README.md): sub-byte fields, bitstrings and signed codec behavior.

Checked-in `.x`/`.erl.x` files and example RTL are fixture/support artifacts beside their sources. Regenerate source outputs through the documented test workflow; extend generic computation synthesis in `hls_compile`, not by adding application-specific branches. The larger [`hls_phi`](../../../../workloads/hls_phi/README.md) and [`hls_snowflake`](../../../../workloads/hls_snowflake/README.md) applications own their decoder actors, resources, host drivers and finite witnesses. They are maintained workloads rather than compiler stages, and generic compiler validation does not depend on either package.
