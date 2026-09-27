# Timing feedback: schedules, physical paths and step rate

A selective executor reschedule improves the complete 2×1 core's vendor period by **3.5–4.4%**, with unchanged cycles and **0.5% more LUTs**. More aggressive retiming regresses. A balanced indexed-selector probe improves substantially, but that selector shape is absent from this core. Compiler defaults remain unchanged.

## Reproduce the analysis

The fixed workflow is: retain RTL/schedule identity → simulate cycles and behavior → map → audit timing coverage → route matched variants → generate the path report. Hypotheses and rejection criteria are [preregistered](../yap/timing-paths-2026-09-27.md). The [runner guide](../timing_chains/README.md#combined-timing-report) specifies each step.

Both reports below regenerate from committed, compressed inputs, without build caches or FPGA tools:

```sh
python3 experiments/07-openxc7/timing_chains/path_report.py \
  experiments/07-openxc7/results/timing-paths-2026-09-27-manifest.json \
  --artifacts experiments/07-openxc7/results --output /tmp/prior-paths
python3 experiments/07-openxc7/timing_chains/path_report.py \
  experiments/07-openxc7/results/timing-feedback-2026-09-27-manifest.json \
  --artifacts experiments/07-openxc7/results --output /tmp/feedback-paths
```

The JSON retains path-family summaries, source/stage evidence and input hashes; `--full-json` includes individual arcs. The [initial report](timing-paths-2026-09-27.md) groups the saved global paths. The [fresh report](timing-feedback-2026-09-27-paths.md) additionally queries RAM sources, DSP through-points and FF control endpoints, deduplicating overlapping paths. Missing families remain unknown; deleting the only sampled family never predicts a zero-period circuit.

## Complete-core experiment

This is the two-plane 2×1 fixture: four phi actors, four syndrome actors, shared schedulers, executor, state/mailbox RAM and reductions. It excludes Ethernet, board I/O and transport. All variants use two requested XLS stages, II=1 and the same executor ports; surrounding RTL is byte-identical. The testbench retains 79.25 normal cycles/step, 79.833333 with output stalls, and identical accepted outputs on every cycle through the 12,000-cycle stall/reset comparison.

Yosys maps the complete core; Vivado 2024.2 places/routes that preserved circuit for `xc7z030sbg485-1` at a requested 5 ns. Pin/net/parameter audits pass before and after routing. These internal setup measurements do not qualify a board clock or establish distributed-decoder throughput.

| Executor scheduling | LUTs | FFs | DSPs | Default period, ns | Implied normal step, µs |
|---|---:|---:|---:|---:|---:|
| Routed-cost reference | 33,171 | 22,008 | 56 | 15.846 | 1.256 |
| Cell-only, no arrival penalty | 33,343 | 21,774 | 56 | **15.151** | **1.201** |
| Cell-only, 3 ns receive penalty | 33,776 | 21,652 | 56 | 17.100 | 1.355 |
| Same, product input registers kept in fabric | 34,019 | 21,948 | 56 | 17.422 | 1.381 |

All retain 44 RAMB18 and eight RAMB36 blocks. Area excludes the timing harness. Cell-only scheduling moves only the two bulk-field products to stage one; the 3 ns penalty moves all four field products there.

The promising pair also passes an `Explore` placement control, with routing policy and mapped circuits unchanged:

| Variant | Default, ns | Explore, ns | Best / mean / worst, ns | Population variance, ns² |
|---|---:|---:|---|---:|
| Reference | 15.846 | 15.794 | 15.794 / 15.820 / 15.846 | 0.000676 |
| Cell-only, no penalty | 15.151 | 15.237 | 15.151 / 15.194 / 15.237 | 0.001849 |

These are **two deterministic placement strategies**, not random seeds or confidence intervals. The candidate's implied 1.201–1.208 µs steps remain short of 1 MHz; unchanged-cycle operation needs a period of 12.618 ns.

## What the failed prediction revealed

The initial hypothesis was that pricing late RAM input would move multiplication across an existing boundary and remove 1–3 ns from the arithmetic family without another cycle. XLS's generic input-delay allowance applies to both channel directions and produced identical RTL at 0/3/6 ns. The directed receive allowance changed the routed-cost schedule but left every field product in stage zero. Cell-only costs finally moved the intended products; moving all four was worse physically.

The aggressive schedule reduces worst-path cell delay from 10.160 to 8.644 ns, but increases interconnect from 5.646 to 8.228 ns. It also places the multiplier input registers inside 48 DSPs. Native timing omits those registered modes, so the physical runner now rejects them before placement. Preserving four operand registers in fabric restores the covered modes; that candidate still regresses in both native and vendor routing. Register packing is therefore not the sole explanation.

The native matched seed reports 41.051→45.147 ns, with roughly 92% interconnect delay and unchanged cycles. Slow nets include both high fan-out controls and low fan-out connections spanning much of the chip. This does not establish a general native regression from one seed, but supplies no evidence for promoting the aggressive candidate.

More importantly, the new query sets reveal **several near-tied limits**:

| Path set | Reference, ns | Selective retiming, ns | Aggressive retiming, ns |
|---|---:|---:|---:|
| Global worst | 15.846 | 15.151 | 17.100 |
| From RAM | 15.846 | 15.144 | 15.468 |
| Through DSP | 15.846 | 15.151 | 17.100 |
| To FF control pins | 15.683 | 14.904 | 16.939 |

The reference control path contains 26 LUT stages: 1.647 ns cell delay including launch, 13.632 ns interconnect. It was absent from the global top twenty. Even eliminating arithmetic would leave that 15.683 ns path if placement and the control circuit stayed unchanged. The selective candidate's worst path instead runs from a registered DSP through arithmetic to **mailbox RAM**: physical work continues beyond the executor boundary. Proc-local delay totals account for neither every upstream arrival nor every downstream destination.

Future changes should target these complete boundary-to-boundary cones, and price any added feedback cycles before implementation. Breaking the serial ready/enable dependency and shortening arithmetic/egress paths must be assessed together; optimizing another isolated operator cannot justify a large whole-core prediction.

## Indexed-selector experiment

A balanced tree preserves arbitrary payloads, indices and out-of-range defaults. SAT proves the compiled RTL equivalent for 63/65/127 cases. At 127 cases, mapped maximum cell depth falls 40→5 and maximum MUXF8 depth 34→0; LUTs fall 5,555→1,622 with the same 3,105 FFs. Counts include the preserved harness. The neighboring 63/65-case probes also fall to five-cell depth.

| Native 127-case probe, two matched seeds | Best MHz | Mean MHz | Variance, MHz² | Worst MHz |
|---|---:|---:|---:|---:|
| Flat/default selector | 24.41 | 24.23 | 0.0324 | 24.05 |
| Balanced selector | 115.27 | 110.77 | 20.2500 | 106.27 |

Vivado confirms 24.481→4.530 ns at the same 5 ns constraint. This is a strong lowering result, **not an application speedup**: the small core has no large binary indexed selector. Its largest selections are 17-way, 96-bit priority selections; applying this idea there needs a separate priority/default equivalence proof and full-core measurement.

## Validation and retained evidence

Local checks: three complete-core variants match the BEAM oracle under normal/stalled output and the cycle-exact reset witness; three full-width selector equivalence proofs pass; report/coverage and calibration tests pass, including registered-DSP launches, overlapping query sets, changed evidence, clock constraints and portable archives. Source-contract checks and Dialyzer pass. The expensive routes are experiment evidence, not new CI jobs; CI adds only the report regressions.

[Detailed measurements and commands](timing-feedback-2026-09-27/) retain area, schedules, cycle witnesses, native routes, vendor audits and distribution statistics. The compact report input archives preserve all sampled paths and schedule inputs. Full SDF/connectivity archives are fingerprinted in `raw-archives.json` for later model work. No further EC2 work is needed for this batch.
