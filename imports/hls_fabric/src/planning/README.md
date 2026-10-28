# Checked build planning

This directory derives and retains source, topology, placement, schema and physical-layout facts used by the build frontends and hardware generators. It also checks retained deployment and inspection metadata at attachment boundaries. Planning is not backend-neutral: a plan can contain compiler-lowered source, XLS family graphs, scheduler RAM layouts or target support-file choices. Keeping those facts here gives their consumers one authority; it does not introduce another compiler IR or independently configurable scheduling model.

Start with these entrypoints:

- `hls_scheduler_plan` normalizes scheduler groups and their actor-interface catalog. `hls_reduction_plan` checks source-fragment ownership, while `hls_topology_constants` derives topology-established state constants.
- `xls_fabric_topology_profile` normalizes physical generation options. `xls_fabric_topology_family_dslx` performs lower-only family preparation despite its historical suffix; `xls_topology_scheduler_plan` retains compact scheduler addresses, lanes, startup and source-fragment routing. `xls_topology_effect_windows` supplies their publication-conflict domains.
- Source-protocol preparation uses `hls_protocol_topology`, `hls_protocol_inventory`, `hls_protocol_capture`, `hls_protocol_transactions`, `hls_protocol_source` and `hls_protocol_fabric`. `hls_protocol_inbox` and `hls_protocol_partition` derive receiver ownership and crossing boundaries from those same programs.
- `hls_protocol_schema`, `hls_protocol_control`, `hls_protocol_application_binding`, `hls_partition_binding` and `hls_partition_ingress_plan` bind canonical frames and host recipients. `hls_protocol_projection` and `hls_protocol_codec_plan` derive bit wiring; the corresponding runtime codecs do not re-plan it.
- `xls_machine_layout` is the complete physical actor-row authority. `xls_scheduler_debug` and `hls_shared_debug_catalog` bind its observation fields and emitted failure codebooks to retained actor identities.
- `hls_protocol_model` optionally invokes application model callbacks and serializes their reports. `hls_protocol_wait_graph` checks the supplied finite graph; neither establishes source refinement or hardware progress by itself.

The legacy partition builders also normalize ownership here before their target-specific wrappers run. Their plans and the public source/scheduler build plans serve different composition paths; a directory move does not make them interchangeable.

Build orchestration acquires source and options, planning establishes the applicable facts, and [backend generators](../backend/README.md) consume them. Some planners call target helpers for authoritative widths or retained graph annotations; do not duplicate those definitions to manufacture a one-way dependency. Add target emission to the backend, host/session execution to runtime, and pure retained record or wire conversion to the wire modules. JSON/ETF reports written here are analysis artifacts, not emitted hardware or trusted admission certificates.
