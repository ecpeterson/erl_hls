# Fixed-schedule LUT arithmetic and DSP cascade timing

**Vendor follow-up:** [Matched Vivado controls and expanded calibration](vendor-followup-2026-09-26.md) now cover the previous model gaps, compare the complete cores at 5/40 ns constraints, and measure DSP forwarding delays. Use those results for current timing conclusions; this report retains the earlier native experiment.

Mapping all arithmetic into LUTs costs 6,514 extra LUTs (+19.6%) without a repeatable native timing gain. Keep DSP inference. The experiment also found and corrected an impossible dependency in our local coarse DSP timing extension; the old arithmetic-path attribution needs revisiting.

[Reproduction](../timing_chains/README.md#arithmetic-resource-mapping-and-dsp-cascade-dependencies) · [Preregistered hypotheses](../yap/lut-arithmetic-2026-09-26.md) · [Measurements](lut-arithmetic-2026-09-26/comparison.json)

## Fixed hardware schedule

Use the best retained shared core from #177: two phi sites per X/Z plane, four phi actors and four syndrome sources, shared schedulers, two requested stages, II=1, default split next-value selects, and compact/accepted-push FIFOs. Both mappings use identical RTL and harness inputs; only decoder synthesis adds `-nodsp`. Neither precision nor the XLS schedule changes. This is distinct from the unsplit architectural controls in the preceding report.

The decoder changes from 33,171 to 39,685 LUTs and 56 to zero DSP48E1s. Both have 22,008 FFs, 44 RAMB18 and eight RAMB36; the storage primitive/parameter multisets match. CARRY4s rise 754→822. The existing RTL witness retains 79.25 cycles/step normally and 79.8333 under stalls. Identical RTL and matching storage inventories are not a new gate-level equivalence proof.

## Paired native measurements

Both variants use XC7Z030 SBG485-1, a 40 ns target, the same chip database and corrected DSP dependency graph. LUT seed 1 used the original frozen binary; that graph correction cannot affect it because it contains no DSPs. Other runs use the separately frozen corrected binary. No compiler default changes.

| Mapping | Seed | Placement estimate (ns) | Routed period (ns) | Period × cycles (µs) | Logic / routing (ns) |
| --- | ---: | ---: | ---: | ---: | ---: |
| DSP | 1 | 43.403 | 42.248 | 3.348 | 3.4 / 38.8 |
| DSP | 2 | 42.141 | 38.805 | 3.075 | 3.5 / 35.3 |
| LUT | 1 | 44.464 | 38.956 | 3.087 | 3.4 / 35.6 |
| LUT | 2 | 45.851 | 42.283 | 3.351 | 3.2 / 39.0 |

| Two-seed statistic | DSP | LUT |
| --- | ---: | ---: |
| Mean routed period (ns) | 40.526 | 40.620 |
| Population variance (ns²) | 2.963 | 2.768 |
| Best / worst period (ns) | 38.805 / 42.248 | 38.956 / 42.283 |
| Mean step cost (µs) | 3.212 | 3.219 |
| Population variance (µs²) | 0.018610 | 0.017383 |
| Best / worst step cost (µs) | 3.075 / 3.348 | 3.087 / 3.351 |

LUT mapping is 7.8% better on seed 1 and 9.0% worse on seed 2; its mean is 0.23% worse. Two seeds reveal sensitivity, not a confidence interval. The prediction of 32–36 ns and 2.54–2.85 µs fails: removing DSP arithmetic exposes control/routing paths, rather than delivering the expected clock improvement. The predicted 4,000–10,000 additional LUTs does hold.

All four limiting paths involve shared execution and reduction control. LUT seed 2 runs from executor request validity through batch selection to collector clock enable (39.0 ns routing); DSP seed 2 runs through scheduler read-address/admission and stage completion to collector state update (35.3 ns routing). Its final collector-enable net costs 9.8 ns. The retained [path reports](lut-arithmetic-2026-09-26/) identify each cell/net. These observations favor investigating publication/collector control locality. They do not establish that every arithmetic optimization is unhelpful: exact division factoring remains a separate candidate.

## Correcting a false DSP dependency

Our coarse combinational DSP model allowed any data input to reach every timed output. The historical limiting path includes B14→ACOUT7. With all internal registers bypassed, ACOUT forwards the selected A/ACIN bit; BCOUT similarly forwards B/BCIN. A B input cannot affect ACOUT. This follows [AMD UG479](https://docs.amd.com/api/khub/documents/gu4oRPFEh_Pm2uaAlfY6Kg/content) and is proved symbolically against Yosys's DSP48E1 primitive model for all four direct/cascade combinations.

The narrow filter removes only impossible A/B cascade dependencies. It changes no numerical delays or other DSP outputs, and does not add registered-DSP support. Unknown parameter modes conservatively retain both candidate buses. This repairs our experimental extension, not a newly established upstream native-tool defect. Selected cascade arcs still carry coarse pessimistic delays and need vendor calibration.

| Same physical design, different dependency graph | Old period (ns) | Corrected period (ns) |
| --- | ---: | ---: |
| Historical placement, estimated interconnect | 46.598 | 41.494 |
| Historical route, identical cells and wires | 39.667 | 38.551 |

The routed control reproduces the historical 25.21 MHz result, then switches dependencies and rechecks timing inside the same process. Its cell/net/placement/routing checksum stays `0x6aa2bd4d`. This is a model correction, not a hardware speedup. The new limiting path delivers a reduction batch to collector state: 2.4 ns logic and 36.2 ns routing. The resulting diagnostic cost is 3.055 µs/step. The separate fresh placements in the table above use the corrected model during optimization and must not be confused with this unchanged-wire comparison.

A routed-checkpoint reload was attempted but the pinned native reader aborted with `std::out_of_range`; the same-process control avoids that failure. [Before/after reports and commands](lut-arithmetic-2026-09-26/fixed-route/comparison.json) retain the successful control.

Historical native arithmetic paths and variant rankings affected by the old false dependencies need rechecking. Prior resource counts, RTL behavior/cycle measurements, XLS estimates and Vivado measurements are unaffected. A passing endpoint audit does not detect impossible combinational arcs, and none of these native periods qualifies a board clock.

## Validation and next vendor checks

All four new routes pass their required FF/RAM endpoint checks, plus DSP checks where present. Mapping preserves the decoder while adding the harness and passes zero-combinational-loop checks. The C++ test exhausts direct/cascade selection and bit dependencies; the symbolic primitive proof uses arbitrary data/control inputs. The timing suite passes 38 tests, source-contract tests pass 19 with no new contract gaps, and Dialyzer succeeds.

Both complete mapped cores are prepared as held-out vendor validation inputs, with a [manifest](lut-arithmetic-2026-09-26/vendor-manifest.json). EC2 was not contacted. On resumption, measure those mappings alongside the already prepared exact-arithmetic kernels/constant-product calibration, and inspect selected cascade arcs explicitly. Retain the application probes as validation; do not train on their results and then present them as independent confirmation.
