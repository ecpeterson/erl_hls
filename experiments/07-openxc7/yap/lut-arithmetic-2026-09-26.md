# Fixed-schedule LUT arithmetic experiment

Use the best retained shared-scheduler core from the compact/accepted-push FIFO experiment. Its seed-1 route is 39.667 ns, limited by state-RAM-to-arithmetic propagation (20.4 ns logic, 19.2 ns routing), with 79.25 cycles/step, 33,171 LUTs, 22,008 FFs, 56 DSPs, 44 RAMB18 and eight RAMB36. Keep the exact RTL, harness, calibrated native binary, chip database, 40 ns constraint and seed.

- [x] Map the decoder with Yosys `synth_xilinx -nodsp`, retaining the normal mapped harness. Predict 32–36 ns and 2.54–2.85 µs/step, at an additional 4,000–10,000 LUTs. Check resources before routing; do not recompile or reschedule XLS.
- [x] Inspect whether the new path is arithmetic or control, and whether the gain depends on the native DSP arc costs. A LUT-only result removes dependence on DSP timing, but cannot qualify the old DSP baseline or the board clock. Prepare vendor validation rather than silently reusing DSP calibration for LUT arithmetic.
- [x] If a first route is competitive, compare both mappings at seed 2; otherwise reject it without a seed sweep. Preserve hashes, reports and required FF/RAM endpoint checks, then remove redundant physical intermediates.

This tests resource mapping and placement under a fixed schedule. No claim is made that the existing XLS model chooses an optimal LUT-only schedule. There is no protocol or latency change at RTL; sequential mapping checks and the retained behavioral witness remain the correctness basis for this experiment.

## Model dependency control, registered before implementation

The original DSP path includes B14→ACOUT7, which UG479 and the local primitive simulation model exclude. While the LUT route runs, restrict ACOUT/BCOUT to the corresponding selected input bit, retaining every numerical delay. Build a separate binary and replay saved placement. Predict several nanoseconds less reported delay or a change of limiting path; this changes the model, not circuit performance. Keep any placement-only comparison separate from routed results, and use the same model on both sides of any subsequent physical comparison.

## Outcome

The two-seed LUT/DSP comparison is tied (+0.23% mean step cost for LUTs) at +19.6% LUT area; reject wholesale DSP removal. The fixed-wire dependency correction reduces the reported historical period 39.667→38.551 ns and changes the limiting path to collector batch delivery. [Full results](../results/lut-arithmetic-2026-09-26.md) distinguish this model change from physical improvement.
