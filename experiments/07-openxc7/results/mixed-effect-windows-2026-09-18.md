# Effect-window ownership in mixed topologies

Mixed and exact-only deployments support `effect_window_partition => weak_components`. The planner finds weak components across physical shared groups and direct actors, then assigns lookahead ownership only to the shared groups. Direct relays, fan-in, fan-out, and shared executors connect dependencies; pure direct components need no arbiter. Compact families use the same planner and grant-channel emitter, including their bounded reduction-plane dependencies. `global` remains the default.

## Validation

The fixture contains two disconnected copies of the mixed feedback workload: 14 actors, four shared worker groups, six direct actors, and eight application RAMs. Group numbering interleaves the components, so the partition is `[[0,2],[1,3]]`. Each component's two shared groups connect through its direct collector and source. Each copy processes 320 work messages and 640 results to produce 32 reports matching the ERTS reference.

At both two and three pipeline stages, the live debug regression holds the first output while the second receives periodic backpressure. The host waits for the second source's terminal phase through `hls_debug:info`, inspects every actor and the blocked queue chain through the public debug transport, then releases the first output. Both complete transcripts must match. Original and instrumented application outputs agree on every cycle; Yosys rejects any combinational cycle before simulation.

Continuous assertions on the same passive handshake probes used by the query service establish that every grant port is exercised, observed grant/release balance stays within one owner per domain, and all grants return. The global run reaches one simultaneous owner; the partitioned run reaches two. These are finite RTL regressions, not an unbounded proof of scheduler or application deadlock freedom.

The separate application-port test resets both graphs while their outputs are blocked, then drives fixed periodic backpressure. It requires both complete post-reset transcripts and rejects duplicate output. Its cycle count is independent of the live test's host query/release timing. Native validation uses Icarus 12 and passes 1,110 EUnit tests. The graph tests exhaust all 64 undirected four-vertex graphs and all 16 owner subsets against OTP's graph implementation, as well as reduction hyperedges, shared executors, direct-only components, exact-only placement, and non-contiguous group indices.

An intermediate full-suite run failed the unchanged host test `physical_close_waits_for_partial_frame_test` (close returned `ok` where the fixture expected a timeout). Twenty baseline repetitions and the current branch's entire host-backpressure module passed; the subsequent full suite passed too. The cause of that isolated failure is unresolved. No host transport code or timeout was changed.

The generated compact D3 topology is byte-identical to merged `b06ea41` under both global and weak-component policies. The source hashes are retained in the accompanying JSON. This change does not replace or invalidate the existing D3 hardware measurements.

## Deterministic cycles

Counts start when the measured reset is released. Left output readiness is `cycle % 11 < 7`; right readiness is `cycle % 7 < 5`. Each output has 32 reports, hence 31 inter-report intervals.

| Pipeline stages | Policy | Left first / last report | Right first / last report | Left / right mean report interval |
| --- | --- | ---: | ---: | ---: |
| 2 | Global | 99 / 2,871 | 95 / 2,870 | 89.419 / 89.516 |
| 2 | Weak components | 99 / 2,871 | 95 / 2,870 | 89.419 / 89.516 |
| 3 | Global | 100 / 2,970 | 100 / 2,968 | 92.581 / 92.516 |
| 3 | Weak components | 100 / 2,970 | 100 / 2,968 | 92.581 / 92.516 |

Partitioning does not improve completion throughput in this workload, despite exercising simultaneous grants. These are logical cycle measurements, not placed-and-routed clock frequencies.

## Mapped area

The registered prediction was a change within about 1% of total fixture area, with unchanged RAM and payload storage. Two matched naming seeds map the complete two-stage fixture with its topology, actor, and mailbox query hardware using native Yosys 0.69+10 (`370a53acf-dirty`), XC7 ABC9, and no I/O or clock buffers. Boundary counter/trace monitors, board transport, placement, routing, power, and timing are outside this measurement.

| Resource | Global best / mean / worst | Weak components best / mean / worst | Population variance, global / weak |
| --- | ---: | ---: | ---: |
| LUTs, including distributed RAM | 15,742 / 15,789.5 / 15,837 | 15,924 / 16,032 / 16,140 | 2,256.25 / 11,664 |
| Flip-flops | 12,543 / 12,543 / 12,543 | 12,539 / 12,539 / 12,539 | 0 / 0 |
| RAMB18 | 12 / 12 / 12 | 12 / 12 / 12 | 0 / 0 |
| RAMB36 | 4 / 4 / 4 | 4 / 4 / 4 | 0 / 0 |

The paired LUT increases are 182 and 303; the mean increase is 242.5 LUTs, or 1.54%. That is slightly above the prediction. Both designs use 80 LUTs of distributed RAM and 20 RAMB18 equivalents. The totals include remapping and changed debug manifests; the LUT delta is not an isolated arbiter cell count.

For this fixture, global ownership remains the better measured choice. The opt-in partition permits independent lookahead where an application benefits, while the common planner and emitter remove separate implementations of the ownership rules. Two naming seeds establish the reported observations; they are not a broad statistical estimate of mapping quality. [Raw samples, distributions, cycle results, and input/tool hashes](mixed-effect-windows-2026-09-18.json) accompany this report.

## Reproduction

```sh
bash tools/test_mixed_topology.sh "$XLS_ROOT" _build/mixed-topology components_global components_weak
python3 tools/measure_mixed_windows.py _build/mixed-topology --area --yosys "$YOSYS"
```

The CI windows workload runs both pipeline depths, live public debug inspection, handshake coverage, and deterministic reset/recovery. Area mapping remains an explicit local measurement. Detailed commands, logs, and synthesis statistics are retained under `_build/mixed-topology` and `_build/mixed-windows`.
