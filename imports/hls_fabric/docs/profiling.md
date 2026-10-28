# Actor timing profiles

Capture a complete experiment before interpreting an actor's timing. Public state observations report committed actor state on their documented publication boundary; channel taps report pre-edge ready/valid. A public query cross-checks those projections independently. Sparse queries alone do not establish continuous waits.

Detailed profiles currently supplement public observations with simulator-private VPI taps and, for message ancestry, payload-observer aliases. They do not obtain all recorded events through the debug channel. The [Erlang inspection APIs](execution/debug-targets.md) already query simulated hardware over the real framed debug transport, but their snapshots and boundary counters/traces do not cover every event consumed by these profilers. VPI also carries that transport; transport bridging itself is distinct from directly observing simulator internals.

The [tooling policy](../STYLE.md#tooling-boundaries) favors a shared simulation/on-device observation path. Migration must preserve timestamps, commit coherence, identity, bounded capture and explicit loss reporting; polling snapshots cannot silently substitute for missing transitions. Existing private recordings remain useful diagnostics, not evidence that all their observations are available on-device.

For the cached D6 mesh:

```sh
python3 apps/hls_phi/tools/profile_phi_mesh.py BUILD --stage RUN --actors --transport
python3 apps/hls_phi/tools/phi_actor_profile.py RUN --device 0 \
  --erl-hls /path/to/erl_hls --publication-cycles 2
```

Use `--trace RUN/device0-trace.csv.gz` for an already retained subset and `--output STEM` to preserve previous analyses. Report commands load the profiler from the selected compiler root. Omit `--erl-hls` to use the `default` rebar profile, or choose another with `--profile NAME`. A report-only compiler checkout can differ from the experiment's pinned hardware dependency; retain both revisions. It writes a canonical timing graph, Perfetto-compatible JSON and distributional statistics. `device0-trace.csv.gz` is a digest-checked subset of the recording, reusable without simulation.

Use `--actor-devices 0` on the mesh capture to limit detailed internal handshakes to a representative board. All eighteen devices still run; every FIFO occupancy, actor publication and requested transport handshake remains recorded across the mesh. This reduces recording volume without substituting a smaller simulation. Two-device profiles accept `--actors` as well.

The adapter identifies work by matching ordered executor requests/results to committed per-actor writes. `--publication-cycles` specifies the required result-to-observation delay: two for the retained-completion pipeline, one for the earlier unbuffered layout (the default). Every retirement must match; execution must still take one clock. Changed buffering or ambiguous attribution fails analysis. Capture-tail work is bounded by one reservation per actor and excluded from duration samples. State reads follow either the scheduler's own port or the RAM owner identified by its dispatch-ticket FIFO.

Reduction transitions use manifest-described status, site, key and remaining count. Per-slot outbox acceptance identifies the producing result. The credited final effect must be accepted or continuously held at the registered output; a backpressured credit can also outlive that effect.

Replicated schedulers retain separate bank and slot identities. Offloaded reductions appear as aggregate completions; intermediate contributions do not write actor state. Fragment queues show partial progress, while the actor's remaining count stays at its opening value. A lack of observed mailbox/internal candidates does not imply that no aggregate is pending inside the scheduler.

For offloaded windows, the graph joins each fragment's FIFO arrival, the committed opening token, the collected aggregate and the matching executor visit. Fragment-depth counters retain queued lookahead. Per-fragment order and committed site/key must agree. Statistics separate arrival spread, collection latency, input-queue/polling wait, mux forwarding, scheduler capture and executor admission. Aggregate handoffs follow per-actor FIFO ordinals and the mux's accepted input order; concurrent or inverted selections fail analysis. The first analysis retains collector bindings from the checked schedule metadata; later replay uses that JSON without Erlang or the original build tree.

Execution slices run from accepted executor request to committed **observation**, including the checked publication delay. Outbox reservation slices end at credit acceptance. Their final effect may still be held in an output register: its separate marker and `last_effect_cycle` record downstream acceptance. Counters retain mailbox depth and the observed reservation flag. A work slice's hover details include actor identity, phase, reduction state, exact cycles and the attribution evidence.

Boundary acceptances render as one clock-width block. Their logical duration remains zero: a same-cycle bypass is still legal, and the block does not assert computation latency. Each reduction join labels its latest required input, retaining ties.

The **local progress** lane partitions completed actor activity into required-input waits, collect/fold, aggregate queue/transfer, scheduler pending, RAM read, execution and publication. Ordinary activation gaps retain observed mailbox occupancy and phase; missing evidence remains unclassified. These spans describe an actor's dependencies, not whole-device utilization. Outbox drainage can overlap waiting for new inputs, so reservation alone is not evidence of a scheduling stall. Public mailbox observations lag their sampling edge by one clock.

The local graph contains actor-state, offloaded-window and outbox-credit dependencies. It does not pair incoming messages with their producers. Use the [common profiler's window and rendering commands](https://github.com/ecpeterson/erl_hls/blob/main/docs/profiling.md) to inspect retained data; windowing explicitly reports lost boundary dependencies.

With packed links, `analysis.json` counts both accepted transfers and their useful protocol words. Transfer occupancy alone can overstate bandwidth when transfers are partially filled. `packed-transport.json` checks packets against the peer's receive log and measures per-lane outstanding frames and header-to-return round trips at the public wire boundaries. These counts exclude unsent staged frames; credit arrival precedes its eventual use by the packetizer. They do not reuse the serial arbiter's internal-choice reconstruction.

The shared packet decoder recognizes full and compact headers and counts only transmitted words, retaining each word's acceptance time. Reconstructed headers and zero padding consume no measured bandwidth. A partially recorded final packet remains explicitly incomplete.

For comparisons against a justified service lower bound, retain absolute intervals and add a logarithmic view of `interval − bound`. State the bound's derivation and scope; an asymptotic bandwidth bound need not constrain every finite interval. Compute arithmetic statistics before plotting. Identify changing bounds when widths, formats or work budgets differ; report zero/negative residuals explicitly rather than clipping them onto a log axis.

## Connected messages

Add `--messages` to a fresh mesh capture with `--actors --transport` on all devices, then reconstruct cross-board deliveries:

```sh
python3 apps/hls_phi/tools/profile_phi_mesh.py BUILD --stage RUN --actors --transport --messages --compress-capture
python3 apps/hls_phi/tools/phi_message_profile.py RUN --erl-hls HARDWARE_DEPENDENCY
python3 apps/hls_phi/tools/phi_message_report.py --run example RUN --output REPORT \
  --erl-hls /path/to/erl_hls
```

Message reconstruction selects one compiler for both Erlang route binding and profile export; its default rebar profile is `test`, selectable with `--profile NAME`. Use the experiment's pinned hardware dependency when binding retained deployments. The compiler must provide the packaged profiling tools; source helpers and Erlang beams come from that same root. This mode requires source-fragment reductions, full-format packets, one reset epoch and capture from reset. It emits compressed canonical and Perfetto graphs. `phi_message_report.py` renders a reduction handoff; `phi_mailbox_report.py` accepts the same arguments and renders an ordinary delivery plus a retry when present. Its remote-message intervals separate receive forwarding, scheduler admission and first selection over the same message population. Both retain source-profile digests.

A passive observer records every accepted payload, including repeated identical values. Deployment source ports and ordered lane ordinals establish identity; checked payload bits corroborate it. The graph connects producer activation, effect acceptance, packetizer admission, complete peer delivery, fragment arrival, collection and consuming activation. It rejects inconsistent order, payloads or clock boundaries. Payload aliases are retained for observation; the exporter checks that application cells, ports and public debug projections are unchanged. Ordinary-message analysis requires complete payload bits. Missing final-edge evidence is disclosed; missing earlier evidence fails analysis. Saved actor reconstructions and per-device extracts are checked against their inputs before reuse. `--compress-capture` writes cycle observations directly to gzip without a large raw intermediate. Failed captures retain an unpublished `.partial` file. Successful mesh captures discard the simulation executable and generated payload-observer RTL; recordings, manifests, source digests, logs and the compiled device cache remain. Use `--keep-simulation` to retain those intermediates for repeated RTL execution. `cycle-trace.csv.gz` may also replace the raw CSV after capture; replay verifies the decoded bytes against the same digest.

Causal arrows express required data/state dependencies. Outbox-credit ordering is separate resource evidence and does not enter causal paths. The optional observed-predecessor overlay highlights latest recorded prerequisites, retains ties and discloses unexplained gaps and truncated roots. It describes this execution, not a rescheduling prediction. Boundary spans include service and waiting; they are not occupancy measurements. Acceptance blocks occupy one clock visually while retaining zero logical duration.

Ordinary frames follow accepted FIFO/mux ordinals, checked deployment routing, and physical mailbox rows. Admission assigns an identity that survives postponement and is retired on consumption; reusing the row creates a new identity. The graph includes the selected RAM read, the dispatching activation, and any phase boundary that releases a postponed message. A fetched frame which the executor ignores is visible but is not a causal input to that activation. Host ingress and deployment startup are explicit external roots.

Mailbox replay currently requires one ordinary producer stream per actor, fixed generated executor layouts, and healthy execution. Unsupported layouts, ambiguous producer ordering, lost interior observations and inconsistent row reuse fail analysis. Capture-tail work and pending messages are reported separately. Admission-to-selection spans include semantic and resource waits: they do not isolate arbitration overhead or prove that rescheduling would shorten a step. [The matched baseline/packed study](artifacts.md#historical-reports) (`experiments/results/message-causality-2026-09-23.md`) illustrates the current evidence and limits.

## Whole-step attribution

`phi_step_report.py` joins independently decoded public status frames to their producing effects by complete frame contents, stream and actor coordinates. It checks every measured round boundary against `progress.json`, then follows causal predecessors across rounds. New captures retain `status-events.json`; an older capture can obtain it through `hls_phi_memory_metrics:status_events/1` without another simulation.

```sh
python3 apps/hls_phi/tools/phi_step_report.py RUN --output REPORT \
  --erl-hls /path/to/erl_hls --step 12
```

`step-contributors` retains every required branch back to the preceding status boundary, including its carry-in events. `step-latest` groups the latest observed prerequisites into readable boundary tracks; tied branches remain separate. Both export canonical graphs and Perfetto traces. The elapsed overlay partitions one representative path; it adds no causal edges. `step-budget.json` includes componentwise bounds over tied alternatives and one continuous chain across the measurement window, which avoids repeatedly charging the final status-output tail. Those bounds are observations, not predicted savings from rescheduling.

For latency sensitivity, `profile_phi_mesh.py --link-stages N` places N elastic source-clock stages before each unchanged asynchronous FIFO. The default is one; zero requires periodic stalls to be disabled. Every direction, including credit returns, crosses the selected stages. This changes latency and elastic storage, not link width or sustained stage bandwidth. It is a testbench perturbation, not a physical Ethernet model or a proposed CDC optimization. Retain the complete application witness and compare against the same compiled board tile.
