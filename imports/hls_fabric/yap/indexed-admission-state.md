# Indexed admission state

Child of #61; baseline `5147854`, application RTL `885e10d36c3a`. Artifacts: `hls_artifacts/runs/indexed-admission-state-2026-10-02/`. Original ordinary control: 2.971102 µs/round; #61: 2.716011 µs, 213,580 LUTs and 10.585 ns routed period. Keep those controls distinct.

## Decision and gates

Retain the source architecture and use the existing XLS optimizer with next-value splitting disabled. The initial aspiration was 20% fewer controller-own LUTs without extra clocks. Hierarchy attribution proved unstable: unchanged FIFO RTL received substantially different LUT assignments. Use complete subtrees, then the complete device, as area gates.

Qualification requires the complete 128-sheet correction oracle, preserved failure/debug behavior, and improved cycles × routed period. The selected candidate passes: 20.3% fewer routed LUTs and 6.4% shorter mean round time than #61. This is one matched routed comparison, not a hardware frequency measurement or a placement-seed distribution.

## Independent screens

Same six-group D3H3 indexed application and toolchain; sample top `SharedService_0__6_4_0_19_12`. Period proxies are 5 ns minus setup WNS after synthesis, not routed periods.

| Candidate | IR state bits, six controllers | IR nodes, six controllers | Complete sample LUTs | Assigned own LUTs | Period proxy |
|---|---:|---:|---:|---:|---:|
| Parent | 83,916 | 45,902 | 32,891 | 25,712 | 9.376 ns |
| Flatten arrays through eight rows | 75,924 | 82,762 | 30,594 | 20,460 | 9.293 ns |
| Flattening plus late narrowing | 75,396 | 83,068 | — | — | — |
| Disable next-value splitting | 84,390 | 46,376 | **25,926** | 18,416 | **8.339 ns** |
| Preserve each row's epoch locally | 82,764 | 45,758 | 32,050 | 25,275 | 8.955 ns |
| Flattening plus disabled splitting | 76,398 | 56,390 | 27,510 | 20,248 | 8.705 ns |

All four mapped candidates have exactly the parent's timestamped external event stream: 128 rounds, 1,125 corrections, 256.590551 mean clocks between rounds, 234–469 range and 3,039.627627 population variance. The combined candidate missed its 24–27k LUT / ≤8.5 ns forecast and loses to disabled splitting alone. The row-local edit remains a reproducible patch, not an unmeasured addition to the selected implementation.

## Complete application

Matched Vivado 2024.2, `xczu7ev-ffvc1156-2-e`, registered `technology_actor_top`, 5 ns constraint, identical scripts and RAM bindings.

| Stage | Parent LUTs | Candidate LUTs | Parent FFs | Candidate FFs | Parent period | Candidate period |
|---|---:|---:|---:|---:|---:|---:|
| Synthesis | 216,622 | 171,387 | 106,446 | 104,964 | 9.605 ns | 9.956 ns |
| Routed | 213,580 | 170,147 | 106,500 | 104,999 | 10.585 ns | 9.903 ns |

BRAM remains 48 RAMB36s after synthesis. Whole-device synthesized LUTs fall 20.9%, slightly beyond the preregistered 12–20% range. The timing estimate worsens despite the sample controller improvement: the limiting path lies in a different controller specialization (22 producer inputs, rather than the screened 19). It still runs through producer selection, collection admission and the collection-ready update; its synthesized path has 41 logic levels versus the parent's 40. These are estimates using unplaced nets. The 9.903 ns result lies in the preregistered 9.4–10.6 ns diagnostic range and passes the less-than-2.716011 µs/round gate.

| Derived round time | Parent | Candidate |
|---|---:|---:|
| Mean | 2.716011 µs | 2.541016 µs |
| Minimum | 2.476890 µs | 2.317302 µs |
| Maximum | 4.964365 µs | 4.644507 µs |
| Population variance | 0.340567 µs² | 0.298094 µs² |

Throughput rises 6.9%. Relative to the original ordinary collector, mean round time is 14.5% shorter with 10.7% more LUTs; this recovers 72.6% of #61's added LUTs. Both routed runs have +0.010 ns hold slack and +1.958 ns pulse slack, with no failing hold/pulse endpoints. Setup still fails the requested 5 ns clock: the reported period is requested period minus setup WNS, not a closure run.

The worst routed path remains in collection admission. The reported worst endpoints differ; their logic delays are 3.015 → 3.153 ns and route delays 7.347 → 6.573 ns. Thus the win accompanies less routing delay, not elimination of the admission dependency. This is consistent with the reduced logic footprint, but is not a matched-path causal decomposition. The sample controller's improved estimate did not predict the full-device pre-route regression; the latter also did not predict the routed improvement.

`accepted-comparison.json` checks completed execution/report hashes, the selected release's RTL hash and identical tool/version/constraints. Only the application RTL differs among physical inputs. `qualified-no-split/` uses the existing timing-report packager. Routed RTL SHA: `754952714554528f790690b66fd3ea2f27238ba1785da2c0f600f4b37b59b76d`.

## Mechanism and rejected leads

- Vivado already trims each retained 128-bit frame to 44 bits. Narrowing that source record alone mostly repeats existing pruning. Eligibility also needs epoch, direction membership, actor mode and failure/postponement state.
- Flattening exposes scalar state but does not guarantee narrowing. The six-row fixture stays at 192 bits under the default pipeline; a late provenance pass reaches 48. The full application gains only another 528 bits from that late pass, so it did not advance to mapping.
- Splitting changes one selected state update into several predicated writes. Disabling it reduces controller writes from 1,272 to 768 while retaining constant-predicate cleanup. The narrower `--split_next_value_selects=0` option does not stop priority-select splitting, which is why this experiment caps the two pass invocations instead. It saves more area despite slightly **increasing** IR state bits and nodes. This identifies update/control representation as the useful lever; bit counts alone would select the wrong candidate.
- Flattening increases writes to 20,138 yet still saves 7.0% of the subtree; neither node nor write counts predict mapped area in isolation. With splitting disabled, flattening has 3,336 writes and loses to the simpler configuration.
- Epoch-local source updates save 2.6% of sample LUTs without changing cycles. They are not in the routed candidate. Keep their measured result separate from the selected compiler policy.

## Validation and provenance

- [x] Check native flattening tests and addressed-row RTL (8,192 replies per variant, including stalls, out-of-range indices and drained reset).
- [x] Check row-local transitions with the production adapter/kernel suite and member-memory RTL test.
- [x] Replay all mapped variants against the frozen full application oracle and timestamps.
- [x] Test live indexed queries with the selected optimizer pipeline at two and three codegen stages: partial gathers, hidden successors, ordered reports under stalls, and structural/cycle noninterference.
- [x] Reproduce measured optimized IR and all RTL bytes through the supported `--optimizer-pipeline` option. Fresh source generation from the final tree matches the measured release and vectors.
- [x] Check materialized monoid collectors at two and three stages: early contributions, backpressure, reset, isolated actor failure, interleaved keys, invalid opening masks and out-of-range members.
- [x] Test configuration/tool hash checks, immutable pipeline publication, mismatched replay rejection, and run Dialyzer.
- [x] Complete matched full-device routing and report its throughput gate.

The compiler pipeline and original optimizer are frozen/hash-checked by the backend; no tool installation or public checkout is modified. The C++ and source alternatives remain experiment patches. The first full-route attempt used the wrong top and was stopped; the corrected flattening attempt was stopped before results when the stronger candidate became available. Neither supplies a physical result. One local publication ran out of disk; checked completed stages were retained and publication resumed after disposable simulator binaries and an obsolete fast-build cache were removed.
