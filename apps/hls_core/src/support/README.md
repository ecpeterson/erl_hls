# Shared support

`hls_codec` supplies pure bitstream operations used by providers and retained codecs. `hls_diagnostic` carries structured failures across source analysis, lowering and runtime validation. `hls_actor_identity` hashes deterministic Erlang terms so emitted manifests and live observation catalogs use the same logical key; it does not identify a deployment incarnation, process or source revision.

These modules own no process, file, network connection or mutable global state.
