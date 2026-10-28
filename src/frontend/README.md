# Source preparation and analysis

`hls_source` captures include/macro/feature context and preprocesses source. `hls_actor_source` reads state/message declarations, while `hls_records` resolves ordered fields, nested records and defaults through [type providers](../api/README.md).

`hls_pack` is the Erlang parse-transform callback selected by actor sources. It generates BEAM record codecs and embeds checked service/interface metadata. `hls_service_contract` analyzes request/reply declarations; its `from_module/1` query only reads the embedded result for runtime adapters. These preparation paths share callback analysis with the [XLS backend](../backend/xls/README.md), but do not themselves publish DSLX files.

`hls_actor_interface` acquires and validates summaries for one planning pass, reanalyzing available source through `xls_parse`. Callers retain that catalog across instances. `hls_actor_constants` computes conservative abstract input/state facts for topology and backend consumers; it does not rewrite actor source.

Use this directory for source-derived facts and preparation. Application type constructors stay in `api/`, logical graph normalization in `topology/`, rendering in `backend/`, and file/bundle publication in `toolchain/`. Do not introduce a second source context or module-global interface cache.
