# Packed wire contracts

These modules translate complete Erlang values and checked descriptors to or from packed binary messages. Runtime sessions and generated-interface planners call them; they do not open devices, hold leases or schedule I/O. The shared `hls_core` library supplies common field/type operations plus the retained `hls_host_codec` catalog and `hls_protocol_application_schema` descriptor.

| Entry points | Contract |
| --- | --- |
| `hls_domain_channel_wire` | Session-bound inspect, exact-pair bind and generation fence for mailbox crossings |
| `hls_supervisor_wire` | Parent lifecycle, delegated incarnation grants and bounded child admission |
| `hls_domain_wire` | Retained actor codecs and independent domain lifecycle/application envelopes |
| `hls_node_binding` | Retained scheduled-node deployment validation and addressed casts |
| `hls_partition_wire`, `hls_partition_ingress` | Partition packets and coordinate-derived host commands |
| `hls_protocol_envelope`, `hls_protocol_codec` | Ordinary protocol frames and schema-bound payloads |
| `hls_protocol_application_codec` | Application command/response framing over the core-owned descriptor |
| `hls_protocol_mixed_schema`, `hls_protocol_mixed_codec` | Mixed native/RTL gateway framing |
| `hls_protocol_bridge_wire` | Role-link words, attachment packets and control messages |

`hls_protocol_codec:plan/0` is the retained *runtime codec description type*. Build-time inference from actor interfaces lives in `hls_protocol_codec_plan:plan/2,3` under [`hls_fabric` planning](../../../../hls_fabric/src/planning/protocol/README.md), and DSLX generation lives in `xls_protocol_codec` under the [`hls_target` XLS backend](../../../../hls_target/src/backend/xls/README.md). Keeping those separate prevents ordinary message encoding from regenerating hardware.

Widths, tags and bounds belong to the appropriate schema. Wire checks detect representational mismatch; they do not establish source-version compatibility, delivery or application progress. Those are separate contracts owned by the callers.

`hls_host_codec_plan` derives the core-owned retained catalogs from source interfaces during communication planning. Runtime consumers use those catalogs directly and do not reload the compiler interface. The application schema and catalog remain ordinary Erlang values; runtime codecs supply their concrete frames without owning those contracts.
