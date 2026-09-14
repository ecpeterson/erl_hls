# D3 arbitration and scheduler RAM ordering

This compares main `f92620cdd85bdb0762357fdfdc568e55e53e6a30` with implementation `8e14148111450ebb983bff414d2606aa70c19865` from [PR #102](https://github.com/ecpeterson/erl_hls/pull/102). The [machine-readable report](d3-arbitration-2026-09-14.json) retains the inputs, samples, distributions, coverage, paths, and validation provenance.

The prediction registered before measurement was fewer control LUTs and shorter arbitration paths, little overall area change, and unchanged simulated step throughput. The final implementation reduces mean core LUT use by **5.71%** over five matched synthesis name seeds, with **0.29% more flip-flops**, unchanged BRAM/DSP use, and unchanged **175.958333 cycles/step**. The mean partial-path estimate changes from **13.19 to 12.99 MHz** (-1.54%). The area saving is consistent across the mapping samples. The routed timing prediction does not hold across seeds: two matched seeds become slower, and the variance grows substantially. These are exploratory modeled-path results, not complete-design clocks.

## Workload and changes

The [physical benchmark](../phi-timing.md) is the decoder-only D3 workload on `xc7z100ffg900-2`: two phi planes, three scheduler shards per plane, two XLS stages, II=1, and deterministic syndrome replay. Both versions use the same native XLS binaries, standard library, RAM implementation/configuration, and XLS `unit` delay model. The native code generator includes the independent XLS RAM response-reservation fix. This is a fresh comparison against the current main commit, not a reuse of the earlier September 12 baseline. Debug instrumentation is absent from the measured netlists.

Source-fragment planes and aggregate muxes now use a shared request mask and priority selector, replacing duplicated rotated dynamic-index scans. Their cursors use the smallest nonzero index width. A population-aware successor wraps before an increment could overflow. Actor schedulers and effect-window arbiters already used the shared selector and receive its new implementation too.

The faster selector exposed an existing scheduler ordering dependency that had been left implicit: mailbox metadata could become eligible for selection before its RAM write committed. Shared schedulers now carry an XLS token beside their metadata, making the next activation's RAM reads depend on the previous activation's writes. This adds no payload storage, acknowledgement FIFO, or RAM port. At II=1 the write/read recurrence must fit one initiation interval; consecutive activations still issue on consecutive clocks.

## Synthesis distribution

Each version uses five matched `rename -scramble-name -seed` values before the same `synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf` flow. These vary synthesis naming order, not input stimuli or placement. Best means the minimum for resource counts and mapping delay; variance is population variance in the square of the reported unit. Five samples characterize this experiment's sensitivity, not a statistical confidence interval.

| Metric | Version | Best | Mean | Variance | Worst |
| --- | --- | ---: | ---: | ---: | ---: |
| Core LUTs | Main | 125,081 | 125,886 | 265,028 | 126,547 |
| Core LUTs | Final | 118,276 | 118,692.4 | 132,365.84 | 119,241 |
| Flip-flops | Main | 80,824 | 80,824 | 0 | 80,824 |
| Flip-flops | Final | 81,058 | 81,058 | 0 | 81,058 |
| CARRY4 | Main | 2,587 | 2,597.2 | 62.56 | 2,611 |
| CARRY4 | Final | 2,455 | 2,460.6 | 46.64 | 2,473 |
| ABC9 delay (ps) | Main | 20,764 | 21,126.2 | 64,843.36 | 21,539 |
| ABC9 delay (ps) | Final | 19,937 | 20,338.6 | 57,545.04 | 20,594 |

Every sample has 104 RAMB18E1, 16 RAMB36E1, 144 DSP48E1, and no LUT RAM; these counts have zero variance. The final design uses fewer LUTs in every matched pair, and its worst LUT count is below the best main count. The arbitration-only intermediate version also has 81,058 flip-flops: the token repair adds no further mapped flip-flops in this workload. Mean CARRY4 use falls 5.26% and mean ABC9 mapping delay falls 3.73%. ABC9 delay is separate from routed timing and cannot establish a complete-design clock.

The ordinary, unrenamed core mapping used for place-and-route has 126,542 LUTs on main and 118,906 in the final design, a 6.03% reduction. Flip-flop and BRAM/DSP counts agree with the five-sample census. The harness adds 97 LUTs and 326 flip-flops to either version. All 212,346 main decoder primitives and 204,774 final decoder primitives survive harness assembly.

## Routed modeled paths

**These are partial-path estimates, not safe clocks for the complete decoder.** The pinned backend omits sequential timing for all 104 RAMB18E1 and 16 RAMB36E1 instances in both versions. Both retain 144 combinational DSPs with coarse input delays. Flip-flop checks use fixed 0.1 ns values, and shared Zynq timing tables do not select the requested speed grade. The [timing-model audit](../phi-timing.md#measurement-limits) identifies these omissions. The primitive census shows no change in known coverage between the versions; it does not prove completeness of every modeled arc.

| Version | Seed | Partial-path MHz | Logic ns | Routing ns |
| --- | ---: | ---: | ---: | ---: |
| Main | 1 | 12.93 | 6.8 | 70.5 |
| Main | 2 | 13.22 | 7.7 | 67.9 |
| Main | 3 | 13.43 | 5.6 | 68.9 |
| Final | 1 | 14.46 | 5.7 | 63.5 |
| Final | 2 | 11.89 | 5.7 | 78.4 |
| Final | 3 | 12.62 | 5.8 | 73.4 |

Main: best **13.43 MHz**, mean **13.19 MHz**, population variance **0.0420 MHz²**, worst **12.93 MHz**.

Final: best **14.46 MHz**, mean **12.99 MHz**, population variance **1.1693 MHz²**, worst **11.89 MHz**.

Best means highest frequency. Statistics use nextpnr's reported precision and three exploratory placement seeds. All six routes complete, but none meets the requested 100 MHz constraint.

Fresh main's first two worst paths start at X-plane output-cursor bits 4 and 1 and reach queue-bank update logic. Its third starts at a scheduler router's input-valid register and passes through shared-scheduler result retirement and stage completion before reaching the reduction plane. All three final worst paths begin in scheduler control or upstream router validity and pass through `SharedService` result selection, retirement, and `p0_stage_done` logic. These paths point to completion/ready fan-out and the placement of scheduler control as the next timing targets.

The final paths contain 5.7–5.8 ns of modeled logic delay and 63.5–78.4 ns of routing delay. In seed 3, a final reduction-plane control net alone contributes 14.5 ns of routing delay. The full paths are retained in the JSON. The best final frequency increases, but the worst decreases from 12.93 to 11.89 MHz; the paired changes for seeds 1–3 are +11.83%, -10.06%, and -6.03%. Three seeds do not establish how frequently those outcomes occur in the broader placement space.

Routing requires 10, 9, and 15 negotiated-congestion iterations on main and 4, 19, and **121** in the final design. All end with zero overused wires and zero architecture-binding failures. The last seed's long routing tail is a practical cost of this particular placement. Post-placement repair still relocates 39,354–39,432 stranded clusters/cells on main and 36,763–37,021 in the final design. These observations do not isolate an RTL cause from limitations in the placer and router.

Core and harness assembly pass `check -assert` and have zero combinational strongly connected components. The assembly check preserves the multiset of decoder primitive types and parameters and puts active sequential clocks on one BUFG; it is not a formal wiring-equivalence proof. Each completed run has 6,480 warnings for unconnected DSP cascade outputs and zero errors. The JSON retains their groups, counts, and examples; no routing errors or ignored combinational loops are accepted.

## Comparison with the previous placed-and-routed measurement

The [September 12 measurement](d3-2026-09-12.md), recorded at revision `26ae5cae82acca1ecc32e8fa21e77a1e62445db3` with application source unchanged from `d62c66f`, is the previous placed-and-routed D3 result. Its [archived JSON](d3-2026-09-12.json) verifies the same workload parameters, XLS compiler and standard-library hashes, RAM configuration and implementation, Yosys/ABC and nextpnr binaries, chip database, XDC, requested frequency, and router. The application RTL has changed since then. The later September 13 phi-memory debug report measures synthesis of a different workload and is not a placed-and-routed timing baseline.

| Version | Seed 1 | Seed 2 | Seed 3 | Best | Mean | Variance | Worst |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| September 12 | 13.10 | 14.11 | 13.92 | 14.11 | 13.71 | 0.1921 | 13.10 |
| Current main | 12.93 | 13.22 | 13.43 | 13.43 | 13.19 | 0.0420 | 12.93 |
| Final PR | 14.46 | 11.89 | 12.62 | 14.46 | 12.99 | 1.1693 | 11.89 |

Frequencies are partial-path MHz; population variance is in MHz².

| Core primitive, ordinary unrenamed mapping | September 12 | Current main | Final PR |
| --- | ---: | ---: | ---: |
| LUT1–LUT6 | 125,561 | 126,542 | 118,906 |
| Flip-flops | 79,578 | 80,824 | 81,058 |
| CARRY4 | 2,625 | 2,620 | 2,473 |
| DSP48E1 | 144 | 144 | 144 |
| RAMB18E1 | 90 | 104 | 104 |
| RAMB36E1 | 22 | 16 | 16 |

Relative to September 12, the final PR uses **5.30% fewer core LUTs** and **1.86% more flip-flops**. Its mean modeled frequency changes by **-5.25%**. The intervening changes already moved current main's LUT count by **+0.78%** and its mean modeled frequency by **-3.77%**, before this PR's changes.

All three versions measure 175.958333 cycles/step on the same deterministic throughput stimulus. The old critical paths began at a reduction-plane output cursor and reached contribution-key comparison or queue-bank update logic. In the final routes, the longest modeled paths begin in scheduler control or upstream router validity and traverse result-retirement/stage-completion logic. The previous run repaired 40,607–40,745 stranded clusters/cells after placement; that count is lower now, but substantial repair and routing sensitivity remain.

The older design has a different BRAM census, and those sequential arcs are omitted from the backend's timing model in every version. The class of known omissions and the count of coarse combinational DSPs are unchanged, but the set of excluded BRAM instances is not identical. Comparisons to September 12 describe the cumulative change since that measurement; the fresh main-versus-final pair isolates this PR under matched resource coverage. Neither comparison establishes a complete-design clock.

## Behavior and RAM ordering

Both final and main RTL measure **175.958333 cycles/step** between steps 8 and 32 under the same variable sink readiness, with 103 X-plane and 124 Z-plane stalled cycles and 63/64 corrections. The independent strict comparison also matches valid timing and every valid payload cycle for cycle over **12,000 clocks**, including long independent sink stalls and a mid-run reset: 646 X-plane and 642 Z-plane frames, with 1,425 and 1,729 stalled cycles. These deterministic checks have no stimulus-seed distribution. Do not combine the simulated cycle count with partial-path MHz to claim deployed throughput.

The three-stage mailbox regression initially failed after the arbitration change. Public scoped `hls_debug:info` snapshots identified a consumer in `waiting` with two queued messages, no postponed work, and `invalid_message`. A diagnostic at the public RAM boundary then showed a write of the new work frame and a read of the same row at 195 ns; the read-before-write RAM returned the old configure frame. This was reproduced with the independent XLS response-reservation fix, so it was distinct from the earlier dropped-response bug in XLS.

With the carried token, the write occurs at 185 ns and the read at 195 ns, returning the new frame. Mailbox postponement, backpressure, and recovery checks pass at two, three, and four XLS stages. The two-stage fixture retains consecutive-clock reads. These regression witnesses support the fix but do not formally prove scheduler RAM ordering for all stalls, resets, and configurations; that remains a Roadmap task.

An earlier repair used a circulating non-bypassing FIFO to publish the next selection after writes. It passed the mailbox regression but measured 266.083333 cycles/step on D3, losing about 34% of step throughput. Retiming variants retained that penalty. Per-actor tracking was also prototyped, but the carried token expresses the required dependency much more simply and preserves the measured throughput. The final implementation contains none of those new queues or tracking tables. The JSON retains the initial arbitration-only synthesis experiment separately; no routed result completed for that intermediate version.

## Validation and reproduction

The final RTL also passes the public topology-debug integration check: 254 channels and 88 FIFO occupancies are discoverable. Nine blocked seeds lead through 92 adaptive queries to the deliberately stalled `x_decoder_event` sink; probing after release confirms recovery. Structural and public cycle-by-cycle noninterference checks pass. Scoped actor debug is exercised separately by the mailbox fixtures and the complete D3 debug CI composition. The physical measurements do not quantify instrumentation overhead.

All **841 EUnit tests**, the generated reduction semantics regressions, and **16 generated-RTL SAT proofs** pass. The proofs cover every request mask, legal cursor, and acceptance choice for populations 1, 2, 3, 4, 9, 16, 17, and 32 with minimal and 32-bit cursors. An independent circular scan checks winner, empty output, cursor advancement, and bounds. A decreasing circular-distance rank bounds continuously eligible contenders by N accepted grants; it does not bound wall-clock wait or arbitrary intermittent eligibility. Twelve debug discovery/protocol tests and eight native physical-runner tests also pass, including real Yosys mapping/assembly. [Both CI jobs pass for the measured implementation](https://github.com/ecpeterson/erl_hls/actions/runs/34821043192).

Follow the [compilation and physical-run instructions](../phi-timing.md#run), preserving separate baseline and candidate RTL directories. Then use the [comparison commands](../phi-timing.md#compare-compiler-changes) for the strict public-interface check and five matched mapping name seeds. Route seeds 1, 2, and 3 for each version with the ordinary physical runner. The JSON preserves compiler/source/stdlib/RTL hashes, exact mapping scripts and tool hashes, chip-database/XDC/netlist hashes, route-output hashes, full critical paths, coverage, warnings, and behavioral evidence. `${REPO}` abbreviates the original checkout path; file digests refer to the original bytes. Generated RTL, synthesis logs, and the large chip database remain build artifacts.
