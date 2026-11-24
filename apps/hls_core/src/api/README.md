# Shared actor values

Application sources use `hls_type` descriptors, records and providers such as `hls_nums`, `hls_bits`, `hls_lists` and `hls_vec`. The same contracts supply compiler widths and retained host codecs without depending on compiler or runtime processes.

`hls_type` dispatches defaults, widths, normalization and packing. `hls_enum` gives finite atom unions a compact declared-order encoding. `hls_record` composes ordered fields, and `hls_record_codec` retains their encoding contract without actor callbacks. `hls_continuation` checks the finite internal-event vocabulary, while `hls_service_schema` reads a compiler-embedded contract without source analysis.

`hls_field_layout` derives typed field widths and offsets. `hls_frame_layout` owns ordinary-frame packing, capacity and bounds; debug and explicit bridge envelopes retain separate layouts. Provider-specific compiler rendering remains behind `xls_type` in the compiler.

`hls_ring` is bounded circular storage with a resumable cursor; applications own predicates and continuation scheduling. `hls_prng` is deterministic source computation. Neither module owns an OTP process or runtime queue.

Read [type-provider extensions](../../../../docs/type-providers.md) for the distinct host and compiler callbacks. Actor behaviours and domain APIs remain in the [`hls_runtime` API](../../../hls_runtime/src/api/README.md).
