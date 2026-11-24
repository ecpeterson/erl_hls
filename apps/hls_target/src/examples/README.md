# Small build walkthrough

The [counter walkthrough](../../../erl_hls/src/examples/counter/README.md) demonstrates the facade build APIs with one tiny actor/topology and source-protocol, channel-scheduler and shared-RAM configurations. Its user-facing source and configurations live with `erl_hls`; target-owned generators consume them without owning the example. Complete applications retain their own sources, drivers and presets outside generic target integration.
