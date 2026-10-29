# XLS-facing generation

These Erlang modules lower checked plans into DSLX and compose source artifacts for XLS. They also retain the physical interfaces needed by their surrounding hardware. This directory is broader than text emission: the public composition facades prepare source and choose a supported lowering path, while smaller renderers consume already checked facts. [Planning](../../planning/README.md) owns reusable topology, schema and layout authorities; it may itself retain XLS-specific representations.

The public build frontend selects one execution path; both use common actor execution support:

- [execution](execution/README.md) owns machine representation, codecs and transition fragments used by activation and scheduler generation.
- [scheduler](scheduler/README.md) owns channel topology, shared RAM execution, collection, publication and their observation interfaces. `hls_scheduler_build` enters through `xls_fabric_topology_dslx` and `xls_scheduler_actor`.
- [protocol](protocol/README.md) owns local actors, receiver inboxes and source-protocol transport through application/deployment composition. `hls_source_build` enters through `hls_protocol_transport`.
- [partition](partition/README.md) owns the legacy placed-partition wrappers and gateway, which can reuse scheduler interfaces.

These are navigation groups within one `hls_lowering` application, not enforced packages. Shared gather, reduction and indexed-memory helpers deliberately retain both common execution and scheduler-specific fragments. Collection/publication features stay with their owning backend rather than becoming separate groups. `xls_template` remains here as the common checked template renderer.

To extend a generated block, first find the retained input plan and its owner. Put reusable behavioral code in `priv/xls/`; use `xls_template` only for explicit checked template slots and Erlang renderers for static dimensions, names and connections. Preserve `xls_emitted` artifacts while composing compiler output so their failure codebooks stay attached. Extract bytes only for an output file or another documented byte boundary. Runtime record packing, transport sessions, external tool invocation and application examples do not belong here.
