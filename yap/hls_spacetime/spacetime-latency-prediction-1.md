# First source-bound latency prediction

The user authorized a bounded predictive model far enough to make one concrete suggestion. This extends the saved register-cut experiment with source-qualified owner obligations and explicit latency/period hypotheses. It does not duplicate the old observed profiling ledger, change hardware, rerun a native job or claim a physical speedup.

## Case and intervention

The main recording is the N2 source-protocol repetition example. The saved interval is `(1774,1873]`, 99 clocks; three accepted public-output anchors occur in the interval. The native sink `dut/network/core/____state_137_reg[123]/D` belongs to Phi actor 2's pending 537-bit machine, specifically `phi[0][11]`. State136 is its committed machine. Phi actor 3 uses committed154/private155. This association comes from the generated source/IR/RTL and observation bindings, not the register number alone.

The C1853 private write is a phase transition, not a diffusion completion, and commits at C1854 with head retirement and outbox creation. Its unchanged phi bits still have the long structural arithmetic fan-in. Merely delaying that bit breaks the coherent owner result. The profile therefore models whole pending actions and coherent commit groups, including source obligations for retirement, reissue and old-outbox draining. Actor take-to-release/slot-reuse closure and cursor/postponement/batch controls remain incomplete; preserving gaps does not repair those dependencies. Small action-control taps exist but do not have graph write events; this gap remains explicit. Scalar ancestry for some pending/committed writes remains unresolved. The modeled completion ancestry contains 43,977 unknown-origin root versions plus two initial roots; these remain fixed inputs, not recovered causal dependencies.

The case builder binds the original generated sources and raw/optimized IR, RTL, observation metadata, retained tap stream and exact prepared recording. It checks 309 Phi actions, 243 classified numerical and 66 other, yielding 1,186 coupled groups (309 actions, 309 commits and 568 receipt fast paths) and 3,359 extra lifecycle/order constraints. Classification checks the exact pre-edge COMPLETE/gathering/reduction-key conditions, not equality of output values. Inactive `egress_blocked` samples are excluded unless action-valid is also set. All active pending holds and commits were consistent with this finite source interpretation.

## Results and decision

With one extra clock per selected action:

| Change                                     | Gap absorption | Gap preservation |
| ------------------------------------------ | -------------: | ---------------: |
| Phi2, all pending actions                  |             99 |              111 |
| Phi2, numerical completion only            |             99 |              109 |
| Phi3, numerical completion only            |             99 |              109 |
| Both Phi actors, numerical completion only |             99 |              109 |
| Both Phi actors, all pending actions       |             99 |              111 |

These are two conditional fixed-work/order scenarios, not a bound on the changed RTL. Some numerical completions already await outbox capacity: for example Phi2's C1860 result commits at C1865 after four active blocked cycles. Other results immediately feed their next owner stage. The model distinguishes those constraints without calling all stored time slack.

The physical census gives the missing leverage over cycle profiling: the largest target in Phi2 is 8.8154 ns, but changing it alone leaves Phi3's 8.8635 ns envelope. Targeting both pending-machine resources leaves a largest recorded mapped envelope of 7.0589 ns in state119. At an illustrative 8.5 ns hypothesis there are 64 above-period targets in each Phi pending-machine resource, and none among other known mapped targets. This is not all device timing: 225,751 of 1,090,260 requested write-bit occurrences are unmapped, and clock/endpoint checks and new routing are excluded.

**Specific recommendation:** if pursuing a hardware trial, pipeline the diffusion-completion arithmetic in both Phi instances while retaining the current receipt/ordinary-dispatch path, with busy/result-valid, selected-head ownership, companion outputs and reset aligned. Do not retime just the selected bit or only Phi2. The 109-clock scenario requires candidate period below `99/109 = 0.908257` of baseline, about a 9.2% reduction, to improve step time. Delaying every action raises that requirement to about 10.8%. The single-sink 215-bit cut is only a storage lower bound; the complete coupled-output partition is still to be designed.

A 10 ns baseline and 8.5 ns candidate would mean 990 ns versus 926.5 ns in the gap-preserving numerical scenario, about 6.4% improvement. Those periods are assumptions used to illustrate the decision, not achieved timing. The model makes this trial worth specifying; it has not yet predicted and confirmed a hardware outcome. The next validation would compare an isolated changed RTL witness against the modeled cycle shifts before spending a native implementation run.

## Retained evidence

Fresh artifacts live under `hls_artifacts/runs/spacetime-2026-11-08/candidate-prediction-1/`: source profile and reproducible offline builder, initial and receipt-corrected scenario/census reports, zero-intervention baseline replay, guarded local tests and browser qualification. Failed native-name inventory lookup is retained before its corrected lookup. The local viewer's ignored `data/latency-profile-2.json` is bound by a new index descriptor. The original recording/rendering payloads are unchanged.

Source and capture hashes identify the evidence; source-obligation assertions and unit tests do not prove native equivalence, a legal pipeline transformation, unrestricted progress or a routed clock period.

## Local qualification

All 459 JavaScript tests and 155 Erlang tests pass, with formatting, Dialyzer and the 18-file source audit clean. The full guarded check took 6.14 seconds, peak process-group RSS 353 MB, exit zero with no guard or remaining processes. The saved CLI report verifies the exact profile/recording and reproduces the two numerical scenarios; no native or application job was run.

Browser checks verify loading the reviewed profile, changing action scope, immediate stale-result invalidation while editing inputs, one- and two-clock interventions, and period sensitivity. Two numerical clocks give 119 clocks under gap preservation, making an assumed 8.5 ns candidate 2.17% slower than an assumed 10 ns baseline. Phi2 alone retains 64 mapped targets above 8.5 ns in Phi3. The delivered panel is left on both numerical actors, one extra clock, illustrative periods 10/8.5 ns. Screenshot and DOM evidence are retained with the case.

## RTL calibration follow-up

The user-authorized [numerical pipeline witness](spacetime-numerical-pipeline-witness-1.md) now measures 106 clocks against the unchanged 99/109 scenarios. Arithmetic result/commit recurrence matches for all 20 remaining diffusion computations; changed output-ready alignment defeats exact public completion prediction. The longer step-4-through-8 interval grows 498→562 clocks. The experiment qualifies finite behavior and source staging, not physical improvement.
