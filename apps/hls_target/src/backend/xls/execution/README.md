# Shared actor execution

`xls_machine_codegen` renders machine types, codecs and transition functions for both [protocol activation](../protocol/README.md) and [scheduler execution](../scheduler/README.md). `xls_machine_names` checks generated names; `xls_state_projection` reconstructs specialized state. The complete row layout remains in [planning/xls_machine_layout](../../../planning/xls_machine_layout.erl).

`xls_event_codegen`, `xls_gather_codegen`, `xls_indexed_memory_codegen` and `xls_reduction_service_codegen` supply event, collection and completion fragments. Some also contain scheduler-specific request, selection or retirement helpers; those existing interfaces deliberately remain intact. Each caller still owns storage, admission and scheduling. This shared directory is not a third execution mode or a separately enforced package.
