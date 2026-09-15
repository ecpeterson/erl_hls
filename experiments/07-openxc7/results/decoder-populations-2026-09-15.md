# Smaller decoder populations

The configurable profile measures **33,629 mean core LUTs** for four phi cells across both planes, **70,216.5** for eight phi cells, and **35,031** for the latter's X plane alone. Omitting that plane saves 50.11% of mean LUTs, consistent with the prediction that duplicating executors dominates this core's cost. The [machine-readable report](decoder-populations-2026-09-15.json) retains all six mapping samples, distributions, source/tool/RTL hashes, and functional validation results.

These are population probes for the intended 4×2 physical board assignment (four data, four syndrome, four phi cells), ahead of a 4×4 physical grid across two boards. They are closed periodic graphs, with deterministic replay sources and the current fixed kernel: two field layers and twelve diffusion rounds. They exclude the full data/measurement network, board partition links, PS interface, and external debug gateway. A smaller closed torus does not implement a partition with remote neighbors.

## Matched XC7 mapping

All configurations use the same native Darwin ARM64 XLS binaries and standard library, two pipeline stages, II=1, the unit delay model, unflopped inputs, flopped outputs, and the same 1R1W scheduler RAM recipe. Mapping uses `synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf` after renaming with seeds 1 and 2. All six mappings pass `check -assert` and `scc -expect 0`. The two seeds are a quick descriptive screening measurement, not a confidence interval.

| Profile | Phi shape per plane | Planes | Phi actors | Phi schedulers | Replay schedulers |
| --- | --- | --- | ---: | ---: | ---: |
| board-sized | 2×1 | X, Z | 4 | 2 | 2 |
| small-both | 2×2 | X, Z | 8 | 4 | 2 |
| small-x | 2×2 | X | 4 | 2 | 1 |

| Core LUTs | Seed 1 | Seed 2 | Best | Mean | Population variance | Worst |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| board-sized | 33,606 | 33,652 | 33,606 | 33,629 | 529 | 33,652 |
| small-both | 70,171 | 70,262 | 70,171 | 70,216.5 | 2,070.25 | 70,262 |
| small-x | 35,283 | 34,779 | 34,779 | 35,031 | 63,504 | 35,283 |

| Profile | Flip-flops | RAMB18 | RAMB36 | DSP |
| --- | ---: | ---: | ---: | ---: |
| board-sized | 29,477 | 44 | 8 | 48 |
| small-both | 52,253 | 74 | 12 | 96 |
| small-x | 26,121 | 37 | 6 | 48 |

The latter counts have zero variance: best, mean, and worst are identical. LUT RAM is zero in every sample. All ABC9 mapping delays are 16,874 ps; this is not routed timing or a complete-design clock limit. CARRY4 statistics are retained in the JSON.

The four-phi and eight-phi probes use 42.79% and 89.33% of a Z-7030's 78,600 physical LUTs respectively. This is useful evidence for measuring a four-phi partition with real links next, not proof of board fit. The two four-phi configurations differ in geometry, replay scheduler count, and reduction machinery; their difference does not isolate the cost of one replay scheduler.

## Behavioral validation

The test runner executes the actual Erlang actors and compares every event through step 32 with native-generated RTL, preserving each actor's event order while allowing concurrent actors' streams to merge differently. Each configuration runs once with ready outputs and once with deterministic independent stalls. The testbench checks complete status sets, stable valid/payload signals under backpressure, and inactive outputs for omitted planes. Removing Z preserves the surviving X seed block and event stream exactly.

| Profile | Events through step 32 | Corrections | Cycles/step, ready | Cycles/step, stalled |
| --- | ---: | ---: | ---: | ---: |
| board-sized | 132 | 0 | 93 | 93.041667 |
| small-both | 264 | 0 | 96 | 96 |
| small-x | 132 | 0 | 96 | 95.916667 |
| rectangle-z (2×3, Z, two shards) | 227 | 29 | 124 | 125.666667 |

Cadence is measured between complete status sets at steps 8 and 32. Small differences, including a slightly shorter stalled window, can reflect the relative completion phase at its endpoints; they are not evidence that stalls improve throughput. The testbench's legacy projected 200 MHz rate is hypothetical and is not used as a hardware result.

When both dimensions are at most two, opposite ports identify the same neighbor and the unique-maximum rule cannot choose corrections. Those cases exercise status progress and transport but are not nontrivial correction witnesses. The 2×3 Z case produces 29 corrections and supplies that additional BEAM/RTL check. No claim is made here about convergence or decoding accuracy for another code distance.

All four optional interface traces also pass aggregate delivery/retirement accounting. The rectangular test exercises queued scheduler-to-router effects; the timeline checks ordered later acceptance instead of requiring both sides to handshake on the same cycle. The tracer accepts one or two planes and the current 16-bit failure code in the reduction aggregate ABI. Normal profiling no longer needs the obsolete census of XLS-local scheduler signal names, and runs without VPI.

An instrumented four-phi profile exports 118 channels and 40 FIFO occupancies. Public framed debug queries identify two blocked seeds using 24 adaptive probes, find the injected external stall, and observe its release. Structural and cycle-by-cycle noninterference pass. This check uses channel/queue inspection, with no actor snapshot projection enabled. All 968 EUnit tests and the compile driver's 17 tests pass (one optional native test skipped). CI runs the board-sized and rectangular cases with tracing and the public debug stall check.

## Historical D3 reference

The default D3 topology DSLX is byte-identical to merged main `9b3cae6`; there is no new native D3 compile or D3 throughput measurement in this experiment. The last recorded full D3 mapping is [125,485.5 mean LUTs](checked-collections-2026-09-15.md). That is a larger workload at an earlier revision, not a matched before/after comparison with these populations.

The last placed-and-routed design remains [PR #102](d3-arbitration-2026-09-14.md): 118,906 LUTs, 81,058 flip-flops, 104 RAMB18, 16 RAMB36, and 144 DSPs. Partial-path frequency estimates were best 14.46, mean 12.99, population variance 1.1693 MHz², and worst 11.89. Missing BRAM timing and approximate register/DSP/device models prevent those estimates from certifying the complete design. No placement/routing or power measurement was performed for these smaller populations.

Reproduction commands and configuration semantics are in [Configurable decoder profiles](../decoder-profiles.md).
