# Packed wire contracts

These modules translate complete Erlang values and checked descriptors to or from packed binary messages. Runtime sessions and generated-interface planners call them; they do not open devices, hold leases or schedule I/O. The shared `hls_runtime` library's `hls_frame_layout`, `hls_codec` and `hls_type` machinery supply common field/type operations.

| Entry points | Contract |
| --- | --- |
| `hls_domain_wire` | Retained actor codecs and independent domain lifecycle/application envelopes |
| `hls_host_codec` | Retained service/actor request and reply codec catalogs and structural checks |
| `hls_node_binding` | Retained scheduled-node deployment validation and addressed casts |
| `hls_partition_wire`, `hls_partition_ingress` | Partition packets and coordinate-derived host commands |
| `hls_protocol_envelope`, `hls_protocol_codec` | Ordinary protocol frames and schema-bound payloads |
| `hls_protocol_application_schema`, `hls_protocol_application_codec` | Application command/response framing |
| `hls_protocol_mixed_schema`, `hls_protocol_mixed_codec` | Mixed native/RTL gateway framing |
| `hls_protocol_bridge_wire` | Role-link words, attachment packets and control messages |

`hls_protocol_codec:plan/0` is the retained *runtime codec description type*. Build-time inference from actor interfaces lives in `hls_protocol_codec_plan:plan/2,3` under [hls_lowering planning](../../apps/hls_lowering/src/planning/README.md), and DSLX generation lives in `xls_protocol_codec` under [hls_lowering backend/xls](../../apps/hls_lowering/src/backend/xls/README.md). Keeping those separate prevents ordinary message encoding from regenerating hardware.

Widths, tags and bounds belong to the appropriate schema. Wire checks detect representational mismatch; they do not establish source-version compatibility, delivery or application progress. Those are separate contracts owned by the callers.

`hls_host_codec_plan` derives retained catalogs from source interfaces during lowering. Runtime consumers use those catalogs directly and do not reload the compiler interface.
