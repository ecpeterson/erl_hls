# Local actor-boundary follow-up

Keep EC2 stopped. Use the preceding experiment's frozen compiler, calibration table, optimizer output, physical constraints and seed 1. Compare each intervention separately before combining anything. Preserve the default-split shared core as the best retained reference, separately from the unsplit architecture control.

- [x] Factor the bulk recurrence's rounded division by twelve into biased shift plus rounded division by three, preserving Q15.16. Prove the finite-width implementation, exercise compiled RTL at extremes and ties, and map it locally. Predict four rather than six DSPs; do not publish calibrated application timing until the new constant-product shape is measured. Prepare exact probe inputs for a later vendor batch.
- [x] Register the collector's aggregate output before demultiplexing: change only the two zero-depth aggregate channels to two-entry, non-bypassing FIFOs. Predict 40–48 ns versus dedicated seed-1 56.05 ns, but 14–29 extra cycles per step may erase the benefit. First inspect actual cycle cost and the resulting path.
- [x] Register the per-actor aggregate input instead: change the two FIFO declarations instantiated across both planes to depth two with no bypass. This isolates the demultiplexer as well as the collector; predict a similar clock range and latency cost, with additional storage. Keep only if the extra isolation helps period × cycles.
- [x] Permit two-cycle recurrence only for phi actor state, retaining one-cycle limits on other state and elastic channel adapters. Predict a 16–20 ns arithmetic stage, 40–45 ns routed period and 65–75 cycles/step. Check the actual schedule rather than assuming an II flag changes only the desired processes.

All application candidates must pass the complete normal/stalled BEAM witness and the reset/stall prefix comparison before physical measurements. Use one seed to reject clear losses; repeat promising or ambiguous comparisons with the existing second baseline seed. Inspect named paths to verify that the intended boundary is present and identify any replacement bottleneck. Remove redundant intermediate netlists/coverage exports after retaining hashes, endpoint audits, logs and measurements.

## Adaptive experiment: work-conserving dedicated egress

The collector register routed at 54.23 ns and needs 92 cycles/step: it fails the throughput criterion. Passive interface matching finds 1,946/1,984 effect batches waiting a cycle in the alternating-poll egress, versus 166/1,984 in the dedicated baseline. This is a benchmark-adapter artifact worth separating from the cost of the register itself. Before implementation: predict that a fair, work-conserving merge recovers 10–14 cycles/step after registration, with little improvement to the original baseline. Compile the leaf separately, substitute only its exact module definition, and validate order/stalls/reset. Route only if cycle savings plausibly make a candidate competitive; do not promote a new general backend from this adapter experiment.

## Adaptive experiment: register publication into the collector

The two-cycle actor recurrence routes at 53.88 ns with 90 cycles/step. Arithmetic leaves the critical path; actor state now drives the collector clock enable through a 3.8 ns logic / 50.1 ns routing path. Before implementation: retain the two-cycle actor recurrence and register only the two incoming reduction-batch FIFOs. Predict 35–42 ns and 90–110 cycles/step; this is useful only near the favorable end of both ranges. Check the FIFO intervention with the original egress first, then use the separately tested work-conserving egress to attribute any polling penalty. This boundary follows the observed actor-to-collector control path, not the earlier collector-to-actor arithmetic path.

## Cheap scheduling screen: relax only field feedback

Label only `__state_4_0` and `__state_4_1`, the two fixed-point field reads in the frozen phi actor, for two-cycle feedback; keep all other state arcs at one cycle. Before implementation: predict a 14–18 ns arithmetic stage and potentially 65–80 cycles/step. Skip physical work if scheduling or simulation shows no improvement. This checks whether relaxing control state unnecessarily contributed to the earlier latency cost.

## Outcome

Local checks and seven routes are complete; [the result report](../results/actor-boundaries-2026-09-26.md) records all misses. Keep production unchanged. The remaining work is the prepared vendor calibration and held-out kernel comparison; no EC2 work ran during this follow-up.
