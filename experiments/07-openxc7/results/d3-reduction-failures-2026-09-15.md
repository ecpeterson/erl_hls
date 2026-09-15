# D3 reduction failures and registered effect credits

This compares main `3f3762b234a2f7ab8a65455df2da27f59dfe9ac5` with implementation `f2fdb8e` on `codex/reduction-failure-propagation`. The [machine-readable report](d3-reduction-failures-2026-09-15.json) retains compiler, source, RTL, synthesis-tool and command fingerprints, individual samples, distributions, and behavioral evidence.

The prediction before measurement was a small area increase for pending failure codes and little healthy-path throughput change. Two matched synthesis name seeds measure **4.87% more core LUTs**, **3.19% more flip-flops**, and unchanged BRAM/DSP counts. The registered-credit repair costs **3.33% of request-paced step throughput** and **3.63% under variable sink readiness**. ABC9's mapping-delay estimate falls, but this run does not measure routed timing or power.

## Behavior and storage

A reducer error is an absorbing value. The receiving actor keeps its first detected failure, accepts all remaining valid contributions without evaluating the reducer again, and fails only when the population is complete. The completion handler does not run. This applies to BEAM, direct/shared actor machinery, and source-fragment aggregation. Supported hardware errors retain their source locations through the ordinary actor debug endpoint. Typed local helpers are now reachable from `reduce/3` as well as other callbacks.

The pending reduction state gains a 16-bit failure code, separate from the actor's terminal failure latch. Shared actors store it in their existing state-RAM row; direct actors store it in their machine state. Aggregate queues carry a 16-bit code in place of a one-bit error flag. No history buffer is added. The measured area change includes this representation and its transport/pipeline consequences together with the credit repair; it does not isolate their individual costs.

The new offloaded fault fixture exposed a pre-existing shared-scheduler combinational loop. Newly captured effect-return credits could influence current result retirement, whose output fed the router and credit-return path. Credit collection now reads the previous iteration's registered pending payload and validity, preserving newly captured requests for the next iteration. This adds no storage but may delay credit reuse by one scheduler iteration. The baseline offloaded fixture has one structural strongly connected component; the repaired fixture has zero and its debug endpoint responds under backpressure.

## Matched synthesis

The workload is the decoder-only D3 profile: two phi planes, three scheduler shards per plane, two XLS pipeline stages, II=1, deterministic syndrome replay, and no debug instrumentation. Both versions use the same native XLS binaries, standard library, RAM implementation/configuration, and `unit` delay model. The native code generator includes the independent XLS RAM response-reservation fix. Compilation manifests are checked before comparison.

Each version is mapped with `rename -scramble-name -seed` values 1 and 2, followed by the same `synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf` flow. These are synthesis naming seeds, not placement or stimulus seeds. Best means minimum resource count or mapping delay; variance is population variance in squared units. Two samples describe this experiment, not a confidence interval.

| Metric | Version | Best | Mean | Variance | Worst |
| --- | --- | ---: | ---: | ---: | ---: |
| Core LUTs | Main | 118,383 | 118,812 | 184,041 | 119,241 |
| Core LUTs | PR | 124,182 | 124,593.5 | 169,332.25 | 125,005 |
| Flip-flops | Main | 81,058 | 81,058 | 0 | 81,058 |
| Flip-flops | PR | 83,640 | 83,640 | 0 | 83,640 |
| CARRY4 | Main | 2,455 | 2,464 | 81 | 2,473 |
| CARRY4 | PR | 2,448 | 2,452.5 | 20.25 | 2,457 |
| ABC9 delay (ps) | Main | 20,209 | 20,401.5 | 37,056.25 | 20,594 |
| ABC9 delay (ps) | PR | 16,874 | 17,164.5 | 84,390.25 | 17,455 |

Every sample has **104 RAMB18E1, 16 RAMB36E1, 144 DSP48E1, and zero LUT RAM**, with zero variance. Mean ABC9 delay decreases 15.87%. That estimate describes technology mapping; it is not routed delay or a safe clock frequency. All four mappings pass `check -assert` and `scc -expect 0`.

| Name seed | Main LUTs | PR LUTs | Main delay (ps) | PR delay (ps) |
| --- | ---: | ---: | ---: | ---: |
| 1 | 119,241 | 124,182 | 20,594 | 17,455 |
| 2 | 118,383 | 125,005 | 20,209 | 16,874 |

Both pairs show the same direction, with the between-version difference larger than the observed naming spread. Additional mapping seeds and place-and-route were not needed to establish the area increase or simulated cycle cost.

## Throughput and observable events

Both versions complete every coordinate through step 32; measurements exclude steps before the step-8 warmup boundary.

| Stimulus | Main cycles/step | PR cycles/step | Throughput change |
| --- | ---: | ---: | ---: |
| Request-paced profile | 174 | 180 | −3.33% |
| Variable sink readiness | 175.958333 | 182.583333 | −3.63% |

These deterministic runs have no stimulus-seed distribution. Under variable readiness, main sees 103 X-plane and 124 Z-plane stalled cycles; the PR sees 162 and 161. Both emit 63 X-plane and 64 Z-plane corrections in the bounded workload. The complete per-step status-set checks reject missing or duplicate coordinate statuses.

The registered-credit change alters event timing and can reorder different actors at the shared output. A cycle-exact comparison therefore fails, as does a single total-order comparison across coordinates. The first total-order difference is the order of status messages from coordinates `(0,0)` and `(1,0)`, not a changed status value. The explicit `--comparison-mode actor-sequence` check instead compares each actor's correction/status sequence and every payload bit, and checks both designs' held payloads across stalls. It passes over **12,000 cycles**, including long independent sink stalls and a mid-run reset, matching **635 X-plane and 626 Z-plane frames** across all 18 actors. Baseline stalled-cycle counts are 1,425/1,729; candidate counts are 1,452/1,708.

This comparison covers each actor's common accepted prefix. The autonomous sources progress at different speeds, so unmatched tails at the end and work discarded by reset are outside the comparison. It is a bounded regression witness, not a proof over arbitrary schedules. The strict cycle mode remains the default and also passes a baseline-versus-itself control.

## Comparison with the last placed-and-routed design

The last routed measurement is the final design in [the September 14 arbitration report](d3-arbitration-2026-09-14.md), from PR #102. Its ordinary unrenamed core mapping has **118,906 LUTs, 81,058 flip-flops, 104 RAMB18, 16 RAMB36, and 144 DSPs**. The present matched main mapping uses two naming seeds; its mean of 118,812 LUTs is close to that earlier unrenamed mapping, but the two are different mapping samples. The PR mean is 4.79% above that historical LUT count; the matched main-versus-PR increase of 4.87% is the appropriate estimate for this change.

The previous routed partial-path estimates were **14.46, 11.89, and 12.62 MHz**: best 14.46, mean 12.99, population variance 1.1693 MHz², worst 11.89. **No new routing run was performed, so there is no measured PR frequency to compare with them.** BRAM sequential timing is omitted, register checks use fixed approximations, and the DSP/device models are incomplete. Those historical estimates are not complete-design clock limits. The [timing-model audit](../phi-timing.md#measurement-limits) describes the coverage limits. Do not combine them, or the new ABC9 estimate, with simulated cycles to claim deployed step throughput.

## Validation and remaining scope

All **869 EUnit tests** pass. The generated DSLX/JIT regressions cover ordinary and aggregate failures, a missed reducer head, delayed final contributions, preserved failure codes through the state codec, suppressed completion, and a later would-be failure that must not overwrite the first. Existing successful count/member and source-fragment semantics still pass. BEAM tests cover saved error/exit/throw exceptions and member validation while draining.

Shared ordinary and offloaded RTL fixtures pass at two and three XLS stages. Public scoped `hls_debug:info` queries recover the expected `badarith`, `case_clause`, match-failure, and `if_clause` locations while a healthy actor completes. The checks include mailbox accounting, blocked-sink release, and structural/cycle noninterference of instrumentation. The pinned Linux run also passes the complete D3 debug composition and the generated RTL/bridged regressions. The updated halo-cell Verilog digest comes from that pinned Linux run; unchanged control digests are retained.

The new structural preflight separately identifies one admission ready/valid cycle in the older direct `ordered_egress_topology` fixture. Its generated RTL is byte-identical to the earlier CI artifact (`ed8d50e2962a53b566797ebd2c1bc04cb06bd3c22a96534f3209246823952516`), and its existing simulation/debug regression still passes. That cycle is not repaired here: it is recorded as a Roadmap follow-up. The integration tool always records SCCs and offers `--require-acyclic`; the shared actor fixtures enable that strict check. Passing simulation alone does not establish safety of the remaining direct-actor cycle.

Pending reduction failure does not cancel contributors, propagate links, or time out a missing contribution. Invalid member/window handling retains its separate protocol policy. Offloading can reassociate the fold and skip the first identity application; a partial reducer still violates its monoid promise on invalid inputs, so different placements need not encounter or select the same error. The contract guarantees that a detected failure cannot become a successful reduction.

## Reproduction

Preserve separate compiled baseline and candidate D3 directories using the [profile compilation instructions](../phi-timing.md#run). Then run:

```sh
python3 experiments/07-openxc7/measure_phi_mapping.py "$baseline" "$candidate" \
    --stage "$mapping" --seeds 1 2 --jobs 2
python3 experiments/07-openxc7/phi_timing.py "$candidate" \
    --reference "$baseline" --stage "$comparison" --phase compare \
    --comparison-mode actor-sequence
python3 experiments/07-openxc7/phi_timing.py "$baseline" \
    --stage "$baseline_sim" --phase simulate
python3 experiments/07-openxc7/phi_timing.py "$candidate" \
    --stage "$candidate_sim" --phase simulate
bash tools/test_reduction_dslx.sh "$xls" "$reduction_stage"
bash tools/test_actor_debug.sh "$xls" "$ordinary_stage" reduction
bash tools/test_actor_debug.sh "$xls" "$aggregate_stage" aggregate
```

The JSON abbreviates the checkout as `${REPO}`. Digests refer to original files; generated RTL and complete synthesis logs remain build artifacts. Request-paced results come from `tools/run_phi_decoder_profile.sh` with `ERL_HLS_PHI_PROFILE_TRACE=0`.
