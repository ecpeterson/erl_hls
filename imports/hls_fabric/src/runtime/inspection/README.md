# Runtime inspection

`hls_protocol_observation` decodes source-protocol samples, while `hls_shared_observation` decodes shared scheduler samples. `hls_process_profile` combines observations into logical process reports; `hls_link_diagnostics` interprets link state. Callers supply the manifest/catalog associated with the running hardware and use the compiler's public debug transport interfaces.

Build-time catalog construction remains in [planning](../../planning/README.md), and instrumentation emission remains in [backend](../../backend/README.md). These modules interpret observations; they do not insert probes or regenerate a decoder. Some shared identity/manifest helpers still come from the compiler backend, a dependency to address when extracting packages.

Snapshots are sampled state and bounded traces have finite retention. Neither implies a complete causal message history or establishes unbounded progress. Profiling and device-specific diagnosis should preserve those evidence limits.
