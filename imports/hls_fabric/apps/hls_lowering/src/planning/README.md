# Checked build planning

This directory derives and retains source, topology, placement, schema and physical-layout facts used by the build frontends and hardware generators. It also prepares retained deployment and inspection bindings; runtime attachment checks live manifests against those results. Planning is not backend-neutral: a plan can contain compiler-lowered source, XLS family graphs, scheduler RAM layouts or target support-file choices. Keeping those facts here gives their consumers one authority; it does not introduce another compiler IR or independently configurable scheduling model.

Follow the selected composition path:

- [scheduler](scheduler/README.md) owns actor groups, state specialization, channel topology, reduction placement and scheduled inspection bindings.
- [protocol](protocol/README.md) owns source programs, captures, receiver ownership, compact codecs and source-network boundaries.
- [partition](partition/README.md) owns the legacy placed-partition graph, optional local scheduling and partition inspection bindings.

Shared authorities remain here: `xls_machine_layout` defines complete actor-row slices, `hls_host_codec_plan` derives retained codec catalogs, and `hls_partition_binding` binds host recipients for both partition and source-protocol applications. These directories group related work within one application; plans retain their distinct contracts, and cross-directory helper calls remain supported.

Build orchestration acquires source and options, planning establishes the applicable facts, and [backend generators](../backend/README.md) consume them. Some planners call target helpers for authoritative widths or retained graph annotations; do not duplicate those definitions to manufacture a one-way dependency. Add target emission to the backend, host/session execution to [hls_fabric runtime](../../../../src/runtime/README.md), and pure retained record or wire conversion to its [wire modules](../../../../src/wire/README.md). JSON/ETF reports written here are analysis artifacts, not emitted hardware or trusted admission certificates.
