# Erlang-to-DSLX backend

Use [`xls_parse`](xls_parse.erl) for a file-to-dedicated-service compilation, or [`xls_actor_program`](xls_actor_program.erl) when several consumers need one checked state-machine snapshot. Neither path invokes XLS. Build packaging and external DSLX/IR/RTL execution belong to [`../../toolchain/`](../../toolchain/).

## Preparation, lowering and rendering

1. [`hls_source`](../../frontend/hls_source.erl) preprocesses the original module under an explicit source context. [`xls_hardware_source`](xls_hardware_source.erl) selects the local function/type/record closure rooted in hardware callbacks before unsupported host-only code can affect hardware validation. The full original source still identifies the compilation and remains available for BEAM compilation.
2. Actor preparation resolves records and helpers, classifies callback heads, and normalizes callback results and entry action lists. These stages retain Erlang forms and evaluation order. [`xls_statem_lower`](xls_statem_lower.erl) coordinates state machines; the immediate and retained-call server paths use [`xls_gs_immediate`](xls_gs_immediate.erl) and [`xls_gs_deferred`](xls_gs_deferred.erl).
3. [`xls_clause_lower`](xls_clause_lower.erl) and its pattern, guard, case, binary and comparison collaborators turn prepared expressions into deferred computations. Their state owns source bindings, eager evaluation and the first selected failure. Type-provider `transpile` callbacks participate at this boundary. The checked state-machine spec combines those computations with phase, effect, continuation, collection and caller-storage contracts.
4. [`xls_actor_codegen`](xls_actor_codegen.erl) assembles common actor declarations and callback functions around a supplied execution body. [`xls_statem_codegen`](xls_statem_codegen.erl) supplies the dedicated register-backed body; external fabric backends supply other execution policies. [`xls_emitted`](xls_emitted.erl) allocates the retained structured failure references and renders the complete document to bytes with its codebook.

These representations serve different consumers:

| Representation | Authority and purpose |
| --- | --- |
| Preprocessed and normalized Erlang forms | Frontend and preparation passes retain source structure for semantic checking and lowering. |
| `xls_actor_codegen:spec()` | Checked callback semantics and deferred rendering fragments consumed by execution backends. Despite the `actor_artifact` entry-point spelling, this is not final emitted text. |
| `xls_statem_plan:plan()` | Optional source-bound planning sidecar from the same lowering; selections retain complete ordered callback families. `xls_actor_program` pairs it with the ordinary spec. |
| `xls_statem_reduction_ir:reduction()` | Closed typed reduction computations and storage requirements, with no Erlang syntax. It is one feature's semantic representation. |
| `xls_clause_lower:clause_state()` | Internal evaluation, binding and failure state; [`xls_clause_lower.hrl`](xls_clause_lower.hrl) shares it only among cooperating lowerers. |
| `xls_dslx:value()` | Ordered target-syntax nodes, nested fragments and opaque provider leaves. It is neither a source-semantics model nor XLS's typed optimization IR. |
| `xls_emitted:artifact()` | Final DSLX bytes and their allocated source-failure codebook, consumed by packaging and debug projection. Its digest is a consistency check, not an equivalence proof. |

Keep fragments structured until module finalization. `xls_dslx:indent/2` defers formatting; `xls_dslx:render/1`, `xls_clause_lower:print/1` and `xls_parse_io:indent/2` are terminal text operations. Rendering a fragment early would lose failure references needed by the enclosing artifact.

## Module map

Each module's `-moduledoc` describes its immediate callers and stage. Export groups distinguish construction/preparation, retained-data queries and rendering; an exported helper is not necessarily a user-facing compiler entry point.

| Area | Modules |
| --- | --- |
| File entry points and retained compilation | [`xls_parse`](xls_parse.erl), [`xls_actor_program`](xls_actor_program.erl), [`xls_statem_plan`](xls_statem_plan.erl) |
| Hardware source and helper preparation | [`xls_hardware_source`](xls_hardware_source.erl), [`xls_helpers`](xls_helpers.erl), [`xls_literal_types`](xls_literal_types.erl), [`xls_var_scope`](xls_var_scope.erl) |
| Callback and entry normalization | [`xls_callback_result`](xls_callback_result.erl), [`xls_statem_callbacks`](xls_statem_callbacks.erl), [`xls_statem_entry`](xls_statem_entry.erl), [`xls_init`](xls_init.erl) |
| Clause semantics and ordered selection | [`xls_clause_lower`](xls_clause_lower.erl), [`xls_callback_lower`](xls_callback_lower.erl), [`xls_pattern_lower`](xls_pattern_lower.erl), [`xls_guard_lower`](xls_guard_lower.erl), [`xls_case_lower`](xls_case_lower.erl) |
| Binary and comparison semantics | [`xls_binary_lower`](xls_binary_lower.erl), [`xls_comparison`](xls_comparison.erl) |
| Actor/server coordination | [`xls_statem_lower`](xls_statem_lower.erl), [`xls_gs_lower`](xls_gs_lower.erl), [`xls_gs_immediate`](xls_gs_immediate.erl), [`xls_gs_deferred`](xls_gs_deferred.erl) |
| Common and dedicated actor assembly | [`xls_actor_codegen`](xls_actor_codegen.erl), [`xls_statem_codegen`](xls_statem_codegen.erl) |
| Continuations and retained replies | [`xls_statem_continuation`](xls_statem_continuation.erl), [`xls_statem_event_codegen`](xls_statem_event_codegen.erl), [`xls_statem_reply_codegen`](xls_statem_reply_codegen.erl) |
| Scalar reduction contracts and rendering | [`xls_statem_reduction_lower`](xls_statem_reduction_lower.erl), [`xls_statem_reduction_ir`](xls_statem_reduction_ir.erl), [`xls_statem_reduction_codegen`](xls_statem_reduction_codegen.erl), [`xls_statem_reduction_service_codegen`](xls_statem_reduction_service_codegen.erl) |
| Indexed gathers and their progress layout | [`xls_statem_gather_lower`](xls_statem_gather_lower.erl), [`xls_statem_gather_layout`](xls_statem_gather_layout.erl), [`xls_statem_gather_codegen`](xls_statem_gather_codegen.erl) |
| Source-shape checks for contribution extraction | [`xls_type_shape`](xls_type_shape.erl), [`xls_pattern_totality`](xls_pattern_totality.erl) |
| Entry storage and outgoing-message facts | [`xls_entry_storage`](xls_entry_storage.erl), [`xls_known_bits`](xls_known_bits.erl), [`xls_message_bits`](xls_message_bits.erl), [`xls_message_facts`](xls_message_facts.erl) |
| Optional phase-value analysis and specialization | [`xls_phase_eval`](xls_phase_eval.erl), [`xls_phase_values`](xls_phase_values.erl), [`xls_phase_specialize`](xls_phase_specialize.erl) |
| Target syntax and final failure metadata | [`xls_dslx`](xls_dslx.erl), [`xls_parse_io`](xls_parse_io.erl), [`xls_failure_sites`](xls_failure_sites.erl), [`xls_emitted`](xls_emitted.erl) |
| Names, imports, types and record codecs | [`xls_names`](xls_names.erl), [`xls_dslx_imports`](xls_dslx_imports.erl), [`xls_nums`](xls_nums.erl), [`xls_named_bits`](xls_named_bits.erl), [`xls_record_codegen`](xls_record_codegen.erl), [`xls_struct_codec`](xls_struct_codec.erl) |
| Dedicated topology preparation and wiring | [`xls_topology_dslx`](xls_topology_dslx.erl), [`xls_topology_profile`](xls_topology_profile.erl), [`xls_topology_graph`](xls_topology_graph.erl), [`xls_topology_family_dslx`](xls_topology_family_dslx.erl), [`xls_topology_instance_dslx`](xls_topology_instance_dslx.erl), [`xls_topology_ingress`](xls_topology_ingress.erl) |
| Committed-state observation and debug projection | [`xls_actor_observation`](xls_actor_observation.erl), [`xls_actor_debug`](xls_actor_debug.erl) |

Topology preparation starts from normalized [`../../topology/`](../../topology/) plans and checked actor interfaces. It chooses compact family loops or materialized instance lanes, validates startup messages against the selected frame capacity, and then renders wiring. The explicit retained-interface overloads let a fabric preparation reuse one interface catalog; calling a convenience preparation again can reacquire those interfaces.

Analysis modules remain separate from execution semantics. Known bits and message facts describe already evaluated values; phase facts overapproximate successful callback boundaries. Their validation and source provenance do not establish protocol progress or authorize dropping failures. Algebraic simplification, inlining, scheduling and RTL lowering remain the external XLS compiler's responsibility.

See [actor compilation](../../../docs/actor-compilation.md), [control flow](../../../docs/control-flow.md), [expression lowering](../../../docs/expression-ir.md) and [source-quality checks](../../../docs/source-quality.md) for the intended contracts and validation policy. This directory map does not claim that every pre-existing declaration has a complete source contract; the audit reports remaining migration gaps.
