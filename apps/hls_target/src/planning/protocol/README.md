# Target protocol planning

These modules interpret communication requirements at a physical source-protocol boundary. They bind application roles and partitions, assign receiver storage, validate target arithmetic/control restrictions and retain the schema/source facts required by target generators.

Process-free transaction, projection, codec and wait-graph planning belongs to [`hls_fabric`](../../../../hls_fabric/src/planning/protocol/README.md). This directory consumes those retained results; it does not own logical routing policy. Generated protocol source belongs to the target [XLS backend](../../backend/xls/protocol/README.md), while live queues and codecs belong to `hls_runtime`.
