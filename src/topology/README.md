# Logical actor topology

`hls_topology:from_module/1` and `normalize/1` check application graphs and derive deterministic routes. `hls_topology_family` handles compact rectangular families; `hls_topology_endpoint` checks endpoints and record compatibility for both exact and family actors.

Normalization consumes actor facts from [frontend/hls_actor_interface](../frontend/hls_actor_interface.erl). It retains logical actor identities, typed external boundaries, delivery modes and startup order. Physical placement, numeric tags, channels and source emission belong to [backend/xls](../backend/xls/README.md); host device routes and sessions belong to [runtime](../runtime/README.md).

Keep graph semantics here. Actor source analysis lives in `frontend/`, and application geometries remain in their example or client modules rather than becoming topology special cases.
