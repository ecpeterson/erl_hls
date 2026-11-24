# Maintained workloads

These OTP applications exercise the compiler, communication planner, runtime and target tooling as complete end-to-end systems. They are built with the umbrella but are not reusable layers of its architecture; applications under [`apps/`](../apps/README.md) never depend on them.

| Workload | Purpose | Start here |
| --- | --- | --- |
| [`hls_phi`](hls_phi/README.md) | Distributed Phi/noise decoder, host drivers and hardware fixtures | [Protocol overview](hls_phi/src/phi_phenom_topology.md) |
| [`hls_snowflake`](hls_snowflake/README.md) | Streaming Snowflake decoder, sequential reference and finite fixtures | [Algorithm and package guide](hls_snowflake/README.md) |

The default profile compiles both workloads. The `hls_workloads` release packages them with their workload-facing launchers; the generic `hls` release and deployed `hls_runtime` release omit them. Small teaching examples remain under [`apps/erl_hls/src/examples`](../apps/erl_hls/src/examples/README.md).
