# Reciprocal integration: exact arithmetic, shorter DSP chains

The phi-field DSLX companion now selects `hls_fixed::round_ratio_chunked<12, 24, 17>`. Erlang handlers, field precision, saturation and ties-away-from-zero rounding are unchanged. This is an explicit arithmetic implementation choice, not an automatic rewrite of arbitrary multiplications. XLS still chooses registers from the executor's stage budget.

The reusable implementation splits a signed operand and unsigned reciprocal into limbs, reduces their aligned products and rounding bias with carry-save additions, then performs one carry-propagating addition. It supports other widths and denominators; 24/17-bit limbs fit the signed 25×18 DSP multiplier inputs after extending unsigned limbs.

## Matched application screen

The control is the post-#183 two-plane **2×1 attribution fixture**, with two-stage, II=1 executors and the calibrated cell-only schedule. This is not the 2×4-qubit target. Only the phi executor is replaced; other proc RTL and all ports are checked unchanged. Mapping uses the same ordinary Yosys policy in both cases, including DSP-register packing.

| Measurement | Original | Chunked, two stages | Chunked, three stages |
|---|---:|---:|---:|
| Normal cycles/step | 79.25 | 79.25 | 94.25 |
| Output-stalled cycles/step | 79.833333 | 79.833333 | 95.083333 |
| Largest executor XLS estimate, ns | 10.092 | 10.716 | 7.616 |
| Core LUTs | 31,774 | 34,234 | not mapped |
| Core fabric FFs | 21,698 | 21,786 | not mapped |
| Core DSPs | 28 | 20 | not mapped |
| RAMB18 / RAMB36 | 44 / 8 | 44 / 8 | not mapped |

All four reciprocal products lose their three-DSP cascades. Each now uses four independent DSP multipliers instead of six DSPs in two three-deep chains. The remaining direct DSP cascades are the unchanged random tie-break rank multiplications. The two-stage executor puts most partial products in stage 0 and two in stage 1; three stages put all reciprocal products in stage 1 and recombination in stage 2. The latter adds 15 normal cycles/step: II=1 does not hide a dependent actor's extra latency. The default stage count is unchanged.

The two-stage change costs **7.74% LUTs and 0.41% fabric FFs**, saving **28.57% DSPs**. Its largest XLS stage estimate increases by **6.18%**: decomposition alone does not guarantee a better balanced executor. The three-stage estimate falls **24.53%**, but the complete application's other timing paths remain. Neither percentage is a routed-clock prediction.

There is **no new full-core routed measurement**. The earlier [isolated three-stage experiment](staged-reciprocal-2026-09-27.md) measured a 43–44% native period reduction under its explicit fabric-register policy; that is not the timing of this integrated, normally packed design. Registered DSP timing remains outside the qualified native model. The previously supplied Vivado host was unreachable during this run; no EC2 work was performed. Shortening the reciprocal chains is retained as an intermediate result, independently of whether another path still sets the clock.

## Validation and reproducibility

- Compiled combinational arithmetic: **7,378 input tuples × 25 results = 184,450 comparisons** with Python integer multiplication/division. Covers signed limbs, modular truncation, 8/37/65-bit rounding, 129-bit multiplication, odd/even divisors and powers of two.
- Ordinary XLS ready/valid pipelines at both two and three stages: original and chunked arithmetic each pass generated and mapped simulations. Each run accepts 5,509 values, checks 5,501 results, exercises 2,576 blocked-output cycles and nine resets. Eight accepted values are intentionally flushed by resets. Negative extrema and limb boundaries are included. Stalled valid outputs must stay stable.
- Two-stage application: BEAM oracle agreement for 161 output events in both normal and stalled runs; cycle-exact comparison through 12,000 cycles with long stalls and reset. The mapped executor is also substituted into the application and compared with its generated counterpart.
- Three-stage application: the same oracle and reset/stall comparisons pass; cycle equality is intentionally not required.
- 1,180 EUnit tests pass; Dialyzer, source-contract checks and the 12 timing-report tests pass. These are simulation/test results, not formal proofs.

The initial fixed kernel from #184 was screened first: it kept the same cycles and mapped to 33,708 LUTs. The reusable limb implementation above is the final measured candidate; its general carry-save ordering costs another 526 core LUTs. This difference is retained rather than substituting the more favorable prototype number.

Use `timing_chains/reciprocal_integration.py --library priv/xls/lib --pipeline-stages 2 3` with the retained control inputs to repeat the application substitution. `tools/test_chunked_arithmetic.py` checks arithmetic independently. `timing_chains/scheduled_reciprocal.py` checks generated/mapped streaming arithmetic; `timing_chains/executor_mapping.py` checks the complete executor in the application. [Machine-readable results and frozen inputs](reciprocal-integration-2026-09-27/) retain commands, schedules, mapping counts and simulation evidence. Neither Vivado nor the local UTM VM was reachable; all reported checks ran natively.
