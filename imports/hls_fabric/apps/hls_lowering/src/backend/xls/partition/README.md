# Legacy partition generation

`hls_partition_dslx` consumes [placed-partition plans](../../../planning/partition/README.md). Its links, outbox, shared and reduction helpers connect device-local actors and crossings; `xls_actor_outbox_dslx` supplies the independent actor outboxes. `hls_partition_tile` combines specialization with physical wrapper parameters; `xls_partition_application` adds the application gateway.

RAM-backed partition groups reuse [scheduler interfaces](../scheduler/README.md). Source-protocol partition codecs remain in [protocol](../protocol/README.md), where they belong to a different retained plan. These directories organize existing composition paths within `hls_lowering`; they do not introduce package boundaries or alter the generated interfaces.
