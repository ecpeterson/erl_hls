# Runtime inspection

`hls_protocol_observation` decodes source-protocol samples, while `hls_shared_observation` decodes shared scheduler samples. `hls_process_profile` combines observations into logical process reports; `hls_link_diagnostics` interprets link state. Callers supply the manifest/catalog associated with the running hardware and use the shared `hls_runtime` debug transport interfaces.

Build-time catalog preparation belongs to [hls_lowering planning](../../../../hls_lowering/src/planning/README.md), and instrumentation emission belongs to its [backend](../../../../hls_lowering/src/backend/README.md). `hls_shared_observation:bind/2` checks a retained binding against the session projection and resources; tile bindings retain the checked logical-to-physical mapping. Identity hashes and debug catalog operations come from `hls_runtime`. These modules do not load source, re-normalize a scheduler, insert probes or regenerate a decoder.

Snapshots are sampled state and bounded traces have finite retention. Neither implies a complete causal message history or establishes unbounded progress. Profiling and device-specific diagnosis should preserve those evidence limits.
