# Device interaction

Runtime modules attach retained application descriptors to already-created brokers and exchange messages with a running device. They own leases, pending requests, queueing and retirement. [Wire codecs](../wire/README.md) encode messages; the common `hls_fabric` broker API from `erl_hls` owns the actual physical I/O boundary. The compiler runtime's `hls_fabric_io` is the file-descriptor transport. This directory does not generate DSLX or compile sources.

| Entry points | Responsibility |
| --- | --- |
| `hls_dma_device` | Linux endpoint readiness checks and broker lifecycle for a deployment |
| `hls_partition_stream` | Scheduled partition application commands, corrections and readout |
| `hls_protocol_stream` | Source-protocol application session |
| `hls_protocol_mixed_stream`, `hls_protocol_mixed_host` | Actual BEAM actors coupled to retained RTL roles |
| `hls_protocol_mixed_admission`, `hls_protocol_mixed_queue` | Pending source-event admission and per-sender delivery state |
| `hls_protocol_relay_queue`, `hls_protocol_routing` | Bounded role relay queues and routing descriptions |
| [inspection](inspection/README.md) | Public observation decoding and profiling |
| [node](node/README.md) | ERTS distribution endpoint and local carrier |

Sessions consume checked plans or bindings from [planning](../planning/README.md); that remaining compile-time dependency is explicit, not evidence of an independent runtime package. Setup and shutdown contracts are module-specific: acquiring a lease, retiring a route and resetting hardware are different operations. See [device sessions](../../docs/device-sessions.md) before implementing a new adapter.
