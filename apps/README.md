# Umbrella applications

This directory contains the seven-application architectural spine, one optional integration adapter and one reusable routing library. Maintained end-to-end applications live separately under [`workloads/`](../workloads/README.md), so their OTP packaging does not obscure the reusable architecture. Generic libraries never depend on those workloads.

Choose an entry point by task:

- Compile one actor or a communicating topology through the supported CLI: [`erl_hls`](erl_hls/README.md) and the [toolchain guide](../docs/toolchain.md).
- Embed or deploy an already-built actor system without compiler code: [`hls_runtime`](hls_runtime/README.md).
- Propose a placement or inspect saved execution and physical evidence: [`hls_spacetime`](hls_spacetime/README.md).
- Learn the actor/compiler structure from a small project: the [telemetry example](erl_hls/src/examples/telemetry/README.md).
- Study a complete decoder workload: [`hls_phi`](../workloads/hls_phi/README.md) or [`hls_snowflake`](../workloads/hls_snowflake/README.md), after the smaller examples.

## Architectural spine

| Application | Owns | Typical use |
| --- | --- | --- |
| [`hls_core`](hls_core/README.md) | Process-free logical-system, implementation-plan and characterization contracts | Shared value library; no service to start |
| [`hls_runtime`](hls_runtime/README.md) | Live actor execution, device sessions, wire codecs and virtual-node supervision | Deployment and CPU execution |
| [`hls_compile`](hls_compile/README.md) | Source analysis and computation synthesis | Library behind the facade |
| [`hls_fabric`](hls_fabric/README.md) | Communication synthesis, protocol projection and logical routing | Library behind topology builds |
| [`hls_target`](hls_target/README.md) | Physical materialization, tool support and characterization adapters | Library behind target builds and evidence import |
| [`hls_spacetime`](hls_spacetime/README.md) | Pure system-plan policy and offline execution analysis | Optional planner, report and viewer tooling |
| [`erl_hls`](erl_hls/README.md) | CLI and cross-application build orchestration | Supported compile/build entry point |

Compile cannot call Fabric, target, Spacetime or the facade; Fabric cannot call target, Spacetime or the facade; target cannot call Spacetime or the facade. Runtime depends only on core and OTP. `hls_spacetime` consumes target-validated physical values, while target never calls the optimizer. The [system model](../docs/system-model.md) defines the value boundaries and complete dependency rule.

## Supporting applications

| Application | Role |
| --- | --- |
| [`router`](router/README.md) | Reusable rectangular multicast and ordered barriers for ERTS and managed endpoints |
| [`hls_spacetime_observer`](hls_spacetime_observer/README.md) | Optional cross-layer capture adapter; its broad integration closure stays out of lower applications |

The default profile builds the architectural applications other than Spacetime, plus `router` and both decoder workloads. The `spacetime` profile selects `hls_spacetime` and `hls_spacetime_observer` with their dependency closure. The `hls` release packages build tooling, `hls_workloads` packages the decoder workloads, and `hls_runtime` contains only the core/runtime deployment closure.
