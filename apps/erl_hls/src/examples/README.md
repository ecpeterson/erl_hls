# Application examples

These applications exercise the same [core value API](../../../hls_core/src/api/README.md), [runtime actor API](../../../hls_runtime/src/api/README.md), [source preparation](../frontend/README.md) and [XLS backend](../backend/README.md) available to clients. They remain in this repository as compiler and runtime fixtures; they are not generic compiler policies.

- [telemetry](telemetry/README.md): a complete two-actor project with configuration, signed calibration, window statistics, a CPU host and a portable connected hardware build. Start here for project structure.
- [regsvc](regsvc/README.md): server calls/casts, register updates and bounded list replies.
- [packed_samples](packed_samples/README.md): sub-byte fields, bitstrings and signed codec behavior.

Checked-in `.x`/`.erl.x` files and example RTL are fixture/support artifacts beside their sources. Regenerate source outputs through the documented test workflow; extend generic lowering in `backend/`, not by adding application-specific branches there. The full Phi/noise application, its configurations and host drivers belong to the umbrella's [`hls_phi`](../../../hls_phi/README.md) application. Compiler topology and interface tests use tiny source actors under `test/`, so compiler validation has no dependency on that application package.
