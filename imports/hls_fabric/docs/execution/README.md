# Actor execution backends

`erl_hls` owns Erlang callback semantics and dedicated communicating actors. This repository adds physical sharing: multiple logical actors use an executor and state/mailbox storage. Logical actor identities, messages and callback behavior remain unchanged by placement.

Build with `rebar3 as test compile`. The dependency is pinned in `rebar.config`; for coordinated development, put the matching public checkout at `_checkouts/erl_hls`. Tools also accept `ERL_HLS_ROOT` when locating compiler sources.

## Compile and place

1. Normalize the logical graph with `hls_topology` from `erl_hls`.
2. Describe physical placement using `xls_shared_topology_profile`: choose scheduler groups, state/mailbox storage, queue depths and optional reduction placements.
3. Ask `xls_shared_topology_dslx:artifact_requirements/2` for each actor module's required options. Pass those options to `xls_shared_parse:to_xls/2`.
4. Emit the graph with `xls_shared_topology_dslx:emit/2`. Generate RAM bindings with `xls_scheduler_ram_v` and compile through the common `compile_xls.py` tool.

An ungrouped actor remains dedicated. Mixed graphs can contain both placements. The private backend validates its own generated namespace and physical options; the public compiler does not import this application. [Mixed topologies](mixed-topologies.md) describes routing and placement. [Reduction placement](actor-reductions.md) describes source fragments and aggregate delivery; [outboxes](actor-outboxes.md) describes independent publication. [State specialization](../state-specialization.md) removes topology-established configuration from shared mutable storage.

## Local activation semantics

`xls_shared_codegen:execution/1` renders pure DSLX activation functions from a closed `xls_parse:actor_artifact/2`. It reuses ordinary dispatch, entry/effect, continuation, reduction and gather lowering from the shared executor, leaving actor selection, storage and transport to the caller. It rejects physical service options and retained replies. An optional state projection must already be validated against the source and contain only instance-zero rows; the caller supplies a valid actor slot.

`local_initial()` creates the source state. `local_pending_at(raw, slot)` reports pending entry, continuation or completion work. `local_step_at(raw, frame, received, effects_reserved, slot)` returns `LocalStepResult`, with named `machine`, `effect_payload`, `effect_layout`, `effect_count`, `effects_valid`, `dispatched`, `directive`, `phase_boundary` and `egress_blocked` fields. `local_effect(layout, payload, index)` returns a `LocalEffect` with `port` and `frame`; use it only for a valid batch and `index < effect_count`. The slot-zero wrappers `local_step` and `local_pending` serve a single actor. `local_observe` returns `LocalObservation { initial_machine, pending, failure }`. `local_cycle` returns `LocalCycleResult { observation, step, effect }`; its observation describes the supplied state before activation, and its decoded effect belongs to the supplied outbox batch, independently of the returned step.

The caller must own the selected actor state and reserve a destination for its result. Apply the returned mailbox directive only when `dispatched` is true, and only once for that selected message. Retain postponed messages in sender order and hold every valid returned effect batch until accepted. `effects_reserved=false` allows a callback to commit with entry work pending; preserve that returned state and resume it when publication capacity becomes available. The functions provide neither mailbox storage nor connected-protocol admission.

Run `bash tools/test_local_execution.sh /path/to/xls /path/to/fresh-stage` after preparing the compiler dependency. Interpreter/JIT witnesses vary source arithmetic, guards and phase names, exercise malformed frames and output stalls, and cover two projected slots with all 128 mutable field values. Separate IR conversion checks reductions and gathers with continuations. These finite checks do not establish network progress or routed timing.

## Observe and reproduce

Open hardware sessions with `hls_shared_observation:open/2`, then bind actors using `hls_shared_debug_catalog:hardware/4`. Inspection still uses `hls_debug:info`, boundary counters/traces and physical wait queries. The explicitly installed local observer decodes scheduler metadata; incoming packets cannot choose executable decoders. See [debug targets](debug-targets.md).

`tools/prepare_xls_sim.sh STAGE` combines common compiler assets with shared actor artifacts, RAM bindings and private profiler hooks. The common VPI transport supplies accepted-edge samples; `test/rtl/xls_scheduler_profile.h` adds passive scheduler telemetry. Profile event meaning, SVG/Perfetto rendering and measurement commands remain in [profiling](../profiling.md).

All board experiments now live under `experiments/`. Existing report paths are preserved there. [CI coverage](../ci.md) separates routine backend witnesses from expensive complete-application measurements.

## Maintenance boundary

The common compiler's `xls_parse:actor_artifact/2` returns checked callback semantics: initialization, dispatch, effects, continuations, retained replies, reductions and source failures. `xls_actor_codegen:emit/3` renders those semantics with a supplied execution body. The artifact is a versioned-source interface through the dependency pin, not a stable serialized interchange format.

Private code owns reservation, actor selection, storage transactions, execution handoff, retirement, effect windows and offloaded reductions. Pipeline changes belong here. Dedicated actors continue to use the public execution body, including in mixed graphs; XLS can pipeline their generated procs independently.

The [scheduler ownership contract](scheduler-pipeline.md) describes reservations, visibility and stalls. The longer [pipeline plan](../../experiments/07-openxc7/yap/scheduler-pipeline-plan.md) records the remaining measurement and design work.

The source-bound actor builder adds a [clocked DSLX owner](../source-protocol.md#compile-a-clocked-source-actor) around these functions, with selected-head retirement and one ordered outbox. Its standalone RTL command enforces the fixed clock schedule; network integration and admission remain separate.
