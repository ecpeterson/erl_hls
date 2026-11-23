# Source-protocol planning

`hls_protocol_topology`, `inventory`, `source` and `capture` retain checked actor programs and their possible messages. `hls_protocol_transactions`, `fabric` and `inbox` derive ownership and receiver storage; `arithmetic` selects supported shared completion groups. [Protocol generators](../../backend/xls/protocol/README.md) consume these plans without replacing the compiler's callback semantics.

Schema, projection and codec planners derive compact wiring. Control, application binding, link, partition and identity modules describe larger source-network boundaries. Host recipients reuse [hls_partition_binding](../hls_partition_binding.erl); deployed codecs consume retained descriptors without running these planners.

`hls_protocol_model` invokes optional application model callbacks, and `hls_protocol_wait_graph` checks a supplied finite graph. Their reports do not by themselves establish source refinement or hardware progress. These related planning tasks remain together within `hls_lowering`.
