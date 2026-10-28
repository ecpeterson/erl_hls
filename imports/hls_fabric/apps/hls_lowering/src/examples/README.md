# Fabric application examples

These modules apply the common build/runtime APIs to concrete workloads. They are not compiler policies. Actor implementations and logical phi/noise topologies currently come from the `erl_hls` example library; the fabric modules add placement, composition, profiling and host execution. These example modules ship with `hls_lowering`, including their application-specific host loops; generic deployed sessions remain in `hls_fabric`.

- [counter](counter/README.md) is the small public walkthrough: one actor/topology source with source-protocol, direct channel-scheduler and shared-RAM configurations.
- [phi_decoder](phi_decoder/README.md) contains the repetition source-protocol CLI, configuration preset and protocol-model provider. `phi_protocol_repetition` in this directory runs finite correction feedback and readout through an attached typed stream.
- `phi_decoder_profile`, `phi_decoder_profile_topology` and `phi_decoder_profile_topology_dslx` define decoder-only measurement geometry, logical routes and placement. `phi_decoder_profile_build` emits one coherent actor/topology/RAM/observation source set; `phi_decoder_profile_top_v` renders its RTL shell.
- `phi_shared_noise_topology_dslx` and `phi_shared_repetition_profile` select shared channel-scheduler placements. `phi_memory_gateway_dslx` composes the example host gateway; `phi_memory_debug_top_v` renders the RAM/serializer/observation shell.

The `*_dslx` and `*_top_v` modules use reusable backend renderers and installed templates, but own the example-specific composition. Keep generic layout/lowering in [backend](../backend/README.md), shared build policy in [toolchain](../toolchain/README.md), and generic session/stream handling in [hls_fabric runtime](../../../../src/runtime/README.md). Generated source and finite simulation results are witnesses, not live-device or decoder-convergence claims.
