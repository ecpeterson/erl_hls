# Source-protocol repetition preset

`phi_protocol_cli` implements `hls-repetition`. It asks `phi_protocol_config:repetition/2` for a source/placement request, then passes it to `hls_build`. The preset resolves the compiler's line data, syndrome and phi actors and `phi_repetition_topology`; options select whole, split or mixed placement within the checked example bounds.

`phi_protocol_model` implements the `hls_protocol_model` callbacks selected by that configuration. It derives a periodic wait graph from the source inventory plus explicit role/phase annotations. Ranking this graph does not establish source refinement, initialization, fairness or application progress; those obligations remain visible in its report.

The source-protocol host loop is [phi_protocol_repetition](../phi_protocol_repetition.erl); callers attach and retire the matching stream. The adjacent `phi_memory_gateway.x` is a retained generated fixture for the separate channel-scheduler memory gateway, emitted by [phi_memory_gateway_dslx](../phi_memory_gateway_dslx.erl), not the implementation of the repetition CLI.

Application records/actor callbacks stay in the compiler example library. General source configuration, backend generation and runtime transport stay with their owning fabric modules rather than growing application branches here.
