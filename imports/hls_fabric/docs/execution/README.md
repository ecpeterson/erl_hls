# Actor execution backends

`erl_hls` owns Erlang callback semantics and dedicated communicating actors. This repository adds physical sharing: multiple logical actors use an executor and state/mailbox storage. Logical actor identities, messages and callback behavior remain unchanged by placement.

Build with `rebar3 as test compile`. The dependency is pinned in `rebar.config`; for coordinated development, put the matching public checkout at `_checkouts/erl_hls`. External drivers accept an explicit `--erl-hls` checkout where needed; the selected compiler must have matching beams for the declared profile. See [build context](../building.md).

## Select and inspect a backend

`hls_build:plan/1` and the `hls-fabric` command select between two supported execution models:

| Backend | Execution/storage ownership | Public build result |
| --- | --- | --- |
| `source_protocol` | Source-bound actor owners, sender-local captures, checked native/host/device placement | Connected transport, network, boundary, application, bridge, deployment or mixed composition. |
| `channel_scheduler` | Dedicated actors or groups sharing an executor, state/mailbox storage and independent publication queues | Channel topology core, actor DSLX and any external RAM bindings/fragments. |

Use the [counter walkthrough](../building.md#one-build-boundary-two-execution-models) to build both models from one ordinary actor and topology. The source backend's `--kind` selects its composition boundary. Scheduler builds reject `--kind`; their configuration contains `sources`, `topology`, `placement` and optional `schedule`/`dslx_path`. Both write `source-build.json` for the same external executor. A backend change still needs a valid configuration and the selected backend's capability checks; these are not interchangeable implementations of every accepted program.

Inspect the checked hardware contract before invoking external compilation:

```sh
_build/default/rel/hls/bin/hls-fabric plan --backend channel_scheduler \
    --config src/examples/counter/scheduler.config --stage profile
_build/default/rel/hls/bin/hls-fabric plan --backend channel_scheduler \
    --config src/examples/counter/scheduler.config --stage placement
```

The primary `scheduler.config` keeps both counters dedicated. To share an executor, substitute `scheduler-ram.config`; it assigns the same actors to one group with block-RAM state and mailbox storage. That core requires the generated RAM connection fragments to be included in an enclosing shell.

`profile` names the backend, retained placement policy, fixed ordinary frame ABI and structured clock schedules. `schedule` shows exact external compilation units. Source sampled clocks require one stage with input/output flops disabled; the framed application gateway has a separate two-stage output-registered schedule. Scheduler channel depths, placement and allowed pipeline/throughput options belong to its configuration. Those scheduling values are not physical timing measurements, and tool hashes exist only after the external executor inspects actual tools.

## Scheduler lowering

For ordinary development, `hls_scheduler_build` performs the following sequence behind `hls_build`; the individual APIs are useful when changing a lowering pass:

1. Compile every declared source and normalize the logical graph with `hls_topology` from `erl_hls`.
2. Normalize `placement` with `xls_shared_topology_profile`, selecting scheduler groups, state/mailbox storage, queue depths and optional reduction placements.
3. Obtain each actor's requirements from `xls_shared_topology_dslx:artifact_requirements/2` and pass them to `xls_shared_parse:to_xls/2` using its captured source context.
4. Emit the graph with `xls_shared_topology_dslx:emit/2`, derive RAM bindings with `xls_scheduler_ram_v`, and package the retained hardware profile and unit schedule.
5. Invoke the independent `compile-source-build` driver, or another build system, against the emitted bundle.

An ungrouped actor remains dedicated. Mixed graphs can contain both placements. The fabric backend validates generated namespaces and physical options; the public compiler does not import this application. Dedicated actors need no external scheduler state/mailbox RAM. Shared RAM-backed cores expose their memory channels and supply connection fragments; an application shell still owns physical RAM instantiation, host gateways and board pins. [Mixed topologies](mixed-topologies.md) describes routing and placement. [Reduction placement](actor-reductions.md) describes source fragments and aggregate delivery; [outboxes](actor-outboxes.md) describes independent publication. [State specialization](../state-specialization.md) removes topology-established configuration from shared mutable storage.

## Source-protocol lowering

`hls_source_build` prepares one source snapshot and derives native ownership, publication/capture layouts and the selected network/application layers from it. Whole applications, multiple device roles and mixed BEAM/native actors have separate checked composition contracts. `hls_build` retains that same plan for inspection and writing; no test fixture or decoder preset is required. Follow the [build control path](../building.md#following-the-implementation) and [source-protocol guide](../source-protocol.md) for the owners of each boundary.

The ordinary actor frame is currently the fixed `axis::FrameN<3>` ABI: 32 header bits plus 96 payload bits. Compact captures and framed bridge envelopes have their own layouts. The profile records this fact without implying frame capacity is now configurable.

## Local activation semantics

`xls_shared_codegen:execution/1` renders pure DSLX activation functions from a closed `xls_parse:actor_artifact/2`. It reuses ordinary dispatch, entry/effect, continuation, reduction and gather lowering from the shared executor, leaving actor selection, storage and transport to the caller. It rejects physical service options and retained replies. An optional state projection must already be validated against the source and contain only instance-zero rows; the caller supplies a valid actor slot.

`local_initial()` creates the source state. `local_pending_at(raw, slot)` reports pending entry, continuation or completion work. `local_step_at(raw, frame, received, effects_reserved, slot)` returns `LocalStepResult`, with named `machine`, `effect_payload`, `effect_layout`, `effect_count`, `effects_valid`, `dispatched`, `directive`, `phase_boundary` and `egress_blocked` fields. `local_effect(layout, payload, index)` returns a `LocalEffect` with `port` and `frame`; use it only for a valid batch and `index < effect_count`. The slot-zero wrappers `local_step` and `local_pending` serve a single actor. `local_observe` returns `LocalObservation { initial_machine, pending, failure }`. `local_cycle` returns `LocalCycleResult { observation, step, effect }`; its observation describes the supplied state before activation, and its decoded effect belongs to the supplied outbox batch, independently of the returned step.

The caller must own the selected actor state and reserve a destination for its result. Apply the returned mailbox directive only when `dispatched` is true, and only once for that selected message. Retain postponed messages in sender order and hold every valid returned effect batch until accepted. `effects_reserved=false` allows a callback to commit with entry work pending; preserve that returned state and resume it when publication capacity becomes available. The functions provide neither mailbox storage nor connected-protocol admission.

Run `bash tools/test_local_execution.sh /path/to/xls /path/to/fresh-stage` after preparing the compiler dependency. Interpreter/JIT witnesses vary source arithmetic, guards and phase names, exercise malformed frames and output stalls, and cover two projected slots with all 128 mutable field values. Separate IR conversion checks reductions and gathers with continuations. These finite checks do not establish network progress or routed timing.

## Observe and reproduce

Open hardware sessions with `hls_shared_observation:open/2`, then bind actors using `hls_shared_debug_catalog:hardware/4`. Inspection still uses `hls_debug:info`, boundary counters/traces and physical wait queries. The explicitly installed local observer decodes scheduler metadata; incoming packets cannot choose executable decoders. See [debug targets](debug-targets.md).

`tools/prepare_xls_sim.sh STAGE` combines common compiler assets with shared actor artifacts, RAM bindings and private profiler hooks. The common VPI transport supplies accepted-edge samples; `test/rtl/xls_scheduler_profile.h` adds passive scheduler telemetry. Profile event meaning, SVG/Perfetto rendering and measurement commands remain in [profiling](../profiling.md).

The flat-topology and decoder experiment drivers retain separate scheduling policy even though they share the external XLS executor. The public `hls_build` profile does not yet replace their experiment-specific options or replay checks.

For the decoder-only profile, `phi_decoder_profile_build:emit(Config, Options)` returns `#{files => Files, result => Result}` without writing files. `Config` selects geometry, planes and shards; `Options` selects observations and effect-window partitioning. The simulation preparation script and debug/test fixtures use this same builder for actor DSLX, topology, RAM wrapper and observation metadata.

Its `phi_decoder_profile.inputs.json` binds the generated sources, wrapper and profile metadata by SHA-256 and carries the XLS RAM configurations from the scheduler bindings. A separate RAM recipe fingerprint identifies the compiled renderer and channel-name authority, independently of the chosen geometry and actor sources, for experiment comparisons. `compile_phi_decoder_profile.py` verifies those inputs before passing the configurations to the common XLS executor; it does not interpret DSLX to recover placement. Regenerate an old prepared stage before compiling it. The manifest checks consistency of trusted local build output, not authenticity or hardware equivalence.

All board experiments now live under `experiments/`. Existing report paths are preserved there. [CI coverage](../ci.md) separates routine backend witnesses from expensive complete-application measurements.

## Maintenance boundary

The common compiler's `xls_parse:actor_artifact/2` returns checked callback semantics: initialization, dispatch, effects, continuations, retained replies, reductions and source failures. `xls_actor_codegen:emit/3` renders those semantics with a supplied execution body. The artifact is a versioned-source interface through the dependency pin, not a stable serialized interchange format.

Private code owns reservation, actor selection, storage transactions, execution handoff, retirement, effect windows and offloaded reductions. Pipeline changes belong here. Dedicated actors continue to use the public execution body, including in mixed graphs; XLS can pipeline their generated procs independently.

The [scheduler ownership contract](scheduler-pipeline.md) describes reservations, visibility and stalls. The longer [pipeline plan](../../experiments/07-openxc7/yap/scheduler-pipeline-plan.md) records the remaining measurement and design work.

The source-bound actor builder adds a [clocked DSLX owner](../source-protocol.md#compile-a-clocked-source-actor) around these functions, with selected-head retirement and one ordered outbox. Its standalone RTL command consumes the same fixed sampled-clock profile as connected source builds. Standalone owner compilation establishes neither connected-protocol admission nor application progress.

The transport builder also emits [sender-local inbox receivers](../source-protocol.md#connect-sender-local-captures-to-an-actor), connecting that owner to typed capture selection, postponement and delayed release. Their output remains the ordinary source effect stream.
