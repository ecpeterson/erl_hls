# Virtual distribution nodes

`hls_node` is the public manager for a virtual device node. `hls_node_sup` owns its manager, acceptor and connection supervision; `hls_node_acceptor` accepts TCP distribution peers and `hls_node_connections` supervises their handlers. `hls_node_connection` adapts supported ERTS signals to the existing fabric brokers, using `hls_node_wire` for distribution packet details. `hls_local_dist` supplies the optional in-process distribution carrier for locally hosted nodes.

The [application supervisor](../../app/README.md) starts configured node trees. [Planning](../../planning/README.md)'s `hls_node_topology` provides normalized scheduled-actor bindings, and [wire](../../wire/README.md)'s `hls_host_codec` translates device payloads. Node startup does not compile sources or create physical transport brokers.

This is a limited distribution endpoint, not a second ERTS or an implementation of arbitrary remote Erlang behavior. The supported signals, incarnation and reconnection rules are in [device sessions](../../../docs/device-sessions.md) and [actor addressing](../../../docs/actor-pids.md). Add carrier behavior here, packet schemas in `wire/`, and hardware generation in `backend/`.
