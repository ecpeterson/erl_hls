# Complete D3 phi-memory debug cost

This experiment compares the complete `phi_memory_demo` application with and without optional observation services. Both variants contain 54 actors in six scheduler banks, the routed host gateway, application RAMs, and host serializer. The instrumented variant adds mailbox observation channels, committed actor snapshots, 217 channel probes, 75 FIFO probes, a shared debug router, and one routed boundary counter/trace monitor. The [machine-readable report](phi-memory-debug-2026-09-13.json) records the exact inputs, compiler/tool digests, mapping scripts, full cell counts, and public observations.

**All observation services add 4,676.4 LUTs (3.71%) on average, 2,485 flip-flops (3.67%), and three RAMB36 blocks.** In the native integration test, the instrumented and production application ports agree on every clock, including application recovery while a debug trace reply is blocked.

## Matched workload and scope

The fixture uses distance three and one executor per actor family (`--shards 1`). The gateway has two XLS pipeline stages, II=1, a unit delay model, unregistered inputs, registered outputs, and one-cycle 1R1W RAM responses. The independently compiled host serializer uses one stage; the observer uses two stages/II=1 and the debug server three stages/II=2. The archived compiler commands identify all flags and defaults. This 54-actor phenomenological memory workload differs from the 36-actor, three-shard decoder-only timing benchmark, so their raw totals are not directly comparable.

The production reference retains normal fail-stop actor execution and its machine-state failure-code fields. The area delta includes all optional observation paths in this deployment, including generated mailbox publications and debug transport. It does not include a hypothetical saving from replacing source-level failure codes with a single failed bit. One host boundary is monitored; additional boundaries have not been priced here.

## XC7 synthesis area

Each variant is flattened, optimized, and renamed with seeds 1–5, then mapped with `synth_xilinx -abc9 -arch xc7 -noiopad -noclkbuf`. The native mapper is Yosys 0.63+173 (`66306a8ca-dirty`); binary hashes are in the JSON. Identical frozen RTL/JSON inputs are used for every seed. LUT totals include distributed RAM footprints: the 30 `RAM32M` instances consume 120 LUTs. Carry chains, dedicated muxes, and other primitives are retained separately in the full JSON cell census.

| Variant | Best LUT count | Mean | Population variance (LUT²) | Worst |
| --- | ---: | ---: | ---: | ---: |
| Production | 125,306 | 126,179.0 | 378,464.80 | 127,156 |
| All observation services | 129,737 | 130,855.4 | 566,969.84 | 131,889 |

Best means the smallest area. These five name-scramble seeds describe mapping sensitivity; they are not a confidence interval.

| Seed | Production LUTs | All observation services LUTs |
| --- | ---: | ---: |
| 1 | 125,306 | 130,630 |
| 2 | 125,972 | 131,467 |
| 3 | 127,156 | 129,737 |
| 4 | 126,483 | 131,889 |
| 5 | 125,978 | 130,554 |

The following resources have zero variance across all five seeds of each variant; best, mean, and worst therefore coincide. The RAM-LUT row is already included in the LUT totals above.

| Primitive | Production | All observation services | Difference |
| --- | ---: | ---: | ---: |
| Flip-flops | 67,774 | 70,259 | +2,485 |
| LUTs used as RAM | 0 | 120 | +120 |
| RAMB18E1 | 82 | 82 | +0 |
| RAMB36E1 | 12 | 15 | +3 |
| DSP48E1 | 48 | 48 | +0 |

Before synthesis, the registered prediction was +3,000–5,000 LUTs, +2,000–3,000 flip-flops, +3 RAMB36 blocks, and unchanged application cycle behavior. The mean LUT increase is within that range; flip-flops are within their range, BRAM matches, and the native test finds no application cycle change. The complete implementation is the unit of comparison; these results do not isolate each service's individual contribution.

Every archived mapping passes final `check -assert` and `scc -expect 0`. Yosys emits intermediate loop warnings in both variants before mapping completes; the JSON retains their counts rather than suppressing them. Production seed 2 initially aborted inside Yosys `opt_clean` with an invalid free. Its retry used the same frozen inputs and command and completed successfully. No failed or partial mapping contributes to the distributions.

## Public-interface diagnosis and recovery

The host opens boundary and topology clients on the same `hls_fabric` broker. With application egress held, it inspects all 54 actors, queries all 75 FIFO occupancies, and follows eight full queues through `inspect_waits` to the blocked external `m_axis` sink. Every actor is initialized, has no recorded failure, and reports consistent occupied/free mailbox capacity.

The test then holds a trace reply and releases application egress, with counter and actor requests queued behind the trace on the shared debug transport. **512 application output beats are accepted while that debug reply remains blocked.** On resuming the debug reader, all requests complete, the wait inspection no longer finds the external sink persistently blocked, and the complete result matches ERTS: 80 corrections, 18 final data-qubit measurements, closeout step 18, and row parity 1.

The first trace drain contains one event. A later drain retains 64 events and reports 472 overflowed events, with zero dropped passive observations and no recorded framing gap. Trace-capacity loss is explicit and distinct from a rejected observation sample. Counter snapshots also report zero observation drops while application stall and traffic counts change.

The testbench compares production and instrumented input readiness, output validity, and valid output data/keep/last for **11,840 clocks**. It records 411 accepted input beats and 2,515 output beats in that run. Post-RTL instrumentation also passes exact alias-only comparison of the application's flattened JSON. VPI carries only the two external stream pairs; diagnosis uses public debug APIs rather than private signal reads.

The recorded recovery interval is 3,502 clocks from sink release to the latest output when the testbench notices host witness completion. Host scheduling and a 100-clock completion poll affect this number; it is not an application cycles-per-step benchmark. The final counter snapshot precedes simulation completion, so its totals need not equal the later testbench totals. Counter, trace, and actor snapshots are independent observations, not one atomic snapshot.

## Reproduction and limits

Follow the [complete fixture commands](../../../docs/topology-debug.md#complete-d3-phi-memory-fixture). The native functional run and five-seed area sweep use the input digests archived here. The new CI job independently rebuilds and runs the public integration test with the pinned Linux XLS release; [both CI jobs pass](https://github.com/ecpeterson/erl_hls/actions/runs/34749616515). Native validation also includes 793 EUnit tests, 12 topology/RTL tests, the existing actor/FIFO query integration, and trace loss/overflow/reset regressions.

These are full-design synthesis area counts, not a placed board design, a safe clock estimate, or a power measurement. Cycle equality establishes the tested logical behavior; it does not establish unchanged physical timing. Additional monitored boundaries, physical fanout/timing effects, and the cost of rich failure-code generation remain follow-up measurements.
