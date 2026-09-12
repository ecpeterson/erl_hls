# D3 decoder physical timing

This benchmark maps and routes the decoder-only D3 workload on `xc7z100ffg900-2` using the native Apple Silicon packages pinned in [the experiment setup](README.md#setup). It uses two phi planes, three scheduler shards per plane, and deterministic syndrome replay. XLS uses two pipeline stages, II=1, and its `unit` delay model. This is not the full phenomenological memory experiment or a board design.

The selected fabric has room for a large decoder experiment, and the installed Project X-Ray data contains its exact package. The two-pin harness assigns an MRCC clock input and an activity output within bank 33. These are compile-harness constraints, not a board pinout. The runner produces no bitstream.

The [2026-09-12 D3 baseline](results/d3-2026-09-12.md) records the measured seed distribution, resource counts, critical-path findings, and validation results.

## Measurement limits

**The reported MHz is a partial-path estimate, not a safe clock for the complete decoder.** The pinned nextpnr implementation has these timing-model limitations:

- `getPortTimingClass` does not model block-RAM ports or registered DSP configurations. Distributed-RAM writes and shift-register clocking are also omitted. Their sequential timing is therefore absent from the reported clock constraint checks; the report counts the affected mapped primitives.
- Unregistered DSPs receive coarse per-input combinational delays. Flip-flop setup, hold, and clock-to-Q use fixed 0.1 ns values.
- The chip-database importer loads shared `zynq7/timings/<tile>.sdf` tables. It does not select speed-grade-specific tables, even though the part string ends in `-2`.

The first two points follow directly from [the pinned nextpnr timing implementation](https://github.com/openXC7/nextpnr-xilinx/blob/68aeeb39f92e39bfb239c7e4a44dd93451fc1889/xilinx/arch.cc#L2375); the table selection is in [its device importer](https://github.com/openXC7/nextpnr-xilinx/blob/68aeeb39f92e39bfb239c7e4a44dd93451fc1889/xilinx/python/xilinx_device.py#L440). These omissions can hide the actual critical path. A successful route or a clean warning log does not establish complete timing coverage. The cell census records known omissions, not an exhaustive proof of timing-arc coverage.

Use the results to compare modeled paths, routing costs, congestion, and seed sensitivity under this exact toolchain. Do not multiply the partial-path MHz by simulated cycles per step to claim deployed throughput. Design-wide timing requires a backend with the missing sequential models and calibrated device timing, plus appropriate clock and I/O constraints. Hold timing, board interfaces, and silicon validation remain separate qualifications.

Check coverage before comparing frequencies: moving registers into a DSP can remove its paths from this backend's timing analysis. A higher reported MHz accompanied by newly excluded paths does not establish an improvement.

## Run

From the repository root, with the experiment packages installed and `ERL_HLS_XLS_ROOT` pointing to native XLS binaries:

```sh
rtl="$PWD/_build/d3-physical-timing/rtl"
stage="$PWD/_build/d3-physical-timing"
ERL_HLS_PHI_PROFILE_SHARDS=3 bash tools/prepare_xls_sim.sh "$rtl"
bash tools/compile_phi_decoder_profile.sh "$rtl" "$ERL_HLS_XLS_ROOT"
python3 experiments/07-openxc7/phi_timing.py "$rtl" --stage "$stage"
```

The compilation helper runs DSLX conversion, optimization, and RTL generation without installing private-state VPI hooks. It records compiler/stdlib/source hashes, RAM configuration, pipeline settings, and the final RTL hashes in `phi_decoder_profile.build.json`. Failed compilation does not publish a completed manifest. The physical runner verifies the workload parameters and RTL hashes before using them.

The default physical run requests 100 MHz and routes seeds 1, 2, and 3 sequentially. Change them with `--frequency` and `--seeds`; use `--jobs` to overlap independent seeds when memory permits. Phases `simulate`, `map`, `route`, and `report` can be invoked separately; `all` is the default. Core mapping, harness mapping, the chip database, and completed routes are cached against their inputs. A changed report or partial rerun cannot masquerade as a completed route. Use separate stage directories for comparisons whose artifacts should coexist, and run only one writer against a stage directory.

The first large-device database generation and synthesis take substantially longer than the small counter experiment. The generated chip database alone is about 637 MiB. Route sequentially on memory-limited hosts; the benchmark does not require building XLS or LLVM.

## Harness and checks

The application is synthesized out of context with `synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf`. The small harness is mapped separately, and the mapped decoder is then restored without another application synthesis pass. The assembly check requires the same multiset of decoder primitive types and parameters, plus a single global clock buffer feeding its active sequential clocks. This detects pruning or an accidental second clock; it is not a formal wiring-equivalence proof.

An independent LFSR varies both output-ready signals. Registers capture all output bits before a rotating activity digest, so the digest's XOR tree is separated from the decoder's output logic. The harness simulation checks accepted status/correction records, stall stability, nontrivial corrections on both planes, all nine coordinates through step 32, and a defined activity output. It reports cycles per step between steps 8 and 32 for this stimulus.

`check -assert` and `scc -expect 0` run on both mapped stages. Routing failures stop the run. Timing-target misses are retained with `--timing-allow-fail`; loops are not ignored.

Use the production query interface to diagnose application backpressure on the same RTL:

```sh
python3 tools/test_topology_debug_integration.py \
    --top phi_decoder_profile_top --clock aclk --reset aresetn --reset-active-low \
    --yosys "$PWD/experiments/07-openxc7/.apio/packages/oss-cad-suite/bin/yosys" \
    --stage "$stage/debug" \
    "$rtl/phi_decoder_profile.v" "$rtl/phi_decoder_profile_top.v" "$rtl/hls_1r1w_ram.v"
```

This check compares original and instrumented public outputs cycle by cycle, blocks an external sink, discovers full FIFOs through `hls_debug:info`, follows their dependencies with `inspect_waits`, then checks recovery after release. It saves `blocked.json`, `recovered.json`, and transport logs. The timing benchmark itself measures the uninstrumented decoder; the query check does not quantify instrumentation overhead.

## Reports and regression checks

`report.md` and `report.json` retain each seed's modeled critical path, logic/routing delay split, clock aliases, warnings, primitive coverage, and raw utilization, together with the mean, population variance, best, and worst partial-path MHz. Three seeds give an exploratory distribution, not a confidence interval. The detailed path comes from the final clock report in the nextpnr log because this pinned version leaves its JSON `critical_paths` array empty. A clock alias is accepted only when the log has an unambiguous single clock.

`core-stat.json` and `mapped-stat.json` retain Yosys resource counts. nextpnr's `SLICE_LUTX` denominator counts separately addressable O5/O6 BELs, not physical LUT packages; do not present that ratio as physical LUT utilization. Compiler, netlist, chip-database, XDC, tool, and per-route output hashes identify the measurement inputs.

Run `python3 experiments/07-openxc7/test_phi_timing.py` for fast report, coverage, retention, and provenance checks. When Yosys is installed, it also maps and assembles a small synthetic core through the real two-stage flow; set `YOSYS` to choose its executable. CI runs these checks with Yosys; the native D3 physical run is an explicit experiment.
