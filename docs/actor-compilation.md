# Actor compilation

The [standalone `hlsc` command](toolchain.md) packages single-actor lowering without requiring rebar at invocation time.

`xls_parse:to_xls(Path, Options)` emits a complete DSLX actor module. Supported options are `source_options` (preprocessor configuration), `direct_actor_debug` (committed-state observations) and `frame_payload_words` (ordinary payload capacity, default three words). Each generated service owns its state; state machines also own their declared bounded mailbox. XLS selects the hardware pipeline separately; the Erlang source describes callback behavior.

`xls_parse:to_artifact(Path, Options)` retains the finished module and its allocated failure codebook together. Use `xls_emitted:bytes/1` when writing DSLX, and pass the artifact itself to debug projection builders. The byte-only `to_xls` convenience API uses the same compilation path. These emitted artifacts are distinct from `actor_artifact/2`, which retains callback semantics before execution-backend selection.

For a communicating graph of `hls_statem` actors, normalize the source topology with `hls_topology`, obtain module requirements from `xls_topology_dslx:artifact_requirements/2`, translate those actors, then emit the graph with `xls_topology_dslx:emit/2`. The physical profile controls channel and egress capacities. The topology frontend does not accept `hls_gs` actors. See [topology semantics](mixed-topologies.md) and the complete [telemetry project](../src/examples/telemetry/README.md).

Scalar clause lowering retains [structured arithmetic and comparison expressions](expression-ir.md) until DSLX rendering. Bit-vector optimization belongs to XLS.

## Compiler implementation boundaries

`xls_parse` is the compilation facade: `to_artifact/1,2` and `to_xls/1,2` select the server or state-machine path. `actor_interface/1,2,3` and `actor_artifact/2,3` expose state-machine semantics; their three-argument forms select a checked `hls_frame_layout`, while shorter forms use the default. The facade does not provide source queries, expression operations or record codecs. Internal consumers call the owning module directly. These APIs move with the compiler revision rather than retaining forwarding functions on the facade.

| Work on | Start here | Result or responsibility |
| --- | --- | --- |
| Preprocessing and source lookup | `hls_source` | Captured context, include-expanded forms, attributes, functions and specs |
| Actor declarations | `hls_actor_source` | Ordered wire tags, explicit/inferred state and message limits |
| Hardware source selection | `xls_hardware_source` | Callback function/type closure before hardware validation; original forms retained for BEAM and source identity |
| Record analysis | `hls_records` | Resolved declarations, typed fields, serialized widths and checked defaults |
| Record DSLX | `xls_record_codegen` | Declarations and codecs over `xls_struct_codec` and the same field descriptors used by the host codec |
| Immediate or retained-call servers | `xls_gs_immediate`, `xls_gs_deferred` | Complete service rendering with the corresponding callback/scheduling model |
| State-machine semantics | `xls_statem_lower` | Checked callbacks and actor artifact; dedicated execution is rendered by `xls_actor_codegen` and `xls_statem_codegen` |
| Callback and expression lowering | `xls_callback_lower`, `xls_clause_lower` | Clause selection, ordered evaluation, bindings and first selected failure |
| Pattern, branch and binary operations | `xls_pattern_lower`, `xls_case_lower`, `xls_binary_lower` | Specialized operations over the shared clause state |

`hls_source:parse_file/2` accepts either source options or an already captured context. Options append the installed compiler include directory; a captured context is used unchanged. Source queries and record validation do not depend on the XLS backend. Type-provider `transpile/3` callbacks intentionally use `xls_clause_lower` for values, statements and failures: that is a backend extension hook, not source inspection.

The internal `xls_clause_lower.hrl` record belongs to expression lowering and its cooperating passes. Branches retain separate bindings, statements and failures; a join exports only values valid in every selected arm. `xls_clause_lower:print/1` renders scalar IR, `xls_dslx` structural syntax and textual leaves, and rejects compile-time phantom types. Adding a source query must not require exporting a lowering helper through `xls_parse`.

The supported expression, guard and failure semantics are documented in [control flow](control-flow.md), [bit syntax](bit-syntax.md), [entry outcomes](entry-outcomes.md) and [local helpers](local-helpers.md). Wire-tag ordering and generated-name constraints are in [actor names](actor-names.md).

## Alternate execution bodies

Compiler extensions can call `xls_parse:actor_artifact(Path, SourceOptions)` for a validated `hls_statem` artifact. It contains initialization, typed dispatch, ordered effects, internal events, retained replies, reductions and failure origins. Entry `evaluation` fields retain structured branch, field-access, effect-packing and result-constructor expressions until `xls_actor_codegen:artifact/3`; consumers can inspect them without parsing generated text. Unsupported actor kinds are rejected explicitly.

`xls_actor_codegen:artifact(Artifact, RuntimeImports, Body)` renders common semantics with an execution body and returns an `xls_emitted` artifact, preserving its allocated failure codebook. The body must preserve callback ordering, failure behavior and effect ownership. `xls_statem_codegen:body/1` supplies dedicated execution, and `xls_statem_codegen:artifact/1` renders that complete service. The corresponding `emit` functions return DSLX IO data without the retained metadata. These are source-level compiler interfaces: pin the compiler revision when consuming them. They are not a serialized deployment protocol.

## Shared source snapshot

`xls_actor_program:from_file(Path, SourceOptions)` compiles a complete actor once into an opaque in-process program; `from_file/3` accepts an explicit checked frame layout. `spec/1` returns the ordinary rendering artifact and `plan/1` its complete planning sidecar from that same lowering. No constructor accepts supplied artifacts or selected alternatives. Consumers retain the program unchanged; editing a returned map does not modify it. These views describe the captured source, so later file edits require a new program with the same intended layout. The program is not a saved build-input format or a replacement for saved-plan validation below.

`xls_actor_program:entry_effects(Program)` returns every effect in every entry layout across all phases, with `phase`, `layout` and zero-based `order`. It preserves the full typed field metadata, including constants, known bits, slices and layout-local storage offsets that express sharing. It neither filters alternatives nor joins them into a constant summary. Empty layouts contribute no effects; evaluation and failure obligations remain in the rendering artifact and planning sidecar. Consumers deriving channel constants must join every matching alternative rather than selecting a convenient phase or branch.

## Ownership-planning sidecar

`xls_statem_plan:from_file(Path, SourceOptions)` returns `{Artifact, Plan}` from one ordinary lowering; `from_file/3` accepts an explicit checked frame layout. `Artifact` is unchanged. `Plan` retains prepared callback clauses, typed helper signatures, entry branch programs and actor-wide protocol obligations before rendering discards their structure. It is an internal planning format, not a replacement renderer or a hardware optimization.

`xls_statem_plan:records(Plan)` and `callbacks(Plan)` expose complete resolved record declarations and ordered callback clauses without inspecting the opaque representation. `provenance(Plan)` returns exactly the original source path and raw binary source, artifact and planner digests. These are read-only snapshot views; provenance is distinct from canonical build identity and does not revalidate current files.

Use `xls_statem_plan:select(Plan, [{Phase, EventKind}, ...])` to inspect complete event families with their transitive helpers. Selection includes every clause in source order, including guards, failure/postponement alternatives and discarded evaluations; it does not select only successful outcomes. Initialization and reducers remain available. Provider calls are inventoried without assuming that providers depend only on their explicit operands.

Before consuming a saved plan, call `xls_statem_plan:validate(Path, SourceOptions, Plan)`. It recompiles the source, including includes, with the layout retained by the plan and compares the complete plan with compilation-local payload identities renamed consistently. Full source and rendering digests complement this check; a digest alone is not an equivalence proof. `manifest/1` emits a compact inventory without source bodies. Neither the plan nor a selected family establishes field independence, allowed concurrency, projection safety, deadlock freedom or physical locality; a transforming backend must establish those separately.

`xls_statem_plan:identity(Plan)` returns a versioned set of canonical source/preprocessing, closed-artifact, complete-plan and planner digests for build identity. Source filenames and include origins are relative to the actor directory; ordered include search roots are relative to the captured build directory. This permits relocation while preserving relative include topology, macro/feature values and ordering, source bodies, failure paths/lines and semantic `?FILE` expansions. The complete-plan digest is recomputed from current contents with origin aliases renamed bijectively, so splitting or merging aliases changes identity. Strict `validate/3` and the path-bearing provenance manifest remain unchanged. Generated actor DSLX uses a generic banner; the original source path remains in the artifact and provenance.

## Source constants under declared inputs

`hls_actor_constants:from_source(Forms, Phases, Messages)` analyzes validated, record-resolved actor source without executing its callbacks. `Messages` must overapproximate every possible cast, including startup configuration. Use `value/1` for an exact hardware-normalized value or `unknown_record/2` for a record with unconstrained fields. Entry and internal callbacks remain unrestricted. The result maps reachable phases to structural abstract data; `constant/1` extracts a term only when every component is known. Unsupported computation, recursion or exhausted analysis loses precision. `repeat_phase` retains updates in the current phase.

This analysis exposes facts to callers; it does not change generated code or grant specialization eligibility. Callers must bind facts to current source and justify the supplied input domain. `xls_phase_values` instead infers source-bound scalar marginals from arbitrary incoming messages and checked successful returns. The two analyses have different assumptions: a constant established under a configured message domain cannot substitute for an unrestricted phase fact.
