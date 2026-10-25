# Actor compilation

The [standalone `hlsc` command](toolchain.md) packages single-actor lowering without requiring rebar at invocation time.

`xls_parse:to_xls(Path, Options)` emits a complete DSLX actor module. Supported options are `source_options` (preprocessor configuration) and `direct_actor_debug` (committed-state observations). Each generated service owns its state and bounded mailbox. XLS selects the hardware pipeline separately; the Erlang source describes callback behavior.

For a communicating graph, normalize the source topology with `hls_topology`, obtain module requirements from `xls_topology_dslx:artifact_requirements/2`, translate those actors, then emit the graph with `xls_topology_dslx:emit/2`. The physical profile controls channel and egress capacities. See [topology semantics](mixed-topologies.md).

Scalar clause lowering retains [structured arithmetic and comparison expressions](expression-ir.md) until DSLX rendering. Bit-vector optimization belongs to XLS.

## Alternate execution bodies

Compiler extensions can call `xls_parse:actor_artifact(Path, SourceOptions)` for a validated `hls_statem` artifact. It contains initialization, typed dispatch, ordered effects, internal events, retained replies, reductions and failure origins. Unsupported actor kinds are rejected explicitly.

`xls_actor_codegen:emit(Artifact, RuntimeImports, Body)` renders common semantics with an execution body. The body must preserve callback ordering, failure behavior and effect ownership. `xls_statem_codegen:body/1` supplies dedicated execution. These are source-level compiler interfaces: pin the compiler revision when consuming them. They are not a serialized deployment protocol.

## Shared source snapshot

`xls_actor_program:from_file(Path, SourceOptions)` compiles a complete actor once into an opaque in-process program. `spec/1` returns the ordinary rendering artifact and `plan/1` its complete planning sidecar from that same lowering. No constructor accepts supplied artifacts or selected alternatives. Consumers retain the program unchanged; editing a returned map does not modify it. These views describe the captured source, so later file edits require a new `from_file/2`. The program is not a saved build-input format or a replacement for saved-plan validation below.

`xls_actor_program:entry_effects(Program)` returns every effect in every entry layout across all phases, with `phase`, `layout` and zero-based `order`. It preserves the full typed field metadata, including constants, known bits, slices and layout-local storage offsets that express sharing. It neither filters alternatives nor joins them into a constant summary. Empty layouts contribute no effects; evaluation and failure obligations remain in the rendering artifact and planning sidecar. Consumers deriving channel constants must join every matching alternative rather than selecting a convenient phase or branch.

## Ownership-planning sidecar

`xls_statem_plan:from_file(Path, SourceOptions)` returns `{Artifact, Plan}` from one ordinary lowering. `Artifact` is unchanged. `Plan` retains prepared callback clauses, typed helper signatures, entry branch programs and actor-wide protocol obligations before rendering discards their structure. It is an internal planning format, not a replacement renderer or a hardware optimization.

Use `xls_statem_plan:select(Plan, [{Phase, EventKind}, ...])` to inspect complete event families with their transitive helpers. Selection includes every clause in source order, including guards, failure/postponement alternatives and discarded evaluations; it does not select only successful outcomes. Initialization and reducers remain available. Provider calls are inventoried without assuming that providers depend only on their explicit operands.

Before consuming a saved plan, call `xls_statem_plan:validate(Path, SourceOptions, Plan)`. It recompiles the source, including includes, and compares the complete plan with compilation-local payload identities renamed consistently. Full source and rendering digests complement this check; a digest alone is not an equivalence proof. `manifest/1` emits a compact inventory without source bodies. Neither the plan nor a selected family establishes field independence, allowed concurrency, projection safety, deadlock freedom or physical locality; a transforming backend must establish those separately.

`xls_statem_plan:identity(Plan)` returns a versioned set of canonical source/preprocessing, closed-artifact, complete-plan and planner digests for build identity. Source filenames and include origins are relative to the actor directory; ordered include search roots are relative to the captured build directory. This permits relocation while preserving relative include topology, macro/feature values and ordering, source bodies, failure paths/lines and semantic `?FILE` expansions. The complete-plan digest is recomputed from current contents with origin aliases renamed bijectively, so splitting or merging aliases changes identity. Strict `validate/3` and the path-bearing provenance manifest remain unchanged. Generated actor DSLX uses a generic banner; the original source path remains in the artifact and provenance.

## Source constants under declared inputs

`hls_actor_constants:from_source(Forms, Phases, Messages)` analyzes validated, record-resolved actor source without executing its callbacks. `Messages` must overapproximate every possible cast, including startup configuration. Use `value/1` for an exact hardware-normalized value or `unknown_record/2` for a record with unconstrained fields. Entry and internal callbacks remain unrestricted. The result maps reachable phases to structural abstract data; `constant/1` extracts a term only when every component is known. Unsupported computation, recursion or exhausted analysis loses precision. `repeat_phase` retains updates in the current phase.

This analysis exposes facts to callers; it does not change generated code or grant specialization eligibility. Callers must bind facts to current source and justify the supplied input domain. `xls_phase_values` instead infers source-bound scalar marginals from arbitrary incoming messages and checked successful returns. The two analyses have different assumptions: a constant established under a configured message domain cannot substitute for an unrestricted phase fact.
