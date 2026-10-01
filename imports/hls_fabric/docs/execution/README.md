# Actor execution backends

`erl_hls` owns Erlang callback semantics and dedicated communicating actors. This repository adds physical sharing: multiple logical actors use an executor and state/mailbox storage. Logical actor identities, messages and callback behavior remain unchanged by placement.

Build with `rebar3 as test compile`. The dependency is pinned in `rebar.config`; for coordinated development, put the matching public checkout at `_checkouts/erl_hls`. Tools also accept `ERL_HLS_ROOT` when locating compiler sources.

## Compile and place

1. Normalize the logical graph with `hls_topology` from `erl_hls`.
2. Describe physical placement using `xls_shared_topology_profile`: choose scheduler groups, state/mailbox storage, queue depths and optional reduction placements.
3. Ask `xls_shared_topology_dslx:artifact_requirements/2` for each actor module's required options. Pass those options to `xls_shared_parse:to_xls/2`.
4. Emit the graph with `xls_shared_topology_dslx:emit/2`. Generate RAM bindings with `xls_scheduler_ram_v` and compile through the common `compile_xls.py` tool.

An ungrouped actor remains dedicated. Mixed graphs can contain both placements. The private backend validates its own generated namespace and physical options; the public compiler does not import this application. [Mixed topologies](mixed-topologies.md) describes routing and placement. [Reduction placement](actor-reductions.md) describes source fragments and aggregate delivery; [outboxes](actor-outboxes.md) describes independent publication. [State specialization](../state-specialization.md) removes topology-established configuration from shared mutable storage.

## Observe and reproduce

Open hardware sessions with `hls_shared_observation:open/2`, then bind actors using `hls_shared_debug_catalog:hardware/4`. Inspection still uses `hls_debug:info`, boundary counters/traces and physical wait queries. The explicitly installed local observer decodes scheduler metadata; incoming packets cannot choose executable decoders. See [debug targets](debug-targets.md).

`tools/prepare_xls_sim.sh STAGE` combines common compiler assets with shared actor artifacts, RAM bindings and private profiler hooks. The common VPI transport supplies accepted-edge samples; `test/rtl/xls_scheduler_profile.h` adds passive scheduler telemetry. Profile event meaning, SVG/Perfetto rendering and measurement commands remain in [profiling](../profiling.md).

All board experiments now live under `experiments/`. Existing report paths are preserved there. [CI coverage](../ci.md) separates routine backend witnesses from expensive complete-application measurements.

## Maintenance boundary

The common compiler's `xls_parse:actor_artifact/2` returns checked callback semantics: initialization, dispatch, effects, continuations, retained replies, reductions and source failures. `xls_actor_codegen:emit/3` renders those semantics with a supplied execution body. The artifact is a versioned-source interface through the dependency pin, not a stable serialized interchange format.

Private code owns reservation, actor selection, storage transactions, execution handoff, retirement, effect windows and offloaded reductions. Pipeline changes belong here. Dedicated actors continue to use the public execution body, including in mixed graphs; XLS can pipeline their generated procs independently.

The [scheduler ownership contract](scheduler-pipeline.md) describes reservations, visibility and stalls. The longer [pipeline plan](../../experiments/07-openxc7/yap/scheduler-pipeline-plan.md) records the remaining measurement and design work.
