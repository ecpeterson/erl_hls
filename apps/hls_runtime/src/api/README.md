# Actor and domain API

Application sources declare `hls_gs` servers or `hls_statem` state machines. The behaviours expose CPU adapters for the same callback vocabulary; their bookkeeping lives in [runtime](../runtime/README.md). Shared descriptors, providers, layouts, continuations and retained service schemas live in the [`hls_core` value API](../../../hls_core/src/api/README.md).

`hls_domain` is the application facade for fixed deployment domains and non-reused incarnations. `hls_domain_ids` separates one-time commissioning and delegated ID ranges from ordinary lifecycle control. `hls_domain_instance` is an ordinary OTP supervisor child representing one admitted incarnation; it encapsulates prepared manual startup and delegates lifecycle control to the surviving owner. The shared lifecycle kernel and ERTS backend live in `runtime/`. See [actor domains](../../../../docs/actor-domains.md).

Source preprocessing, record discovery and `hls_pack` belong to the compiler's [frontend](../../../erl_hls/src/frontend/README.md). Built-in DSLX callbacks live in [backend/xls](../../../erl_hls/src/backend/xls/README.md) behind `xls_type`; they are absent from the core provider modules.
