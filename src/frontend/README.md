# Source preparation and analysis

`hls_source` captures include/macro/feature context and preprocesses source. `hls_actor_source` reads state/message declarations, while `hls_records` resolves ordered fields, nested records and defaults through the runtime [type providers](../../apps/hls_runtime/src/api/README.md).

`hls_pack` is the Erlang parse-transform callback selected by actor sources. It generates BEAM record codecs and embeds checked service/interface metadata. `hls_service_contract` analyzes request/reply declarations; the runtime's `hls_service_schema:from_module/1` reads the embedded result. These preparation paths share callback analysis with the [XLS backend](../backend/xls/README.md), so compiling an actor requires `erl_hls`. Executing its generated codecs and callbacks requires the runtime library.

`hls_actor_interface` acquires and validates summaries for one planning pass, reanalyzing available source through `xls_parse`. Callers retain that catalog across instances. `hls_actor_constants` computes conservative abstract input/state facts for topology and backend consumers; it does not rewrite actor source. Neither source-bound acquisition nor source freshness checks belong in deployed runtime paths.

Use this directory for source-derived facts and preparation. Application constructors stay in `hls_runtime`, logical graph normalization in `topology/`, rendering in `backend/`, and file/bundle publication in `toolchain/`. Do not introduce a second source context or module-global interface cache.
