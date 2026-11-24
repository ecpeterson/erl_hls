# Channel-scheduler planning

`hls_scheduler_plan` normalizes actor groups, their interface catalog and physical storage. `hls_topology_constants` derives state specialization; `hls_reduction_plan` checks source-fragment ownership.

`xls_fabric_topology_profile` adds scheduler placement and observation options to the common `hls_implementation_constraints` capacities, names, frame selection and schedule vocabulary. `xls_fabric_topology_family_dslx` prepares family graphs despite its historical rendering suffix; `xls_topology_scheduler_plan` retains compact addresses, lanes and startup. `xls_topology_effect_windows` derives publication-conflict domains. The [scheduler generators](../../backend/xls/scheduler/README.md) consume these retained facts.

`xls_scheduler_debug`, `hls_shared_debug_catalog` and `hls_node_topology` prepare observation and host bindings without starting runtime sessions. Complete actor-row layout remains in [xls_machine_layout](../xls_machine_layout.erl). Legacy partition planning also reuses scheduler groups; this directory is a responsibility group within `hls_lowering`, not an exclusive call boundary.
