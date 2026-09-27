# Vendor calibration and complete-core controls

The expanded XLS model covers the observed application shapes, but new selector diagnostics expose a serious interpolation underestimate. Independent Vivado routes reject the proposed architectural speedups and confirm that exact arithmetic factoring saves DSPs without improving step time. Production defaults are unchanged.

## Scope and measurement

The complete core is the two-plane **2×1 fixture: four phi actors and four syndrome actors**, with its schedulers, state/mailbox RAM and reduction planes. It excludes board I/O, Ethernet and transport. Measurements use `xc7z030sbg485-1`, native Yosys `synth_xilinx -abc9`, preserved mapped circuits and Vivado 2024.2 placement/routing. The usual constraint is 5 ns; four controls instead request 40 ns. These are internal setup measurements, not board qualification or demonstrated operating frequencies.

Each imported and routed circuit passes pin-graph/parameter equivalence, full internal clock coverage, zero loop checks and complete routing with zero routing errors. Reported period is `REQUIREMENT − SLACK`, including setup and skew; logic/net columns describe only the data path. Step cost multiplies this period by independently simulated steady-state cycles. Each vendor configuration has one placement: no placement variance is estimated.

## Complete-core results

| Core at 5 ns constraint | Period, ns | Cycles/step | Step cost, µs | LUTs | DSPs |
|---|---:|---:|---:|---:|---:|
| Shared, normal lowering | 15.846 | 79.25 | 1.256 | 33,171 | 56 |
| Same RTL, LUT arithmetic | 15.090 | 79.25 | 1.196 | 39,685 | 0 |
| Shared, unsplit next values | 15.968 | 79.25 | 1.265 | 36,571 | 56 |
| Dedicated, unsplit | 21.675 | 64.50 | 1.398 | 34,745 | 112 |
| Dedicated, normal lowering | 26.867 | 62.00 | 1.666 | 33,894 | 112 |
| Shared, bulk factoring | 15.851 | 79.25 | 1.256 | 33,274 | 48 |
| Shared, bulk and center factoring | 15.944 | 79.25 | 1.264 | 33,112 | 40 |

The [22-core table](vendor-followup-2026-09-26/cores.json) also contains eager execution, three fusion removals and five registered/II=2 boundary variants. None improves the shared control's step cost. Removing immediate reissue, separating entry execution and registering egress cost respectively 1.469, 2.057 and 1.731 µs. The best registered/II=2 boundary candidate costs 1.320 µs. Their cycle penalties overwhelm clock changes.

Normal-lowering dedicated execution misses its preregistered period range of 19.5–23.8 ns. Its limiting path runs from a reduction accumulator through comparison/arithmetic to a router-state enable: 41 logic levels, 7.633 ns cell delay and 18.649 ns interconnect. Removing shared state storage does not remove this composed path. The default/unsplit difference also cautions against attributing an architectural delta to scheduling alone.

LUT arithmetic gains 4.8% in this placement but costs 19.6% more LUTs. At a 40 ns constraint the same DSP/LUT maps instead measure 22.042/24.987 ns, reversing their ranking. Shared-unsplit/dedicated-unsplit measure 24.695/27.318 ns. All four meet that relaxed constraint. A requested clock changes implementation effort and placement; it is not just a reporting parameter. These controls do not support promoting LUT arithmetic.

## Arithmetic hypothesis and failure

Factoring rounded division by twelve reduces a signed constant product from 37×39→76 to 35×37→71 while preserving Q15.16, saturation and ties-away rounding. It removes two DSPs per isolated kernel. The predicted 5–20% bulk-kernel improvement fails: period increases **12.750→13.045 ns**. Cell delay falls 9.263→8.728 ns, but interconnect grows 3.365→4.192 ns. The center kernel likewise increases **15.205→15.727 ns**.

Bulk-only factoring leaves the original center multiplier critical. Factoring both predicts 40 DSPs, unchanged cycles and 13–15 ns; only the area/cycle predictions hold. The final core has **28.6% fewer DSPs**, essentially unchanged LUTs, and a 0.6% longer period in its one placement. Its path remains state RAM → selection/weighted arithmetic → two DSPs → carry logic → register, with 26 CARRY4s, 9.933 ns cell delay and 5.908 ns interconnect. Reducing total DSP occupancy does not sufficiently shorten the serial carry/arithmetic chain.

The [kernel evidence](vendor-followup-2026-09-26/kernels.json), finite-width proofs and independent integer-oracle checks cover 158,444 bulk and 162,089 center RTL vectors. Four bulk/five center assertions prove unsatisfiable; a deliberately wrong rounding bias is satisfiable. Full new application variants match all 161 BEAM witness events under normal/stalled outputs and pass the 12,000-cycle reset/backpressure comparison.

## Model coverage and remaining uncertainty

The calibration corpus now has **1,070 measured shapes, 848 training entries and 216 held-out error samples**. Added coverage includes the observed 65-way selector/predicate neighborhood, up to 128-way sampled selectors/logic, 256-bit encoders, 128-bit products and the exact factored constant product. Width/fan-in combinations outside the sampled domain still fail explicitly. All 785 previous table entries are unchanged.

| Prediction minus measurement | Cell delay | Routing-inclusive delay |
|---|---:|---:|
| Mean error | +114.68 ps | +15.51 ps |
| Population variance | 76,308.60 ps² | 352,735.95 ps² |
| Mean absolute error | 163.82 ps | 316.71 ps |
| Worst underestimate | 924 ps | 2,753 ps |
| Worst overestimate | 2,414 ps | 3,529 ps |
| Underestimated samples | 54/216 | 117/216 |

Near-zero signed mean does **not** make this an upper bound. The worst optimistic held-out case is a 24-bit, 65-case default selector. Four [adaptive neighboring probes](vendor-followup-2026-09-26/selector-diagnostics.json), excluded from the fit and statistics above, are worse:

| Cases, width 24 | Measured routed cost, ns | Prediction, ns | Underestimate, ns |
|---|---:|---:|---:|
| 63 | 11.687 | 9.717 | 1.970 |
| 66 | 11.370 | 10.015 | 1.355 |
| 95 | 17.478 | 12.270 | 5.208 |
| 127 | 22.855 | 14.758 | **8.097** |

The predicted small discontinuity just above 64 is not a sufficient explanation. XLS emits nested equality/ternary selectors; the 127-case mapped path has 39 levels, including 33 serial MUXF8s. Width/fan-in interpolation misses this mapping outcome. Coverage is therefore distinct from accuracy: large selectors need a mapping-aware model or different lowering before relying on their scheduling estimates.

Whole-package audits pass for the small core, D3, and all new arithmetic/architecture variants. Four regenerated applications are byte-identical to their measured RTL, and their scheduling-normalized IR passes too. C++ and Python predictions agree on all 1,070 measured shapes in both modes.

Sixteen legal three-DSP fixtures add A/B forwarding evidence, including register settings for later work. Fully combinational selected-bus costs are now 613/623 ps for direct A/B forwarding and 442/415 ps for ACIN/BCIN forwarding. Only these four numerical costs change in the native extension; unrecognized and registered configurations retain their previous handling. A fixed-placement estimated-interconnect replay remains **24.10 MHz**: the formerly excessive forwarding costs are no longer limiting. This is neither a newly completed native route nor a hardware speedup.

Vendor queries of the native-limiting endpoints and full placement/net-route exports are retained for local diagnosis. Those endpoints cost 10.509–14.213 ns in the vendor placements; comparing them with native timing does not isolate model error because physical routes differ. The evidence supports investigating native placement/interconnect estimates alongside arithmetic depth, rather than treating either tool's ranking as universal.

## Reproduction and next use

Use the [timing-model workflow](../docs/timing-model.md) and [core experiment commands](../timing_chains/README.md). The [extension plan](vendor-followup-2026-09-26/extension-plan.json), [calibration facts](vendor-followup-2026-09-26/calibration.json), [application coverage](vendor-followup-2026-09-26/application-coverage.json), [primitive arcs](vendor-followup-2026-09-26/cascade-arcs.json), critical-path excerpts and [raw archive hashes](vendor-followup-2026-09-26/raw-archives.json) identify the inputs and evidence. Committed report excerpts omit trailing whitespace; full local archives retain mapped JSON, SDF, pre/post-route connectivity, parameters, commands and all 20 reported paths; disposable checkpoints and duplicate EDIF are omitted.

The next local experiments should target the **serial arithmetic/carry chain**, using exact transformations or a carefully placed stage boundary and comparing period × cycles, and the **linear selector lowering** exposed by the saved neighboring circuits. Neither task requires another vendor session merely to begin. Full board closure, repeated placement sensitivity and timing for newly introduced primitive modes remain separate validation work.
