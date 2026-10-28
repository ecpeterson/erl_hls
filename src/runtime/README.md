# CPU execution and host runtime

The application-facing CPU adapters are `hls_gs` and `hls_statem` in [api](../api/README.md). Here, `hls_mailbox`, `hls_reduction`, `hls_indexed_gather`, `hls_callback_actions`, `hls_gs_deferred` and `hls_reply_book` own their bounded reference state and reply bookkeeping. They are independent of hardware scheduling policy. `hls_codec` supplies shared bitstream primitives.

For a device connection, `hls_fabric` is the routed-frame broker. `hls_fabric_lease` reserves device paths, `hls_fabric_io` owns raw descriptors, and `hls_fabric_session` drains one logical session. `hls_fabric_client` is embedded state used by server/debug proxies to retain request ownership across timeouts. A timed-out caller does not imply cancellation of device work.

`hls_debug` dispatches scoped queries through `hls_debug_target`. `hls_debug_catalog` binds logical actors to CPU or hardware observations; its direct hardware convenience path validates a backend projection. `hls_topology_debug` checks manifest/session identity and decodes observations, while `hls_topology_wait` explores candidate waits using an injected query function.

Runtime code consumes concrete frame/schema/manifest contracts. Source reading, actor lowering and board programming are not runtime responsibilities. Current-state samples and boundary traces have different scopes; neither alone proves continuous blocking or application progress.
