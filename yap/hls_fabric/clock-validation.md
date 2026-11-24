# Clock-crossing qualification

Maintainer procedures for the [clock-domain contract](../../docs/hls_fabric/clock-domains.md).

## Validation

`tools/hls_fabric/test_async_fifo.py` checks depth 4, 8 and 16, with write/read periods 6/14, 14/6, 10/10 and 4/22 ns. It exercises hundreds of pointer wraps, exact capacity, randomized stalls, stable output under backpressure, stopped read/write clocks, reset while full with a stopped reader, and reset during active traffic. Epoch-tagged words distinguish old and new work after reset. With `--xilinx-cells /path/to/yosys/xilinx/cells_sim.v`, the runner also maps a depth-eight, 37-bit FIFO and repeats the regression against the actual XC7 memory/flip-flop simulation models; CI includes this check.

`test/formal/async_fifo.sby` checks a four-entry, two-bit instance against an independent eight-entry reference queue with arbitrary payloads. Both clocks, requests, readiness and common reset are unconstrained after an initial reset. The `prove` task uses ABC PDR to establish capacity, nonempty valid output, ordered data and quiescence during reset for unbounded digital executions. The `cover` task requires traffic beyond one complete FIFO wrap. This is a proof for that instance and digital clock model, not a proof for every parameter, physical metastability or application progress. No fairness assumption requires either clock to keep running.

The phi harness first resets both graphs and all crossings during a partially transmitted packet. It then begins a fresh application epoch, holds the 0→1 admission gate, and uses public topology queries to follow full queues to that output. After stopping device 1's clock and opening the gate, it saves another public inspection of device 0's blocked output. Device 1 resumes and every actor's correction/status sequence through step 32 is compared with the independent BEAM oracle. The public debug protocol carries all host observations; VPI transports only external debug beats. No private actor registers are inspected.

CI checks the standalone FIFOs and both phi populations: `[2,2]` X/Z at 6/14 ns and `[4,2]` X at 14/6 ns, against a 10 ns host clock. Clock periods can be changed without regenerating XLS RTL: `--reuse-build --clock-halves 7 3` validates the same build and creates a separate simulation directory. The retained `clocks.json` records periods and phase; source/tool/artifact hashes and debug observations remain beside each run. Native validation additionally covers `[3,4]` X at 4/22 ns: six lanes with distinct neighbors, 396 statuses and 82 corrections through step 32. Formal tools are an additional native validation, not a dependency of the ordinary CI job.

```sh
python3 tools/hls_fabric/test_async_fifo.py
sby -f -d _build/async-fifo-proof test/formal/async_fifo.sby prove
sby -f -d _build/async-fifo-cover test/formal/async_fifo.sby cover
python3 workloads/hls_phi/tools/test_phi_bridge.py "$XLS_ROOT" --stage _build/phi-clocks --shape 4 2 --planes x --clock-halves 7 3
```

## Area

The six depth-eight FIFOs together map to **256 LUTs and 198 flip-flops**, with no BRAM or DSPs. Of the LUTs, 160 implement distributed memory and 96 implement logic. Two ABC9 naming seeds give identical results: best/mean/worst 256 LUTs, population variance 0; the FF result likewise has variance 0. The pre-synthesis estimate was 300–660 LUTs and about 228 FF before shared reset logic. Synthesis shares equivalent reset and pointer logic.

This is the isolated crossing bundle with all data bits live, synthesized for XC7 without I/O pads or clock buffers. It excludes actor cores, credit endpoints, debug services, the testbench's admission stages and any physical transport; it is not a whole-decoder or placed timing measurement. The [machine-readable report](../../docs/hls_fabric/artifacts.md#historical-reports) (`experiments/results/clock-crossing-measurements.json`) records source hashes, mapping version and primitive counts. Reproduce with `python3 tools/hls_fabric/measure_clock_crossings.py --yosys /path/to/yosys`.
