# Local-owner physical timing gate

Preregistered before full-window synthesis. Use the complete d=3 surface window (36 vertices, 51 edges), unchanged 32-bit cluster IDs and Erlang-lowered transitions. Begin with one registered global busy reduction, not the replay’s assumed seven-clock tree. Check raw and mapped RTL against the same complete phase witnesses before timing it.

The area prior is 15k–35k XC7 LUTs, 6k–20k FFs, no DSP or BRAM. The isolated merge kernel has a long comparison/priority chain; expect kernel evaluation, rather than a 36-input Boolean busy reduction, to be a leading timing path. There is no defensible full-window frequency estimate yet. Test the assumed 125 MHz directly with an 8 ns constraint; retain the achieved setup period, hold/pulse checks, logic/routing split and endpoint identities even if it fails.

Use the established technology comparison runner and Tcl flow: portable RTL, explicit global clock buffer, timed internal state/control paths, external I/O paths excluded, Default synthesis/placement/physical optimization/routing. Start with XC7Z030 only, one run, with the authorized 24-hour limit. Preserve input and report hashes. A setup-derived period is a screening statistic; do not call it closure unless all relevant checks pass.

Charge the actual command acceptance, capture, proposal, gather, busy and result handshakes. Report any discrepancy from the earlier phase-cost recurrence. The externally commanded phase engine does not yet demonstrate autonomous sheet admission, retirement under an independent source, or end-to-end 1 MHz throughput. Combine measured phase costs with checked lower-noise phase counts only as a conditional next-controller budget.

Do not add a deep busy tree by habit. If busy/control routing is actually limiting, compare a shallow registered tree using the exact same state transition and witness. Its shorter period must compensate for its extra phase clocks; record that break-even ratio before running the variant.

Before native timing results: the measured command cadence is three clocks for drop and five otherwise. Thus an ideal zero-gap sequencer would spend `5 × phases − 2` clocks per sheet: 23 for a quiet sheet and 24.387 for the original-seed 512-sheet d=3/0.5% cohort. Its conditional mean-service break-even for one microsecond is about 41.01 ns per clock. This is a useful gate for the phase engine, not an autonomous throughput prediction: sequencer, admission, retirement backpressure and the intended acquisition/decoder partition remain unmeasured.

## Native result

The [retained native report](../docs/artifacts.md#historical-reports) (`experiments/snowflake/hardware/native-timing/README.md`) completed in 860 seconds. Synthesis/routed setup-derived periods are 15.993/15.764 ns; routed resources are 10,796 LUTs, 7,682 FFs and no DSP/BRAM. The LUT prior was high; the FF prior held. At the requested 8 ns, setup fails by 7.764 ns, while hold/pulse checks and internal timing coverage pass. All nets route; the sole DRC warning is the intentionally absent PS7 block. External I/O remains excluded, so this is not board-clock qualification.

The predicted kernel bottleneck is present: six serial CID compare/select steps feed pointer/activity/busy, with 4.389 ns logic and 11.432 ns routing on the worst path. No sampled worst path implicates the global busy reduction. A distinct 10.524 ns capture-control path already has a 2,592-load enable net, so eliminating the kernel chain would not by itself achieve 8 ns.

The prior ideal-sequencer cadence gives a conditional 0.384 µs mean at the measured setup period on the stated d3/0.5% sample. This supports building the autonomous finite-input controller next, then remeasuring its complete service and timing. It does not establish end-to-end throughput, a stable stochastic backlog, or the budget for the intended 2×4 tile. Do not deepen the busy reduction without a path or throughput measurement that motivates it.
