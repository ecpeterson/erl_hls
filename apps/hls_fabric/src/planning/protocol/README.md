# Source-protocol planning

Core logical topology owns bounded actor materialization. `hls_protocol_inventory` and `hls_protocol_capture` project that materialization into possible-message and capture requirements; `hls_protocol_transactions` derives finite request/response ownership. These planners consume compiler facts without replacing the compiler's callback semantics.

`hls_protocol_projection`, `hls_protocol_codec_plan` and `hls_protocol_link` derive logical wiring and retained codec/link requirements. `hls_protocol_wait_graph` checks a supplied finite dependency graph. Their reports do not by themselves establish source refinement, physical buffering or hardware progress.

Target-owned protocol identity, application binding, receiver storage and physical source composition live in [`hls_target`](../../../../hls_target/src/backend/xls/protocol/README.md). Deployed codecs consume retained descriptors through `hls_runtime` without running either planning application.
