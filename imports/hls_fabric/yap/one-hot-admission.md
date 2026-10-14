# One-hot collector admission

Keep producer grants one-hot through scalar/indexed collector payload selection, and derive availability directly from eligible requests. The selected version raises routed replay throughput 13.3% over #62 for 0.64% more LUTs. Binary producer IDs remain for cursor advancement and clearing consumed pending requests. Arbitration, validation, storage ownership and pipeline boundaries retain their behavior.

## Matched result

Complete single-clock D3H3 Snowflake actor graph: 36 vertices, six scheduler/executor groups, tree-six barrier, indexed gathers and monoid collectors; 128 sheets at p = 0.005. Baseline is #62 (`5206efe`, tree-identical to merged `main` at `280130a`). Both candidates retain its XLS pipeline, two codegen stages, unit delay model, result-channel delay of six units and LUTRAM completion storage. Vivado 2024.2, xczu7ev-ffvc1156-2-e, unchanged registered wrapper and 5 ns constraint; only application RTL changes between physical bundles.

| Version | Synthesized period estimate | Routed period | LUTs | FFs | Mean round |
|---|---:|---:|---:|---:|---:|
| #62 / main | 9.956 ns | 9.903 ns | 170,147 | 104,999 | 2.541 µs |
| One-hot, validity from grant | 8.572 ns | 9.381 ns | 170,771 | 104,080 | 2.407 µs |
| **One-hot, early validity** | **8.983 ns** | **8.744 ns** | **171,235** | **103,852** | **2.244 µs** |

All retain 48 BRAM36s, zero DSPs and 84,390 logical controller state bits. Mean round spacing is identical: 256.590551 clocks (min 234, max 469; population variance 3,039.627627 clocks²). All 1,750 external events, including their cycles, match byte-for-byte: 128 rounds, 1,125 corrections, END at 33,145 clocks.

Periods are derived as constraint minus worst setup slack; this is not 200 MHz closure or a board-frequency qualification. Each version has one matched implementation run. The selected route has +0.003 ns hold and +1.958 ns pulse slack, zero routing errors and no unconstrained internal endpoints. External ports retain the baseline's timing exclusions and its 282-load-free-output warning. Mean round time scales this single-clock replay by the derived period. The 1 MHz target remains unmet.

The baseline top 50 span 9.578–9.903 ns; the selected version spans 8.702–8.744 ns. Their endpoint groups change from indexed readiness / scalar state / indexed metadata = 24 / 21 / 5 to indexed metadata / readiness / scalar command / mailbox order = 27 / 16 / 6 / 1. The new worst path runs from the indexed arbitration cursor to indexed readiness (3.055 ns logic, 5.716 ns routing). These are ranked path sets, not matched-endpoint decompositions.

## Hypotheses and screens

Before implementation: target full-device LUTs within ±3% of 170,147, no intentional state/RAM increase, identical cycle trace; no whole-clock percentage prediction. Remove the producer encode-then-index dependency and screen both 19-/22-producer controllers before routing. The inspected 19-/22-producer controllers lose 14 dynamic array reads each; ordinary mailbox selection retains its reads.

| Synthesis scope | Indexed LUTs | First one-hot LUTs | Indexed period | First one-hot period |
|---|---:|---:|---:|---:|
| Isolated 19-input selector | 262 | 409 | 2.939 ns | 2.557 ns |
| Isolated 22-input selector | 327 | 468 | 3.288 ns | 2.783 ns |
| 19-producer controller | 25,926 | 26,222 | 8.339 ns | 9.198 ns |
| 22-producer controller | 25,713 | 27,044 | 9.334 ns | 8.783 ns |

The isolated indexed versions use 64 MUXF7 and 32 MUXF8 cells; their direct alternatives use none. The transformation trades dedicated mux resources for LUT logic. The 22-producer increase (+5.18%) triggered investigation: logical state was unchanged, mapped FFs and rebuilt hierarchy changed, and weighting the two controller shapes projected +2.2% full-design LUTs. Full synthesis actually grew 0.35%. Connected constants eliminate high destination bits retained by standalone controller ports, so some standalone critical paths disappear on integration.

A second preregistered candidate carries `valid = or_reduce(eligible)` beside the grant, avoiding validity/fallback's extra dependency on priority encoding. Budget: no state/cycle change and less than 0.5% additional full-device LUTs. It meets that budget and wins routing. Its standalone controllers use 24,939/26,847 LUTs, but full synthesis uses more LUTs than the first candidate (172,576 versus 171,980). Unplaced timing also ranks the candidates backwards. Keep the structural and capacity screens; select on completed routes.

## Compiler opportunity

Our XLS build retains the encode-then-index dependency in the [minimal comparison](../experiments/05-xls/one-hot-selection/selection.x). A candidate rewrite is `values[one_hot_sel(g, [0, …, N-1])]` to direct selection when `g` is established at most one-hot. Preserve `values[0]` for `g == 0`; arbitrary multi-hot masks are not equivalent. Match before constant index encoding decomposes into bit slices and ORs. An IR rewrite can handle aggregate cases, avoiding DSLX's explicit packed codecs.

XLS already has mutual-exclusion queries and related select rewrites. Its select-lifting pass can construct an alternative, compare unscheduled critical-path delay using the configured estimator, and apply an area heuristic. That is a possible profitability framework, but our isolated area results rule out treating this as an unconditional simplification. The experiment changes source intent, not optimizer policy.

## Validation and retained evidence

Passed: 323 EUnit tests; Dialyzer; source contracts (no new gaps); mailbox interpreter/JIT checks; 25 collector-kernel, two memory-helper and 50 production-adapter tests; 17 physical member-RAM cases; scalar collector checks; two-/three-stage RTL tests with stalls, reset and protocol faults; live indexed queries and debug noninterference. The held-request fixture now reselects from its current state instead of reusing a stale intent. Wide mailbox tests cover every producer lane and boundary competition; exhaustive small masks and the separate SAT comparison complement them. This reduces the mailbox suite from 109 to 28 local seconds.

The SAT miter establishes equivalence of isolated indexed/direct/early-valid selectors at 19 and 22 inputs for every data value, mask and 32-bit cursor. It is not a proof of the full controller. Reproduce with `experiments/05-xls/one-hot-selection/check.py --xls XLS_ROOT --yosys YOSYS --stage EXTERNAL_STAGE`.

Evidence lives outside the repository in `hls_artifacts/runs/one-hot-admission-2026-10-02/`: `comparison.json`, both `routed-report` packages, frozen source/RTL releases, passing logs and execution hashes. Final reviewed sources regenerate byte-identical unoptimized IR, optimized IR and RTL. `rebase-identities.json` preserves the identical-tree mapping onto merged main. Use the existing `technology_report.py` workflow to verify and package the native reports.
