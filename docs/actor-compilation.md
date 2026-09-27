# Actor compilation

`xls_parse:to_xls(Path, Options)` emits a complete DSLX actor module. Supported options are `source_options` (preprocessor configuration) and `direct_actor_debug` (committed-state observations). Each generated service owns its state and bounded mailbox. XLS selects the hardware pipeline separately; the Erlang source describes callback behavior.

For a communicating graph, normalize the source topology with `hls_topology`, obtain module requirements from `xls_topology_dslx:artifact_requirements/2`, translate those actors, then emit the graph with `xls_topology_dslx:emit/2`. The physical profile controls channel and egress capacities. See [topology semantics](mixed-topologies.md).

## Alternate execution bodies

Compiler extensions can call `xls_parse:actor_artifact(Path, SourceOptions)` for a validated `hls_statem` artifact. It contains initialization, typed dispatch, ordered effects, internal events, retained replies, reductions and failure origins. Unsupported actor kinds are rejected explicitly.

`xls_actor_codegen:emit(Artifact, RuntimeImports, Body)` renders common semantics with an execution body. The body must preserve callback ordering, failure behavior and effect ownership. `xls_statem_codegen:body/1` supplies dedicated execution. These are source-level compiler interfaces: pin the compiler revision when consuming them. They are not a serialized deployment protocol.
