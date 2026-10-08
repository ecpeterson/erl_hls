# Actor compilation

`xls_parse:to_xls(Path, Options)` emits a complete DSLX actor module. Supported options are `source_options` (preprocessor configuration) and `direct_actor_debug` (committed-state observations). Each generated service owns its state and bounded mailbox. XLS selects the hardware pipeline separately; the Erlang source describes callback behavior.

For a communicating graph, normalize the source topology with `hls_topology`, obtain module requirements from `xls_topology_dslx:artifact_requirements/2`, translate those actors, then emit the graph with `xls_topology_dslx:emit/2`. The physical profile controls channel and egress capacities. See [topology semantics](mixed-topologies.md).

## Alternate execution bodies

Compiler extensions can call `xls_parse:actor_artifact(Path, SourceOptions)` for a validated `hls_statem` artifact. It contains initialization, typed dispatch, ordered effects, internal events, retained replies, reductions and failure origins. Unsupported actor kinds are rejected explicitly.

`xls_actor_codegen:emit(Artifact, RuntimeImports, Body)` renders common semantics with an execution body. The body must preserve callback ordering, failure behavior and effect ownership. `xls_statem_codegen:body/1` supplies dedicated execution. These are source-level compiler interfaces: pin the compiler revision when consuming them. They are not a serialized deployment protocol.

## Ownership-planning sidecar

`xls_statem_plan:from_file(Path, SourceOptions)` returns `{Artifact, Plan}` from one ordinary lowering. `Artifact` is unchanged. `Plan` retains prepared callback clauses, typed helper signatures, entry branch programs and actor-wide protocol obligations before rendering discards their structure. It is an internal planning format, not a replacement renderer or a hardware optimization.

Use `xls_statem_plan:select(Plan, [{Phase, EventKind}, ...])` to inspect complete event families with their transitive helpers. Selection includes every clause in source order, including guards, failure/postponement alternatives and discarded evaluations; it does not select only successful outcomes. Initialization and reducers remain available. Provider calls are inventoried without assuming that providers depend only on their explicit operands.

Before consuming a saved plan, call `xls_statem_plan:validate(Path, SourceOptions, Plan)`. It recompiles the source, including includes, and compares the complete plan with compilation-local payload identities renamed consistently. Full source and rendering digests complement this check; a digest alone is not an equivalence proof. `manifest/1` emits a compact inventory without source bodies. Neither the plan nor a selected family establishes field independence, allowed concurrency, projection safety, deadlock freedom or physical locality; a transforming backend must establish those separately.
