# Compiler topology acquisition

`hls_topology:from_module/1` and `normalize/1` load each distinct source-bound actor summary once, project it into `hls_process_interface`, and delegate graph validation to core `hls_logical_topology`. The façade preserves the compiler-facing API without owning a second topology representation.

Acquisition consumes richer facts from [frontend/hls_actor_interface](../frontend/hls_actor_interface.erl). Core retains only logical identity, public schema layouts, mailbox bounds, output ports and emitted/dispatched schemas. Source freshness, callback effects, state layout and selectors remain compiler data. Physical placement, numeric tags, channels and source emission belong to [backend/xls](../backend/xls/README.md); host device routes and sessions belong to [hls_runtime](../../../hls_runtime/src/runtime/README.md).

Keep source acquisition here and graph semantics in `hls_core`. Application geometries remain in their example or client modules rather than becoming topology special cases.
