# Architecture and attribution experiments

Keep the 2×1-per-plane source/phi workload, both planes, generated callbacks, source-fragment collectors, event witness, two requested stages, calibrated model, compact FIFOs, physical harness and seed fixed. The reference is public commit 5b5a023. Experiments remain outside compiler defaults.

1. Replace shared actor execution and external state/mailbox RAM with dedicated actors holding state and bounded mailboxes in registers. Retain the reduction plane and existing routing/effect-window protocol. Prediction: 20–40% shorter native routed period, no cycle penalty, up to twice the arithmetic hardware. State feedback could instead prevent useful pipeline cuts; report that failure explicitly. Distinguish additional local effect buffering from elimination of shared execution.
2. Disable same-activation retirement-to-issue forwarding. Prediction: 10–25% shorter control path, 10–30% more cycles; the period×cycles product may lose. Keep all other code identical.
3. Separate callback dispatch from phase entry. Prediction: shorter arithmetic/control cones but another activation at phase transitions; measure the product rather than infer a gain from MHz.
4. Restore magnitude-based rounding and separately register egress handoff. These controls attribute the reciprocal and bypass effects under the current schedule, rather than reuse comparisons from a different model.
5. Inspect narrower fixed-point recurrence mappings. Preserve the integer range by reducing fractional precision in any application proposal; do not silently change application numerics. DSP count changes discretely, and less arithmetic cannot remove a separate scheduler control bottleneck.

Start with one matched physical seed and retain placement estimates, routed period, dominant path, area, normal/stalled cycles and timeouts. Recheck promising/ambiguous outcomes on a second seed. Native timing remains diagnostic, especially DSP cascades; EC2 is stopped. Check public events by per-actor sequence under backpressure and reset, since legitimate architectures may change cross-actor interleaving.

## Scheduling normalization control

The dedicated actor exposes a scheduling-only coverage gap: the default optimizer splits a 16-bit failure-code update into 65 guarded next values. Scheduling adds a 65-input NOR/AND and a 65-bit priority encoder, beyond the calibrated fan-in/encoder bounds. The optimized-IR audit reports zero gaps; auditing the normalized scheduled IR finds six. Compare `--split_next_value_selects=0` on both the shared reference and dedicated architecture. This keeps source semantics and calibration fixed while avoiding the expansion. Prediction before measurement: fewer control predicates may reduce area/fanout, but schedule and cycle effects are unknown. Retain the original split reference as a separate control; its freshly regenerated compact RTL is byte-identical to the previously routed candidate.

## Additional predictions before their runs

For the separate-entry control, expect roughly 10–20% shorter placement/routing period but 20–40% more cycles. For old magnitude rounding, expect 10–30% longer arithmetic delay and essentially unchanged cycles: the previous arithmetic probes favor the reciprocal. For registered phi egress, expect less than 10% period improvement and 0–10% more cycles; arithmetic may completely mask the isolated control improvement. These are hypotheses, not confidence intervals.
