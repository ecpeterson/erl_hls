# Numerical rebalance on the N6 / 3+3 repetition application

**The timing improvement persists on both complete Zynq-7030 roles.** The slower-role static setup-equivalent bound falls from 20.898 ns to 14.820 ns, a 29.1% reduction. Individual roles improve by 26.1% and 35.9%. This retains about 76% of the smaller experiment's 38.2% percentage reduction, while using a different device and larger application. It is not a cross-device speedup or measured execution frequency.

## Application and intervention

This is fresh `phi_protocol_config:repetition(6, #{split => 3})` source-protocol generation: two independent roles, each with three data, three syndrome and three Phi actors. The eighteen-actor application has eight inter-role crossings and a 128-bit frame ABI. Each native top includes its complete generated role, framing, transport, credits and attachment/retirement machinery. The host relay, physical Ethernet/GTX link and PS7/board shell are outside the native top.

The candidate applies the exact constant-enabled [N2 numerical rebalance](spacetime-numerical-rebalance-physical-1.md) to all six Phi actors. Two signed 36-bit numerators and non-phi action metadata are retained at the existing action edge; rounding, anyon injection and saturation finish before entry/publication on the next existing edge. Ownership, old-state outbox admission, ordinary receipts and blocked-entry retention remain unchanged. There is no extra clock stage or shared arithmetic. Three owners add 219 declared register bits per role; native register counts also reflect optimization and replication.

Both variants use the same frozen fabric source (`0ae93e086e70071b1bdc1f7a650a78cc227a8ef1`), compiler/runtime (`38e1f9bf08046e714d5479ffd5112afa00e8ee64`) and generation settings. All 406 source inputs and both compiled release identities were checked. Existing N2 arithmetic qualification was reused; it was not rerun.

## Matched native result

| Role                       | Baseline 5-WNS | Rebalance 5-WNS | Reduction |
| -------------------------- | -------------: | --------------: | --------: |
| Role 0                     |      20.067 ns |       14.820 ns |     26.1% |
| Role 1                     |      20.898 ns |       13.399 ns |     35.9% |
| Slower role in each design |      20.898 ns |       14.820 ns |     29.1% |

| Role / variant      |   LUTs | Flip-flops |
| ------------------- | -----: | ---------: |
| Role 0 baseline     | 20,383 |     11,680 |
| Role 0 rebalance    | 22,404 |     13,411 |
| Role 1 baseline     | 20,768 |     12,015 |
| Role 1 rebalance    | 20,759 |     11,535 |
| Aggregate baseline  | 41,151 |     23,695 |
| Aggregate rebalance | 43,163 |     24,946 |

Aggregate cost rises by 2,012 LUTs (4.9%) and 1,251 FFs (5.3%). Both roles fit the target's reported 78,600 LUT / 157,200 FF capacity and the unchanged diagnostic 30,000 LUT / 18,000 FF per-role screens; the aggregate remains below 60,000 LUT / 36,000 FF. This does not requalify the historical component screens or account for the missing board shell. DSPs, BRAM and latches are zero throughout. Different per-role area responses are observations from one fixed implementation each, not evidence of a deterministic area saving in role 1.

All four jobs use Vivado 2024.2, `xc7z030sbg485-1`, a 5 ns BUFG clock, OOC synthesis with rebuilt hierarchy, Default implementation and two threads. There is one attempt per variant/role, executed serially, with no restart, reroute or settings sweep. The smaller N2 reference used `xczu7ev-ffvc1156-2-e`; only the within-pair fractional reductions are being compared.

**The 5 ns target fails in all four cases.** Routed WNS is -15.067/-9.820 ns for role 0 and -15.898/-8.399 ns for role 1. The period figures hold the reported constraints/skew fixed; they are not independently revalidated alternative clocks. Hold slacks are +0.048/+0.088/+0.044/+0.052 ns in execution order, and pulse slack is +2.1 ns throughout. All routable nets are routed with zero routing errors; internal clock, unconstrained-endpoint and loop checks pass.

Each default OOC DRC report contains exactly one `ZPS7-1` warning requiring the missing PS7 block. Original zero-DRC gates and their failed comparison remain unchanged. A separately retained, exact-match policy admits only this warning for the **standalone PL static comparison**; other findings or missing evidence reject. Zero-DRC and board-deployment admission remain false. The policy changes neither hardware nor native constraints and does not establish a usable board configuration.

## Finite two-role qualification

The new witness runs actual baseline role 0/1 RTL with BEAM host brokers, cross-role relay and correction feedback. Candidate twins receive identical offered inputs, ready calendars, reset and retirement. Every public handshake and meaningful valid payload is compared on every clock, including independent stalls. Across two incarnations, 110,980 role-cycle samples match, followed by four retirement samples. Each incarnation reproduces 107 canonical events, 17 corrections, fence 14 and six readouts equal to one. Postponement is exercised; retirement cancels remaining chatter with no held input bytes/beats.

These are finite public value/clock witnesses. Internal actor controls were not observed in this larger harness. Host-paced clocks differ across incarnations, so they cannot establish sustained throughput; this is also not a prospective new-workload validation of the control model. No native equivalence, unrestricted progress or live-device result is claimed.

## Remaining path population

The routed baseline role-0 worst path has 53 logic levels and 19.996 ns data delay; role 1 has 46 levels and 20.784 ns. Candidate role 0 has 27 levels and 14.523 ns data delay, of which 12.449 ns (85.7%) is routing. Its fifty worst reported paths associate with actor 7 machine-to-machine control, including a register-enable endpoint. Candidate role 1 has 27 levels and 13.323 ns data delay, including 11.274 ns routing; its worst path associates actor 11's held input with private action selection metadata.

These source names and width/layout correspondences are provisional associations. Narrowed/recoded or unsupported fields remain unknown; they do not establish native equivalence, dynamic sensitization or why the placer/router chose its layout. No new candidate geometry export or viewer dataset was made.

## Runtime, integrity and retention

| Native job       | Synthesis |     Opt |    Place |  Physopt |     Route | Total runner |
| ---------------- | --------: | ------: | -------: | -------: | --------: | -----------: |
| Baseline role 0  | 315.372 s | 5.106 s | 73.175 s | 25.979 s |  81.409 s |    543.135 s |
| Rebalance role 0 | 820.596 s | 5.105 s | 87.174 s | 35.264 s |  98.863 s |  1,091.002 s |
| Baseline role 1  | 235.118 s | 4.928 s | 74.272 s | 30.631 s |  68.904 s |    455.469 s |
| Rebalance role 1 | 230.415 s | 5.002 s | 78.602 s | 23.861 s | 135.170 s |    514.563 s |

Reports, checkpoints, functional-netlist export and startup/exit overhead are separate in `final-review.json`; table compute columns do not sum to the runner total. Local compilation/witness wrappers and child times are nested, not additive. The original baseline compile guard did not observe XLS processes in separate sessions; their retained child records show maximum RSS at most 2.036 GB. Later local work used a descendant-aware 6 GiB guard. All native jobs exited zero without guards and within their original windows; maximum native group RSS was 8.18 GB. Calendar, approval and queue gaps are not counted as compute.

All eleven inputs and thirty-two outputs per native job were terminal-verified, with actual runner and owned group gone. Each job was collected and fully reviewed once. Finalization rechecked retained compressed report contents against those authoritative raw hashes, then verified every archive member's size/hash. The 11,257,394-byte reproduction archive contains 872 members (73,073,633 raw bytes), below the 20 MiB cap. SHA-256: `bb1d6a199ab3aac8ac64b71a4125e1ab1954c8bf86b3e0c83d3cf0197fb54070`.

Artifacts: `/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-08/numerical-rebalance-3plus3-1/`. The final review preserves original and supplemental OOC decisions, exact source/IR/RTL and harness evidence, finite traces, phase/runtime records and remote DCP identities. Bulk products remain subject to seven-day retention review. This publication changes only measurement notes; the production backend and baseline viewer catalogue are unchanged.
