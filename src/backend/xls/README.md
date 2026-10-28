# Erlang-to-DSLX backend

Use [`xls_parse`](xls_parse.erl) for a file-to-dedicated-service compilation, or [`xls_actor_program`](actors/xls_actor_program.erl) when several consumers need one checked state-machine snapshot. Neither path invokes XLS. Build packaging and external DSLX/IR/RTL execution belong to [`../../toolchain/`](../../toolchain/).

## Preparation, lowering and rendering

1. [`hls_source`](../../frontend/hls_source.erl) preprocesses the original module under an explicit source context. [`xls_hardware_source`](analysis/xls_hardware_source.erl) selects the local function/type/record closure rooted in hardware callbacks before unsupported host-only code can affect hardware validation. The full original source still identifies the compilation and remains available for BEAM compilation.
2. Actor preparation resolves records and helpers, classifies callback heads, and normalizes callback results and entry action lists. These stages retain Erlang forms and evaluation order. [`xls_statem_lower`](actors/xls_statem_lower.erl) coordinates state machines; the immediate and retained-call server paths use [`xls_gs_immediate`](actors/xls_gs_immediate.erl) and [`xls_gs_deferred`](actors/xls_gs_deferred.erl).
3. [`xls_clause_lower`](expressions/xls_clause_lower.erl) and its pattern, guard, case, binary and comparison collaborators turn prepared expressions into deferred computations. Their state owns source bindings, eager evaluation and the first selected failure. `xls_type` selects built-in compiler companions or custom-provider `transpile` callbacks at this boundary. The checked state-machine spec combines those computations with phase, effect, continuation, collection and caller-storage contracts.
4. [`xls_actor_codegen`](actors/xls_actor_codegen.erl) assembles common actor declarations and callback functions around a supplied execution body. [`xls_statem_codegen`](actors/xls_statem_codegen.erl) supplies the dedicated register-backed body; external fabric backends supply other execution policies. [`xls_emitted`](emission/xls_emitted.erl) allocates the retained structured failure references and renders the complete document to bytes with its codebook.

These representations serve different consumers:

| Representation | Authority and purpose |
| --- | --- |
| Preprocessed and normalized Erlang forms | Frontend and preparation passes retain source structure for semantic checking and lowering. |
| `xls_actor_codegen:spec()` | Checked callback semantics and deferred rendering fragments consumed by execution backends. Despite the `actor_artifact` entry-point spelling, this is not final emitted text. |
| `xls_statem_plan:plan()` | Optional source-bound planning sidecar from the same lowering; selections retain complete ordered callback families. `xls_actor_program` pairs it with the ordinary spec. |
| `xls_statem_reduction_ir:reduction()` | Closed typed reduction computations and storage requirements, with no Erlang syntax. It is one feature's semantic representation. |
| `xls_clause_lower:clause_state()` | Internal evaluation, binding and failure state; [`xls_clause_lower.hrl`](expressions/xls_clause_lower.hrl) shares it only among cooperating lowerers. |
| `xls_dslx:value()` | Ordered target-syntax nodes, nested fragments and opaque provider leaves. It is neither a source-semantics model nor XLS's typed optimization IR. |
| `xls_emitted:artifact()` | Final DSLX bytes and their allocated source-failure codebook, consumed by packaging and debug projection. Its digest is a consistency check, not an equivalence proof. |

Keep fragments structured until module finalization. `xls_dslx:indent/2` defers formatting; `xls_dslx:render/1`, `xls_clause_lower:print/1` and `xls_parse_io:indent/2` are terminal text operations. Rendering a fragment early would lose failure references needed by the enclosing artifact.

## Directory map

These are responsibility groups within one compiler application, not separate Erlang namespaces or a strict sequence of passes. Module names stay flat. Keep a feature's preparation and rendering collaborators together; the expression and type-provider APIs intentionally cooperate across directories.

| Directory | Responsibility | Starting points |
| --- | --- | --- |
| [types/](types/README.md) | Built-in provider operation lowering, descriptor rendering and typed codecs | `xls_type`, `xls_provider_*`, `xls_struct_codec` |
| [expressions/](expressions/README.md) | Source evaluation, matching, helpers, literal typing and variable scope | `xls_clause_lower`, `xls_callback_lower`, `xls_helpers` |
| [actors/](actors/README.md) | Actor/server preparation and execution fragments, collections, replies and observation | `xls_statem_lower`, `xls_actor_program`, `xls_actor_codegen` |
| [analysis/](analysis/README.md) | Hardware source closure, conservative value facts and shape checks | `xls_hardware_source`, `xls_message_facts`, `xls_phase_values` |
| [emission/](emission/README.md) | Deferred target documents, names, imports and final failure metadata | `xls_dslx`, `xls_emitted` |
| [topology/](topology/README.md) | Dedicated actor graph preparation and wiring | `xls_topology_dslx`, `xls_topology_graph` |

`xls_parse` remains the file-level facade at this directory's root. Each module's `-moduledoc` identifies its immediate callers and collaborators; export groups distinguish entry points, retained-data queries and rendering helpers.

Host provider functions and typed field offsets belong to [`hls_runtime`](../../../apps/hls_runtime/README.md). `xls_type` composes compiler conversions over those descriptors; `xls_struct_codec` renders layouts derived by `hls_field_layout`. See [provider extensions](../../../docs/type-providers.md) for callback ownership.

Topology preparation starts from normalized [`../../topology/`](../../topology/) plans and checked actor interfaces. It chooses compact family loops or materialized instance lanes, validates startup messages against the selected frame capacity, and then renders wiring. The explicit retained-interface overloads let a fabric preparation reuse one interface catalog; calling a convenience preparation again can reacquire those interfaces.

Analysis modules remain separate from execution semantics. Known bits and message facts describe already evaluated values; phase facts overapproximate successful callback boundaries. Their validation and source provenance do not establish protocol progress or authorize dropping failures. Algebraic simplification, inlining, scheduling and RTL lowering remain the external XLS compiler's responsibility.

See [actor compilation](../../../docs/actor-compilation.md), [control flow](../../../docs/control-flow.md), [expression lowering](../../../docs/expression-ir.md) and [source-quality checks](../../../docs/source-quality.md) for the intended contracts and validation policy. This directory map does not claim that every pre-existing declaration has a complete source contract; the audit reports remaining migration gaps.
