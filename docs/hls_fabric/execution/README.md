# Actor execution backends

`erl_hls` owns Erlang callback semantics and dedicated communicating actors. This repository adds physical sharing: multiple logical actors use an executor and state/mailbox storage. Logical actor identities, messages and callback behavior remain unchanged by placement.

Build with `rebar3 as test compile`. The dependency is pinned in `rebar.config`; for coordinated development, link the matching compiler checkout at `_checkouts/erl_hls` and its `apps/hls_runtime` directory at `_checkouts/hls_runtime`. External drivers accept an explicit `--erl-hls` checkout where needed; the selected compiler must have matching beams for the declared profile. See [build context](../building.md).

## Select and inspect a backend

`hls_build:plan/1` and the `hls-fabric` command select between two supported execution models:

| Backend | Execution/storage ownership | Public build result |
| --- | --- | --- |
| `source_protocol` | Source-bound actor owners, sender-local captures, checked native/host/device placement | Connected transport, network, boundary, application, bridge, deployment or mixed composition. |
| `channel_scheduler` | Dedicated actors or groups sharing an executor, state/mailbox storage and independent publication queues | Channel topology core, actor DSLX and any external RAM bindings/fragments. |

Use the [counter walkthrough](../building.md#one-build-boundary-two-execution-models) to build both models from one ordinary actor and topology. The source backend's `--kind` selects its composition boundary. Scheduler builds reject `--kind`; their configuration contains `sources`, `topology`, `placement` and optional `schedule`, `dslx_path` and `frame_payload_words`. Both write `source-build.json` for the same external executor. A backend change still needs a valid configuration and the selected backend's capability checks; these are not interchangeable implementations of every accepted program.

Inspect the checked hardware contract before invoking external compilation:

```sh
_build/default/rel/hls/bin/hls-fabric plan --backend channel_scheduler \
    --config apps/erl_hls/src/examples/counter/scheduler.config --stage profile
_build/default/rel/hls/bin/hls-fabric plan --backend channel_scheduler \
    --config apps/erl_hls/src/examples/counter/scheduler.config --stage placement
```

The primary `scheduler.config` keeps both counters dedicated. To share an executor, substitute `scheduler-ram.config`; it assigns the same actors to one group with block-RAM state and mailbox storage. That core requires the generated RAM connection fragments to be included in an enclosing shell.

`profile` names the backend, retained placement policy, selected ordinary frame ABI and structured clock schedules. `schedule` shows exact external compilation units. Source sampled clocks require one stage with input/output flops disabled; the framed application gateway has a separate two-stage output-registered schedule. Scheduler channel depths, placement and allowed pipeline/throughput options belong to its configuration. Those scheduling values are not physical timing measurements, and tool hashes exist only after the external executor inspects actual tools.

## Scheduler lowering

For ordinary development, `hls_scheduler_build` performs the following sequence behind `hls_build`; the individual APIs are useful when changing a lowering pass:

1. Compile every declared source and normalize the logical graph with `hls_topology` from `erl_hls`.
2. Normalize `placement` with `xls_fabric_topology_profile`, selecting scheduler groups, state/mailbox storage, queue depths and optional reduction placements.
3. Prepare `Generation = xls_fabric_topology_dslx:plan(Topology, Placement)` once. Obtain requirements with `artifact_requirements(Generation)` and pass them to `xls_scheduler_actor:to_artifact/2` using each source's captured context. Retain the emitted artifacts for debug projection; `xls_emitted:write/2` publishes the main DSLX and its generated helper modules. In-memory bundles compose `bytes/1` with `dependencies/1` relative to the main file directory.
4. Emit the graph with `xls_fabric_topology_dslx:emit(Generation)`. Its `analysis/1` supplies the retained scheduler and interfaces to `xls_scheduler_ram_v:bindings/3`; package those bindings, the hardware profile and unit schedule.
5. Invoke the independent `compile-source-build` driver, or another build system, against the emitted bundle.

An ungrouped actor remains dedicated. Mixed graphs can contain both placements. The fabric backend validates generated namespaces and physical options; the public compiler does not import this application. Dedicated actors need no external scheduler state/mailbox RAM. Shared RAM-backed cores expose their memory channels and supply connection fragments; an application shell still owns physical RAM instantiation, host gateways and board pins. [Mixed topologies](mixed-topologies.md) describes routing and placement. [Reduction placement](actor-reductions.md) describes source fragments and aggregate delivery; [outboxes](actor-outboxes.md) describes independent publication. [State specialization](../state-specialization.md) removes topology-established configuration from shared mutable storage.

## Source-protocol lowering

`hls_source_build` prepares one source snapshot and derives native ownership, publication/capture layouts and the selected network/application layers from it. Whole applications, multiple device roles and mixed BEAM/native actors have separate checked composition contracts. `hls_build` retains that same plan for inspection and writing; no test fixture or decoder preset is required. Follow the [build control path](../building.md#following-the-implementation) and [source-protocol guide](../source-protocol.md) for the owners of each boundary.

The profile selects the ordinary actor ABI through `frame_payload_words`, defaulting to three words: 32 header bits plus 96 payload bits. Generated `axis::Frame` uses the corresponding `FrameN<N>` layout. Compact captures and framed bridge envelopes have independent layouts; see [ordinary frame capacity](../building.md#ordinary-frame-capacity) for their separate limits.

## Local activation semantics

`xls_activation_codegen:emit/1` renders pure DSLX activation functions from a closed `xls_parse:actor_artifact/2`. It uses `xls_machine_codegen` for ordinary dispatch, entry/effect, continuation, reduction and gather execution, leaving actor selection, storage and transport to the caller. `xls_scheduler_codegen` composes that same machine with RAM access, a loader and scheduler retirement; activation output contains none of those services. It rejects physical service options and retained replies. An optional state projection must already be validated against the source and contain only instance-zero rows; the caller supplies a valid actor slot.

`local_initial()` creates the source state. `local_pending_at(raw, slot)` reports pending entry, continuation or completion work. `local_step_at(raw, frame, received, effects_reserved, slot)` returns `LocalStepResult`, with named `machine`, `effect_payload`, `effect_layout`, `effect_count`, `effects_valid`, `dispatched`, `directive`, `phase_boundary` and `egress_blocked` fields. `local_effect(layout, payload, index)` returns a `LocalEffect` with `port` and `frame`; use it only for a valid batch and `index < effect_count`. The slot-zero wrappers `local_step` and `local_pending` serve a single actor. `local_observe` returns `LocalObservation { initial_machine, pending, failure }`. `local_cycle` returns `LocalCycleResult { observation, step, effect }`; its observation describes the supplied state before activation, and its decoded effect belongs to the supplied outbox batch, independently of the returned step.

The caller must own the selected actor state and reserve a destination for its result. Apply the returned mailbox directive only when `dispatched` is true, and only once for that selected message. Retain postponed messages in sender order and hold every valid returned effect batch until accepted. `effects_reserved=false` allows a callback to commit with entry work pending; preserve that returned state and resume it when publication capacity becomes available. The functions provide neither mailbox storage nor connected-protocol admission.

Run `bash tools/hls_fabric/test_local_execution.sh /path/to/xls /path/to/fresh-stage` after preparing the compiler dependency. Interpreter/JIT witnesses vary source arithmetic, guards and phase names, exercise malformed frames and output stalls, and cover two projected slots with all 128 mutable field values. Separate IR conversion checks reductions and gathers with continuations. These finite checks do not establish network progress or routed timing.

## Observe and reproduce

Prepare the source-checked binding with `hls_shared_debug_catalog:prepare/4` during lowering. Runtime clients open hardware sessions with `hls_shared_observation:open/2` and attach that retained value using `bind/2`; `open/3` combines these runtime steps. Inspection still uses `hls_debug:info`, boundary counters/traces and physical wait queries. The explicitly installed local observer decodes scheduler metadata; incoming packets cannot choose executable decoders. See [debug targets](debug-targets.md).

`tools/hls_fabric/prepare_xls_sim.sh STAGE` combines common compiler assets with shared actor artifacts, RAM bindings and private profiler hooks. The common VPI transport supplies accepted-edge samples; `test/rtl/xls_scheduler_profile.h` adds passive scheduler telemetry. Profile event meaning, SVG/Perfetto rendering and measurement commands remain in [profiling](../profiling.md).

Prepared Snowflake and Phi experiments use `hls_build_profile:experiment/1` through a retained profile sidecar. Their specialized source generation and replay checks remain separate, but their literal channel schedule and completion-storage policy have the same owner as the public frontend. See [prepared experiment policy](../building.md#prepared-experiment-policy).

For the decoder-only profile, `phi_decoder_profile_build:emit(Config, Options)` returns `#{files => Files, result => Result}` without writing files. `Config` selects geometry, planes and shards; `Options` selects observations and effect-window partitioning. The simulation preparation script and debug/test fixtures use this same builder for actor DSLX, topology, RAM wrapper and observation metadata.

Its `phi_decoder_profile.inputs.json` binds the generated sources, wrapper and profile metadata by SHA-256 and carries the XLS RAM configurations from the scheduler bindings. A separate RAM recipe fingerprint identifies the compiled renderer and channel-name authority, independently of the chosen geometry and actor sources, for experiment comparisons. `compile_phi_decoder_profile.py` verifies those inputs before passing the configurations to the common XLS executor; it does not interpret DSLX to recover placement. Regenerate an old prepared stage before compiling it. The manifest checks consistency of trusted local build output, not authenticity or hardware equivalence.

Board shells, physical constraints, drivers and deployment probes live under `platforms/xc7`; decoder applications and their external drivers live under `apps/hls_phi` and `apps/hls_snowflake`. Remaining alternative implementations and ablations live under `experiments/`. Historical report paths are archive lookup keys, not current checkout paths. [CI coverage](../ci.md) separates routine backend witnesses from expensive complete-application measurements.

## Maintenance boundary

The common compiler's `xls_parse:actor_artifact/2` returns checked callback semantics: initialization, dispatch, effects, continuations, retained replies, reductions and source failures. `xls_actor_codegen:artifact/3` finalizes those semantics and a supplied execution body into an `xls_emitted` artifact. The artifact binds the main module and generated helper-module bytes to one failure codebook allocated from retained structured references; `xls_emitted:sites/2` additionally checks source locations at debug boundaries. The byte-only `emit/3`, `to_xls/2` and `xls_activation_codegen:emit/1` conveniences return only the main module for inspection; they do not carry generated imports. Fabric uses `xls_scheduler_actor:to_artifact/2` and `xls_activation_codegen:artifact/1` where metadata must survive specialization or owner composition. The artifact is a versioned-source interface through the dependency pin, not a stable serialized interchange format.

Private code owns reservation, actor selection, storage transactions, execution handoff, retirement, effect windows and offloaded reductions. Pipeline changes belong here. Dedicated actors continue to use the public execution body, including in mixed graphs; XLS can pipeline their generated procs independently.

The [scheduler ownership contract](scheduler-pipeline.md) describes reservations, visibility and stalls. The longer [pipeline plan](../../../platforms/xc7/yap/scheduler-pipeline-plan.md) records the remaining measurement and design work.

The source-bound actor builder adds a [clocked DSLX owner](../source-protocol.md#compile-a-clocked-source-actor) around these functions, with selected-head retirement and one ordered outbox. Its standalone RTL command consumes the same fixed sampled-clock profile as connected source builds. Standalone owner compilation establishes neither connected-protocol admission nor application progress.

The transport builder also emits [sender-local inbox receivers](../source-protocol.md#connect-sender-local-captures-to-an-actor), connecting that owner to typed capture selection, postponement and delayed release. Their output remains the ordinary source effect stream.
