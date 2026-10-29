# Channel-scheduler generation

`xls_fabric_topology_dslx` prepares a topology through [scheduler planning](../../../planning/scheduler/README.md); `xls_scheduler_actor` compiles its required actor variants. `xls_scheduler_codegen` wraps [shared machine execution](../execution/README.md) with RAM loading, selection, accepted-work tickets and publication. Dedicated and shared actors can coexist in the materialized topology; regular families can retain compact generation.

Collection, reduction, indexed storage, publication and effect-window helpers stay beside their scheduler owner. `xls_scheduler_observation`, `xls_collection_observation` and `xls_scheduler_ram_dslx` retain matching topology, debug and RAM interfaces; the [Verilog adapters](../../sv/README.md) reuse them.

Legacy partition wrappers also consume scheduler interfaces. This grouping does not restrict those calls or create a separate package. Runtime queues and source-protocol local owners remain with their own paths.
