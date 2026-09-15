# Reduction inspection cost

Adding committed reduction metadata to the D3 debug service costs **456 LUTs and 55 flip-flops**, with no block RAM increase, against merged main `d21a93d` (PR #114). Both matched name-scramble seeds return identical counts. The [machine-readable report](reduction-inspection-2026-09-15.json) includes the input/tool digests, individual seeds, complete cell counts, distributions, and validation scope.

## Workload and method

The decoder-only D3 build contains 36 actors in eight shared scheduler banks: 18 syndrome sources and 18 phi actors, with three executors per phi plane. Each phi actor has 55 selected reduction metadata bits. The application uses two XLS pipeline stages, II=1, and one-cycle 1R1W RAM responses. Its generated actor DSLX is byte-identical to merged main.

Both measurements observe the exact same compiled application RTL: 262 channels, 88 FIFO occupancies, and 36 actor snapshots, including scheduler mailbox publications. The baseline uses main's projection generator, schema-4 query controller, snapshot RTL, and instrumentation tools. The new variant uses schema 5 and retains reduction metadata in the snapshot banks. Each manifest includes its own fingerprint constant.

`tools/measure_topology_debug.py --modes actors --seeds 2` isolates debug logic by making application observations unconstrained inputs while retaining their aliases and constants. Both variants use the same native Yosys 0.69+10 (`370a53acf-dirty`) and `synth_xilinx -flatten -abc9 -arch xc7 -noiopad`, after scrambling names with seeds 1 and 2. Every mapping passes `check -assert` and `scc -expect 0`.

## Results

| Variant | Best LUTs | Mean | Population variance | Worst |
| --- | ---: | ---: | ---: | ---: |
| Merged main | 1,306 | 1,306 | 0 | 1,306 |
| Reduction inspection | 1,762 | 1,762 | 0 | 1,762 |

All other resource counts also have zero variance across the two seeds; best, mean, and worst coincide.

| Resource | Merged main | Reduction inspection | Increase |
| --- | ---: | ---: | ---: |
| Logic LUTs | 1,146 | 1,386 | 240 |
| Distributed-memory LUTs | 160 | 376 | 216 |
| Flip-flops | 887 | 942 | 55 |
| RAMB18 | 0 | 0 | 0 |
| RAMB36 | 0 | 0 | 0 |

LUT totals include distributed RAM: each `RAM32M`/`RAM64M` occupies four SLICEM LUTs. The metadata shares each bank's indexed snapshot memory; its accumulator and seen-member bitmap are excluded. No additional application RAM port or observation channel is required. The schema-5 reply carries a 128-bit value and adds two stream beats to every topology query, including physical queries.

The registered prediction was 200–500 additional LUTs, 50–150 flip-flops, and no block RAM. The measured increase is within those bounds. The 34.9% LUT increase is relative to this isolated debug service, not the application. These two seeds test mapping sensitivity; they are not a confidence interval. This is not a placement, timing, power, or whole-design area result, and it does not replace the earlier placed-and-routed measurements. Passive tap fanout can still affect physical timing.

## Functional checks

The live ordinary-reduction fixture holds back three participants' startup commands. Through `hls_debug:info`, actor 0 reports a pending `badarith` at its source line with one contribution remaining, while actor 1 reports a healthy fold with the same remaining count. Neither has a terminal failure yet. After the host releases the normal application ingress, the healthy actor completes and the failing actors retain their expected terminal failures. Both two- and three-stage RTL agree cycle by cycle with their uninstrumented counterparts.

The offloaded version verifies the different observation boundary: recipient counts remain at three, with no pending failure, until their complete aggregates arrive. It then reports the same terminal outcomes. Partial source fragments are outside the recipient snapshot. Direct RTL independently waits for the withheld participants and produces exactly the one healthy result.

The D3 live test inspects all 36 actors under a blocked output and after release, follows nine blocked seeds with 92 adaptive queries, and finds identical application outputs for 4,800 clocks. Additional validation includes 986 Erlang tests, 12 Python/RTL discovery and protocol tests, 20 DSLX/JIT reduction tests, and an eight-step exhaustive snapshot comparison across five geometries. The snapshot tests cover full-width metadata, reset after reuse, invalid rows, asynchronous selection, and simultaneous reads/writes. Routed protocol tests vary all 128 observation bits and hold replies under backpressure.

Reproduce the current measurement with the commands in the JSON report. For the baseline, extract the projection generator and debug tools from `d21a93d`, regenerate its projection against the same actor artifacts, and instrument the same frozen RTL. Keep both manifests and all generated scripts/logs beside the results. The unchanged routed counter/trace services and outer debug router are excluded from this isolated comparison.
