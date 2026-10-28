# XLS types and codecs

`xls_type` is the compiler side of the runtime `hls_type` descriptor contract. Expression lowerers call its `transpile/4` dispatch; actor and topology renderers use its type and codec operations. It selects the built-in `xls_provider_*` companions or the application's own provider callbacks. This includes operations such as arithmetic, collection access, PRNG updates and serial counters, not just printing type names.

`xls_record_codegen` adapts source records to `xls_struct_codec`; the latter renders declarations and codecs from runtime-owned `hls_field_layout` offsets. `xls_named_bits` describes nominal types declared by generated layouts. `xls_nums` prints numeric types/literals, and `xls_frame_layout` renders ordinary-frame declarations from the runtime frame contract.

Host values, packing and descriptors remain in [hls_runtime](../../../../apps/hls_runtime/README.md). Source-only shape checks belong to [analysis](../analysis/README.md); source evaluation and selected failures belong to [expressions](../expressions/README.md). Provider output stays structured until [emission](../emission/README.md) finalizes the containing artifact. See [type-provider extensions](../../../../docs/type-providers.md) for the callback boundary.
