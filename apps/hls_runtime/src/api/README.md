# Actor and type vocabulary

Application sources declare `hls_gs` servers or `hls_statem` state machines, use `hls_type` descriptors in records, and select providers such as `hls_nums`, `hls_bits`, `hls_lists` and `hls_vec`. The behaviours expose CPU adapters for the same callback vocabulary; their bookkeeping lives in [runtime](../runtime/README.md). This directory belongs to the `hls_runtime` library and must remain independent of compiler implementation.

`hls_type` dispatches host defaults, widths, normalization and codecs. `hls_record` composes ordered fields, and `hls_record_codec` retains their encoding contract for later host use without actor callbacks. `hls_continuation` checks the finite event vocabulary. `hls_service_schema` reads the service contract embedded by the compiler without revisiting its source.

`hls_field_layout` derives typed field widths and offsets. `hls_frame_layout` owns ordinary-frame packing, selected capacity and bounds; debug and explicit bridge envelopes have separate layouts. The compiler consumes these facts to render support code through `xls_struct_codec` and `xls_frame_layout`.

Source preprocessing, record discovery and `hls_pack` belong to the compiler's [frontend](../../../../src/frontend/README.md). Built-in DSLX callbacks live in [backend/xls](../../../../src/backend/xls/README.md) behind `xls_type`; they are absent from the runtime provider modules. Read [type-provider extensions](../../../../docs/type-providers.md) for the distinct host and compiler callback contracts.
