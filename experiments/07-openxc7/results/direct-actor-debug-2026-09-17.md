# Register-backed actor observations: XC7 area

The five-actor reduction fixture is mapped in two configurations: the production application with physical channel/FIFO queries, and the application with those queries plus committed phase, failure, and reduction observations. Both include the same routed debug transport. Counters, event traces, board I/O, placement, timing and power are outside this measurement.

The compiler uses two pipeline stages, unit delay, input flops disabled and output flops enabled. Yosys runs `synth_xilinx -flatten -abc9 -arch xc7 -noiopad` with two matched name-scrambling seeds. Each build passes `check -assert` and `scc -expect 0`. The preserved instrumented JSON supplies the application so its memory attributes survive. Exact source/binary hashes, individual runs and full distributions are in the [machine-readable report](direct-actor-debug-2026-09-17.json).

| Metric | Configuration | Best | Mean | Population variance | Worst |
| --- | --- | ---: | ---: | ---: | ---: |
| LUT | Physical queries | 6457 | 6529.5 | 5256.25 | 6602 |
| LUT | Actor and physical queries | 6828 | 6828 | 0 | 6828 |
| FF | Physical queries | 4096 | 4096 | 0 | 4096 |
| FF | Actor and physical queries | 4225 | 4225 | 0 | 4225 |
| RAMB18 | Physical queries | 0 | 0 | 0 | 0 |
| RAMB18 | Actor and physical queries | 0 | 0 | 0 | 0 |
| RAMB36 | Physical queries | 0 | 0 | 0 | 0 |
| RAMB36 | Actor and physical queries | 0 | 0 | 0 | 0 |
| DSP | Physical queries | 0 | 0 | 0 | 0 |
| DSP | Actor and physical queries | 0 | 0 | 0 | 0 |

Mean LUT count rises from 6529.5 to 6828: +298.5 (+4.57%). The matched-seed increases are 226 and 371 LUTs. Flip-flops increase by 129 (+3.15%) in both seeds. No design uses distributed-memory LUTs, BRAM or DSPs.

The registered prediction was a modest per-actor retention/output-register cost plus selection/control LUTs. The measured result is consistent with that prediction, but it is not a per-actor cost bound: constant fields and repeated logic can optimize away in this specific fixture. The observation exposes no accumulator or payload. Two seeds describe mapping variation here; they are not a statistical estimate over arbitrary placements or applications.

Native live simulations at pipeline depths two and three query all five actors through the framed `hls_debug` interface. They distinguish healthy and failed incomplete reductions, wait for the missing participants, inspect terminal source locations, follow a stalled report to its sink, and verify release. Post-generation instrumentation preserves application outputs cycle by cycle. A separately compiled diagnostics-disabled reference emits the same complete application frame; that bounded transcript does not establish equal throughput for every workload.

Reproduce:

```sh
bash tools/test_actor_debug.sh XLS_ROOT _build/direct-actor-debug direct_reduction
python3 tools/measure_direct_actor_debug.py _build/direct-actor-debug \
  --stage _build/direct-actor-debug/area --yosys "$YOSYS" --seeds 2
```
