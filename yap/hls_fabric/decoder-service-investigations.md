# Decoder service qualification

`Notes/erl_xls/Roadmap.md` is the sole active task list. This note supplies G5’s acceptance criteria if current Snowflake service becomes the selected application bottleneck; it neither starts a decoder architecture campaign nor requires a QEC threshold study. P4 separately owns timed acquisition for the application baseline.

## Current gap

The maintained [Snowflake example](../../apps/hls_snowflake/README.md) builds an ordinary D2/H2 actor graph. [The CI oracle](../../apps/hls_fabric/test/hls_ci_snowflake.erl) uses eight fixed syndrome masks, [the driver](../../tools/hls_fabric/test_protocol_snowflake.py) assumes six corrections per sender, and [the public-pin scoreboard](../../apps/hls_fabric/test/rtl/protocol_snowflake_tb.sv) permits at most two sheets ahead of completed rounds. That is useful finite functional coverage, but its input timing follows decoder progress and cannot establish sustained independently offered service or overload behavior.

Snowflake consumes generated syndrome sheets; the integrated phenomenological-noise actors belong to Phi/repetition. Longer Snowflake runs should reuse the existing reference/noise inputs and ordinary BEAM actor oracle, without claiming that those Phi actors are already wired into Snowflake.

## Conditional service workload

Use the existing D2/H2 source graph first. Make vectors and per-sender correction counts data-driven; compile one graph and reuse its exact RTL for different finite streams. Keep the eight-sheet regression in CI and expose longer runs as an opt-in command. Source generation/oracles belong with the application; external simulation and report processing may remain outside Erlang.

Offer sheets on a schedule independent of decoder readiness. A blocked producer retains pending sheets rather than dropping them or shifting their nominal offer times. Count offered, accepted, completed and pending work, including empty correction sheets. Preserve sheet identity, correction order per sender and the final drained horizon. Record the external backlog separately from finite hardware queues.

Use seeded phenomenological data/measurement noise with exact geometry, probabilities and seeds retained. The historical 0.5% main, 0.2% sensitivity and 2.5% stress cohorts are useful candidates, not a requirement to run a matrix. Select one main stream plus a blocked-output and overloaded control. These probabilities are model inputs, not circuit-level physical error rates.

## Acceptance

- Exact BEAM/reference/public-RTL agreement on the finite workload, including empty outputs, variable correction counts and final drainage.
- Independent offer, acceptance and completion timestamps; backlog trajectory, service/latency distributions, queue peaks and explicit incomplete tail.
- Stable retained outputs under stalls, bounded hardware ownership, no accepted-input loss, and a deliberate overload that accumulates visible external backlog.
- A rejecting scoreboard control; a longer positive recording alone is insufficient to validate the measurement.
- Retained source/tool/artifact identities and failures. Simulations are witnesses; no unrestricted progress, stability or decoder-correctness claim.

Measure cycles first. Convert service to time only with the actual same-candidate routed period, and distinguish static timing from a demonstrated live rate. The historical 1 MHz goal needs this workload qualification and physical evidence; increasing a simulator's nominal clock does not establish it. Once a useful service target is demonstrated, prioritize device fit and burst margin over higher peak rate.

## Analysis and later architecture work

G4 in the master owns predictive-model work; the [spacetime evidence](https://github.com/ecpeterson/hls_spacetime/blob/main/yap/spacetime-visualization.md) records existing temporal/physical comparisons. Extend a model only for a selected intervention, require exact baseline replay, and model changed credits, ownership and finite resources before forecasting downstream schedules. Subtracting observed waits or shortening one physical path is not a complete-sheet prediction.

A later architecture proposal must identify eliminated transactions, competing dependencies, state/access costs and a rejection criterion before hardware work. Preserve source-defined ordering, callback failures, early arrivals, output ownership and debug coherence. Snapshot gathers, scalar reductions and collection retirement have different contracts; do not combine them merely because they use similar storage.

Larger spatial windows, concentration/halo replication, circular storage, regular-region lowering and independent QEC validation remain conditional directions under G5 in the master. Whole-code distance and temporal depth are separate from a spatial commit region and halo. None is required to make the present application useful for compiler development.

## Retained history

The [pre-reconciliation plan](https://github.com/ecpeterson/hls_fabric/blob/28f8bd1562f7f429a8f482c4d73776b04cdc2e31/yap/decoder-service-investigations.md) preserves the detailed October service-model, physical-locality and regular-region hypotheses. It records the D3/H3 scheduler control, conditional receiver replay, rejected continuation experiment and all original references. Those checklists are historical, not another active queue.

The [earlier custom-controller screen](https://github.com/ecpeterson/hls_fabric/blob/692ee4c769cbe369d4572a5b65bc8458fb712947/yap/decoder-service-investigations.md#registered-next-screen-2d-workload-and-bounded-service), [autonomous-stream result](snowflake-autonomous-stream.md), [window study](snowflake-window-scaling.md), [topology campaign](topology-specialization.md) and [physical architecture evidence](physical-architecture-options.md) retain their distinct designs and qualifications. Historical custom-controller 1 MHz cohorts do not establish current actor/source-protocol throughput. Locate original measurements through [artifact lookup](../../docs/hls_fabric/artifacts.md#historical-reports); no measurement is repeated or reinterpreted by this reconciliation.
