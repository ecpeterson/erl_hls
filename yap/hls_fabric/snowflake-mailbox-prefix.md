# Mailbox prefix experiment

Reviewed 2026-10-01. Historical availability study. The K1 gather saved no cycles and was not adopted; K2 batching remains deferred. [Snapshot gathering](topology-specialization.md) takes precedence; reassess batching against the residual mailbox workload rather than reusing these opportunity counts as predictions.

The cached K1 gather keeps one state read/write and one executor transaction per contribution. Its independent cycle payoff is uncertain; it is a semantic control for bounded K2 batching. Before changing the datapath, measure whether a second same-window contribution is already waiting.

## Passive observation

`channel_probe.py --activations --prefix` records every physical mailbox write, ownership acquisition and actual ownership retirement. It reconstructs mailbox order, consumption and postponement, checking every accepted ticket's physical index and exact frame. A slot cannot be reused before the observed retirement. Same-cycle writes do not count as earlier availability. The full external transcript must remain identical.

A candidate requires logical head zero, a consumed nonterminal first contribution, an already written adjacent nonpostponed second contribution, matching envelope kind and epoch, and distinct valid direction numbers. Expected membership, previously seen members and reducer failure state are not observed. The acquisition and accepted-ticket samples are distinct, and neither is claimed to be the earlier combinational scheduling decision. These are permissive availability bounds, not legal-batch or cycle-savings measurements.

## Matched stress-eight observation

Source: `snowflake-probe/_build/control-combined8`, private b256dbf plus public effect packing 768b2d2, six shared executors, six-source/16-mailbox coordinator. Evidence: `gather-private/_build/prefix/combined8`, including frozen observer sources, hashes, raw events and checked summaries.

All 10,572 activations and queue retirements matched, and the external transcript remained identical. Snapshot and transfer contributions account for 8,160 activations. The following counts exclude 2,880 contributions that finish their phase.

| Observation boundary | Snapshot pairs | Transfer pairs | No second written | Total candidate pairs |
|---|---:|---:|---:|---:|
| Ownership acquisition | 2,736 | 1,696 | 848 | 4,432 |
| Accepted dispatch ticket | 2,784 | 1,776 | 720 | 4,560 |

Every candidate's second physical word became that actor's next accepted activation in the same phase. Greedily selecting disjoint adjacent pairs in each actor's recorded activation order gives 2,592 acquisition pairs (1,584 snapshot, 1,008 transfer) or 2,672 accepted-ticket pairs (1,584 snapshot, 1,088 transfer). These are the maximum disjoint subsets of those observed path edges, not predictions for the rescheduled design. The acquisition subset covers a potential 24.5% fewer executor activations if every permissive pair proves legal and can be consumed together without new costs. It does not predict step-rate improvement: added read cycles, shared-port contention, altered arrival times and critical-path changes still matter.

The sample establishes enough backlog to justify a K2 experiment if K1 remains a viable control. K2 must still stop at completion/invalid membership/key/postponement, reserve the captured committed prefix, preserve concurrently appended mail, and retire both slots atomically. A second conditional mailbox read must not recreate the rejected projection loader's unschedulable same-iteration read dependency.

## K1 control result

The [retained experiment](../../docs/hls_fabric/artifacts.md#historical-reports) (`experiments/snowflake/actors/mailbox-gather/README.md`) exercised all 8,160 folds. Every observed boundary and the complete external transcript remained cycle-identical to the ordinary-source control. The gather function itself is not where these ownership cycles are spent. K2 stays deferred; the availability measurement justifies a future bounded-batch investigation, not adopting K1 alone.
