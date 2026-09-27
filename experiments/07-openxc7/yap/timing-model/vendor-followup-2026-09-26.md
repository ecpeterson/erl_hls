# One vendor session for the next timing experiments

The batch combines pending calibration with independent full-core controls. Keep the board target, Yosys mapping, preserved netlists and 5 ns OOC constraint fixed. Do not treat a successful internal setup report as board qualification.

- [x] Measure the previously prepared exact 35×37→71 constant product and validate the reference/factored bulk kernels. The six-to-four DSP result is known; before inspecting vendor outcomes, expect 5–20% shorter kernel delay, with extra carry logic as the principal counterhypothesis. Application timing may improve only 0–10% if control replaces arithmetic.
- [x] Extend the operation table over the observed 65-way predicate limit and a bounded neighborhood: 64/128-way logic and selectors, 128/256-bit encoders, and 96/128-bit signed/unsigned products. Hold out irregular widths/counts, including 65-way cases. Keep unsupported larger payload/fan-in combinations explicit.
- [x] Measure the retained DSP/LUT shared mappings and the architectural/fusion/boundary controls under the same preserved-circuit flow. Native results motivate these comparisons but do not supply a reliable quantitative vendor ranking. Record the comparison before choosing any new defaults.
- [x] Collect direct/cascade A/B output arcs with unregistered and likely registered input modes. Existing primitive archives cover arithmetic output modes but omit these outputs. Numerical delay calibration is separate from proving the dependency filter.
- [x] Re-audit optimized and scheduling-normalized application IR with the expanded table, regenerate the factored application, and measure its mapped full core during this session.
- [x] Retrieve compact raw reports, SDF and mapped inputs; verify hashes and audits before declaring the host releasable. Preserve replay plans, not duplicate build caches.

The first three already prepared arithmetic fixtures and the two full mapping controls were launched before writing this inventory; no outcomes beyond successful completion of the constant-product run had been inspected. No training row is inferred from an application result. All changes remain confined to the experiment folder.

## Cascade numeric correction, before implementation

The audited direct/cascade pilot SDF gives 613 ps A→ACOUT, 623 ps B→BCOUT, 442 ps ACIN→ACOUT and 415 ps BCIN→BCOUT, versus the coarse model's 5.40/3.85/5.20/3.61 ns. Check the complete mode corpus, then replace only these four fully combinational selected-bus costs. Keep other DSP dependencies/delays and registered-mode coverage unchanged. Expect about 9.5 ns less modeled logic for two A cascade forwards in isolation, but little or no shared-core frequency change where control routing already limits timing. Compare retained placement without moving cells; do not call a reporting change a circuit speedup.

## Matched normal-lowering architecture control

After seeing the unsplit dedicated core at 21.675 ns, use the new 65-way predicate coverage to compile dedicated actors with normal next-value splitting. The shared default-split control already exists. Expect approximately 64.5 cycles/step and a period within ±10% of the unsplit dedicated result: arithmetic is unchanged, but state-update enables and placement may differ. The candidate needs less than about 19.5 ns to beat 15.846 ns × 79.25 cycles for the shared control. Keep this separate from attributing the prior unsplit architecture delta.

## Both field components, before implementation

The audited default bulk-only result is 15.851 ns versus 15.846 ns unchanged; its critical multiplier is the untouched 37×39→76 center product. Apply the same factorization to the center numerator after proving that `6*a + 2*b + sum` fits signed 36 for signed-32 fields and a signed-34 four-neighbor sum. Preserve the anyon offset and final saturation. Expect the same calibrated 35×37→71 product, 40 rather than the original 56 DSPs, unchanged 79.25 cycles/step, and 13–15 ns if arithmetic remains limiting. A replacement control path may leave the clock unchanged. First prove/validate the isolated expression, then compare the default shared core at the same 5 ns constraint.

## Selector edge diagnostics

The largest new routing underestimate is the held-out 24-bit, 65-case default selector (2.753 ns). Before measuring more points, suspect the extra incomplete mux group just above 64 cases; expect 66 cases to remain within roughly 20% of 65, with a discontinuity compared with 63 or 127 if that explanation is right. Collect 63/66/95/127 cases at width 24 now. These adaptively chosen diagnostics do not enter the 848-row fit or its 216-sample held-out accuracy claim; retain them to investigate a better shape model locally without another vendor session.

## Outcome and rejected measurements

Completed 87 calibration additions, 16 legal cascade fixtures, four whole arithmetic kernels, 22 core/constraint configurations and four adaptive selector diagnostics. See the results report for predictions versus observations. The first cascade fixture exposed dedicated outputs to fabric; routing rejected it, so its measurements were discarded and the three-DSP fixture replaced it. One large selector timed out at 900 seconds under contention and completed with identical inputs under a 2,400-second budget. Only the successful, fully audited run enters the corpus.

The adaptive selector diagnostic refutes a simple 64-case boundary explanation: 95/127 cases have much larger misses, and the 127-case path contains 33 serial MUXF8s. Keep these out of the held-out accuracy aggregate; investigate the emitted ternary chain and its mapping locally.
