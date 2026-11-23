# Legacy partition planning

`hls_partition` expands a logical topology into placed actors and inter-device lanes. `hls_partition_ingress_plan` binds rectangle ingress; `hls_partition_schedule` optionally assigns local actors to RAM executors, and `hls_partition_reduction` attaches supported reduction offload. `hls_partition_tile_debug` prepares observation bindings.

These plans feed the [partition generators](../../backend/xls/partition/README.md) and reuse [scheduler planning](../scheduler/README.md). They remain distinct from the source-network cuts in `hls_protocol_partition`. Shared host-recipient binding stays in [hls_partition_binding](../hls_partition_binding.erl); the directory grouping adds no package or execution boundary.
