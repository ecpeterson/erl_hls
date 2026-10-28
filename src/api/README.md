# Actor and type vocabulary

Application sources declare `hls_gs` servers or `hls_statem` state machines, use `hls_type` descriptors in records, and select provider modules such as `hls_nums`, `hls_bits`, `hls_lists` and `hls_vec`. The behaviours also expose CPU adapters for the same callback vocabulary; their bookkeeping lives in [runtime](../runtime/README.md).

`hls_type` dispatches provider callbacks for host codecs and XLS rendering. `hls_record` composes resolved fields, and `hls_record_codec` retains their encoding contract for later host use without actor callbacks. `hls_continuation` checks the shared finite event vocabulary. `hls_frame_layout` is the common ordinary-frame schema used by host codecs and emitted support configuration; debug and explicit bridge envelopes have separate widths.

Source preprocessing, record discovery and `hls_pack` belong to [frontend](../frontend/README.md), not here. Backend implementation helpers belong to [backend/xls](../backend/xls/README.md). Provider callbacks may depend on that backend's expression API; merely adding an application operation does not justify another source reader or generator in this directory.
