# Application timing calibration, 2026-09-26

The expanded, opt-in model schedules every optimized IR node in the 2×1-per-plane decoder testbench. The measurements include complete assembled-core timing, because proc-local operation costs exclude generated FIFO handshakes and global placement. No board clock is qualified.

[Use and reproduction](../docs/timing-model.md) · [Exact replay plan](xc7-timing-model-2026-09-26-plan.json) · [Hypotheses](../yap/timing-model/application-coverage.md)

## Measurement scope

The testbench contains four phi actors and four source actors, both X/Z planes, and four scheduler groups. Both models receive the same optimized IR, two requested pipeline stages and II=1. BEAM and normal/stalled RTL witnesses check the accepted event sequences. Mapped-core counts include the scheduler RAMs; the timing harness preserves that mapping instead of resynthesizing it with constant external inputs.

Target `xc7z030sbg485-1`, XLS `20bf86d9c9e90f9df380a0280a5973ce0c33a59a`, native Yosys 0.63+173 with ABC9, Vivado 2024.2. Vivado preserves mapped cells and nets, disables placement-time register replication, and checks exact pin connectivity and primitive parameters before and after routing. Reported periods come from worst internal setup slack at a requested 5 ns; external I/O and full board clock qualification are outside this experiment.

The replay plan varies payload width, fan-in and index width independently. It includes partial/default selectors, variadic logic, wide comparisons and shifts, array reads/updates, and nested reads. Measured limits reach 1024-bit payloads, 32 alternatives and 64-bit indices, but do not form a complete Cartesian product: 32-entry array updates with 32/64-bit indices are limited to 512-bit payloads because their 1024-bit mapped probes exceed this part's LUT capacity. Upper extrapolation and unsupported operations fail explicitly.

## Results

The corpus contains **983 distinct operation shapes**, producing **785 training rows** and 192 held-out error samples (including composed nested reads; wiring-only controls are excluded). The installed C++ estimator and the Python fitter agree for every shape in both cell-only and routing-inclusive modes. All 7,974 nodes of the small core and 14,021 nodes of the D3 regression have estimates; codegen completes without a fallback model.

| Small core, same IR and stage count | Unit model | Calibrated model |
|---|---:|---:|
| Normal cycles/step | 93.25 | 79.25 |
| Stalled cycles/step | 93.25 | 79.8333 |
| LUT cells | 33,509 | 33,650 |
| Flip-flops | 29,411 | 29,226 |
| Internal setup period, Vivado OOC | 20.046 ns | 15.758 ns |
| Normal cycles × setup period | 1.8693 µs | 1.2488 µs |

Both mappings use 56 DSPs, 44 RAMB18s and 8 RAMB36s. The implied step time improves **33.2%**, but does not reach 1 µs and is not a demonstrated operating point. One physical run per circuit measures a design difference, not placement variance. The final calibrated critical path has 24 logic levels, 10.189 ns logic delay and 5.546 ns net delay, from scheduler state RAM to an arithmetic register. The final table reproduces the validated RTL byte-for-byte.

The independent D3 regression retains 180 normal cycles/step; under output stalls it changes from 181.9583 to 182.875. BEAM witnesses match all 161 small-core and 723 D3 accepted events under both readiness patterns. Small-core profiling also checks 1,848 aggregate sends, receives and visits without payload mismatches. These are bounded regressions, not an equivalence proof.

Error is predicted minus measured delay. These statistics describe different held-out circuits, not repeated placement seeds:

| Model | Mean (ps) | Variance (ps²) | Mean absolute (ps) | Most optimistic (ps) | Most pessimistic (ps) |
|---|---:|---:|---:|---:|---:|
| Cell only | +113.85 | 41,297.60 | 147.39 | −403 | +1,061 |
| Including local routing | +16.75 | 250,643.95 | 281.50 | −1,278 | +3,354 |

The routed model underestimates 103/192 cases by an average 246.76 ps, and overestimates 87 by an average 329.10 ps; two are exact. The cell model underestimates 45 by an average 71.53 ps and overestimates 132 by 189.99 ps; fifteen are exact. The worst routed underestimate is a five-entry, 384-bit array read with a three-bit index: 2,491 ps predicted versus 3,769 ps measured. The nearly zero signed mean therefore does **not** establish conservatism.

[Machine-readable evidence](xc7-timing-application-2026-09-26.json) retains shape measurements, validation errors, audits and artifact fingerprints. The raw operation/primitive archive is 816,293,714 bytes, SHA-256 `138ec6e7c5fa3beb6ff7fb033f1f9e3c7aa00c4fa0ef2adcc8275f5036188e2d`; the final assembled-core archive is `a21c645879192b62f800414b1cbee7ec98bacb24a6dd95fff26e0ed37cf991a9`. Both are retained locally outside Git.

## Limits and reusable evidence

The table guides stage placement; it is not a conservative bound on routed timing. Summed operation costs put the small core’s largest scheduled stage at 49.870 ns, versus its 15.758 ns measured assembled-core setup period: isolated operation costs also accumulate substantial pessimism when mapping shares or fuses logic. Local operation routing does not predict global congestion, cross-proc ready paths or all arithmetic fusion. Default compiler settings remain unchanged.

The archived primitive measurements cover independent DSP A/B register depths 0–2 and M/P register choices, plus variable-address SRL16E/SRLC32E. Separate hard-block reports retain minimum-period and pulse-width requirements. The retained evidence contains 53 primitive instances, 2,744 arcs, and 967 clock checks in 56 reports; the largest captured minimum period is 3.292 ns and pulse-width requirement 0.780 ns. These records support later native-model extensions; registered DSP/SRL coverage is not enabled by collecting them.

Post-route rechecking found register replication in some earlier operation probes. Repaired circuits replace those samples. The eighteen earlier composed-kernel and primitive comparisons pass the new post-route graph checks, so their physical results remain valid. Calibration statistics from the smaller September 25 corpus are superseded by this campaign.
