# Decoder physical timing

This benchmark maps and routes checked decoder profiles on `xc7z100ffg900-2` or `xc7z030sbg485-1` using the native Apple Silicon packages pinned in [the experiment setup](README.md#setup). The default D3 workload uses two phi planes, three scheduler shards per plane, and deterministic syndrome replay. The standard profiles use two XLS pipeline stages, II=1, and the `unit` delay model. This is not the full phenomenological memory experiment or a board design.

The larger fabric accommodates D3; the Z-7030 uses the checked SBG485 package overlay from the board preparation. The two-pin harness assigns an MRCC clock input and an activity output within bank 33 on the Z-7100 or bank 13 on the Z-7030. These are compile-harness constraints, not a board pinout. The runner produces no bitstream.

The [2026-09-12 D3 baseline](results/d3-2026-09-12.md) records the measured seed distribution, resource counts, critical-path findings, and validation results. The [2026-09-14 arbitration and RAM-ordering comparison](results/d3-arbitration-2026-09-14.md) compares fresh main and the changed design with that earlier measurement: LUT use falls while routed timing becomes more sensitive to placement seed.

The [2026-09-20 Zynq-7030 probe](results/z7030-decoder-2026-09-20.md) records the four-cell core mapping, two interrupted one-hour routing attempts, and a packed-netlist capacity bound for D3. It establishes no new clock estimate.

## Choose the probe budget

Start with the cheapest measurement that answers the PR's question. Run focused correctness checks and D3 throughput before the large synthesis or routing jobs, and measure the final candidate after those checks pass. Use small representative fixtures while comparing implementations. A change that leaves the generated RTL identical can reuse its verified measurements.

| Question | Initial probe | When to spend more |
| --- | --- | --- |
| Does the change preserve behavior and throughput? | Focused regressions, public-interface simulation, and D3 cycles/step | Expand workloads or pipeline stages when they exercise the changed path. Placement seeds do not add functional coverage. |
| Does mapped area change? | Two matched signal-name seeds, 1 and 2 | Expand to seeds 1–5 when the effect is small relative to the observed spread, changes sign, or needs stronger evidence. |
| Does physical timing or routability change? | Opt-in routing of matched seeds 1 and 2, after functional and mapping checks | Add seed 3 or a larger predefined set when the result could change an engineering decision or support a timing claim. A mixed result can remain inconclusive. |

These defaults require four synthesis runs instead of ten, and four physical runs instead of six for a fresh baseline/candidate pair: 60% and 33% fewer runs, respectively. Runtime does not scale exactly with count; congestion can make one seed much slower than the others. Reuse completed baseline measurements only when their RTL, workload, tools, constraints, and timing coverage match the intended comparison.

The September 14 comparison illustrates the distinction. Its first two synthesis seeds give a 5.74% mean LUT reduction, close to the five-seed result of 5.71%. Physical seed 1 improves modeled frequency by 11.83%, while seed 2 regresses by 10.06%; those two already justify reporting mixed timing. Seed 3 regresses by 6.03% and takes 121 congestion iterations, versus 4 and 19 for the first two. One favorable route would have been misleading, but the third was not necessary to discover the tradeoff. This is evidence for a cheaper screening policy, not proof that two seeds always suffice.

Keep every requested seed in the result, including failed or interrupted runs in the discussion; do not substitute easier seeds or silently drop slow ones. An incomplete route has no usable frequency. Choose any extension before inspecting its new results and include the entire set in the report. Report the sample count, individual results, mean, population variance, best, and worst. These small, deliberately selected sets describe sensitivity rather than establish confidence intervals. A one-seed smoke check is allowed with `--seeds 1`, but its zero population variance says nothing about seed sensitivity.

## Measurement limits

**The reported MHz is a partial-path estimate, not a safe clock for the complete decoder.** The pinned nextpnr implementation has these timing-model limitations:

- `getPortTimingClass` does not model block-RAM ports or registered DSP configurations. Distributed-RAM writes and shift-register clocking are also omitted. Their sequential timing is therefore absent from the reported clock constraint checks; the report counts the affected mapped primitives.
- Unregistered DSPs receive coarse per-input combinational delays. Flip-flop setup, hold, and clock-to-Q use fixed 0.1 ns values.
- The chip-database importer loads shared `zynq7/timings/<tile>.sdf` tables. It does not select speed-grade-specific tables, even though the part string ends in `-2`.

The first two points follow directly from [the pinned nextpnr timing implementation](https://github.com/openXC7/nextpnr-xilinx/blob/68aeeb39f92e39bfb239c7e4a44dd93451fc1889/xilinx/arch.cc#L2375); the table selection is in [its device importer](https://github.com/openXC7/nextpnr-xilinx/blob/68aeeb39f92e39bfb239c7e4a44dd93451fc1889/xilinx/python/xilinx_device.py#L440). These omissions can hide the actual critical path. A successful route or a clean warning log does not establish complete timing coverage. The cell census records known omissions, not an exhaustive proof of timing-arc coverage.

Use the results to compare modeled paths, routing costs, congestion, and seed sensitivity under this exact toolchain. Do not multiply the partial-path MHz by simulated cycles per step to claim deployed throughput. Design-wide timing requires a backend with the missing sequential models and calibrated device timing, plus appropriate clock and I/O constraints. Hold timing, board interfaces, and silicon validation remain separate qualifications.

The [native endpoint audit](timing_coverage/README.md) checks the running backend against explicit port/clock requirements and reproduces these omissions on small routed circuits. Passing those requirements does not establish complete timing coverage.

Check coverage before comparing frequencies: moving registers into a DSP can remove its paths from this backend's timing analysis. A higher reported MHz accompanied by newly excluded paths does not establish an improvement.

## Run

From the repository root, with the experiment packages installed and `ERL_HLS_XLS_ROOT` pointing to native XLS binaries:

```sh
inputs="$PWD/_build/d3-physical-timing/inputs"
stage="$PWD/_build/d3-physical-timing"
ERL_HLS_PHI_PROFILE_SHARDS=3 bash tools/prepare_xls_sim.sh "$inputs"
bash tools/compile_phi_decoder_profile.sh "$inputs" "$ERL_HLS_XLS_ROOT"
rtl=$(cd "$inputs/compiled" && pwd -P)
python3 experiments/07-openxc7/phi_timing.py "$rtl" --stage "$stage" --phase simulate
python3 experiments/07-openxc7/phi_timing.py "$rtl" --stage "$stage"
```

The [incremental compilation helper](../../docs/incremental-xls-builds.md) reuses checked conversion, optimization, and RTL-generation stages without installing private-state VPI hooks. It atomically publishes the completed profile bundle at `inputs/compiled`; pin that directory before simulation or measurement. It records compiler/stdlib/source hashes, RAM configuration, pipeline settings, and the final RTL hashes in `phi_decoder_profile.build.json`. Failed compilation keeps the previous successful bundle selected and retains diagnostics for the failed attempt. The physical runner verifies the workload parameters and RTL hashes before using them.

The default phase is `map`: it maps the core and harness without launching simulation or routing. The command above runs simulation explicitly first. Invoke `--phase route` to request physical timing; it requests 100 MHz and routes seeds 1 and 2 sequentially. Change those settings with `--frequency` and `--seeds`; `--phase all` explicitly runs simulation, mapping, and routing. Use `--jobs` to overlap independent seeds when memory permits, accounting for jobs in other stage directories too. Keep one or two large jobs active on a 16 GB host and check memory before increasing concurrency.

Core mapping, harness mapping, the chip database, and completed routes are cached against their inputs. Extend a run in the same stage directory with `--phase route --seeds 1 2 3` to reuse verified seeds 1 and 2 and compute only seed 3. Report regeneration requires the intended seed list too: `--phase report --seeds 1 2 3`. A changed report or partial rerun cannot masquerade as a completed route. Use separate stage directories for comparisons whose artifacts should coexist, and run only one writer against a stage directory.

The first large-device database generation and synthesis take substantially longer than the small counter experiment. The generated chip database alone is about 637 MiB. Route sequentially on memory-limited hosts; the benchmark does not require building XLS or LLVM.

## Zynq-7030 population probe

Prepare and validate the four-phi-cell population before routing it. This closed 2×1 grid per plane approximates a board's phi population; it excludes the data/measurement network, physical transport and external debug gateway. Opposing neighbors coincide in this small periodic graph, so use D3 as the nontrivial-correction check. See [profile geometry](decoder-profiles.md#geometry-and-populations).

```sh
python3 tools/test_decoder_profiles.py "$ERL_HLS_XLS_ROOT" \
    --stage _build/z7030-profiles --cases board-sized d3
python3 experiments/07-openxc7/phi_timing.py \
    _build/z7030-profiles/board-sized/compiled \
    --stage _build/z7030-physical --part xc7z030sbg485-1 \
    --device-root "$ERL_HLS_OPENXC7_BUILD_ROOT" --phase all --seeds 1
```

`--device-root` reuses the board experiment's checked database cache, avoiding another copy. Omit it to use `STAGE/device`. Start with one diagnostic placement seed; if it completes and another sample is useful, repeat with `--phase route --seeds 1 2`. Report both attempts. The default request remains 100 MHz for continuity with the historical measurement; a missed target is retained and disclosed. The runner accepts the compiled profile's dimensions and planes, checks the measured harness under variable sink readiness, and retains the same mapped-core preservation checks. The separate `compare` phase remains D3-only.

## Compare compiler changes

Preserve separately compiled baseline and candidate directories. A strict public-interface comparison drives both designs with identical independent sink stalls and a mid-run reset:

```sh
python3 experiments/07-openxc7/phi_timing.py "$candidate" \
    --reference "$baseline" --stage "$comparison" --phase compare
```

This requires matching workload, compiler, standard library, and RAM configuration. It checks output-valid timing and every valid payload, including values held while a sink is blocked. It rejects unknown outputs and requires progress after reset. Use this stronger comparison when a change should preserve cycle timing.

For intentional scheduling changes, add `--comparison-mode actor-sequence`. This compares accepted correction/status event prefixes separately for all 18 coordinates, preserving each actor's event order and every payload bit while allowing arbitration to reorder different actors. It checks both designs' payload stability across backpressure and requires each actor to progress before and after reset. The autonomous sources may reach different steps, so unmatched final prefixes and reset-discarded in-flight tails are outside this bounded comparison. Run the ordinary `--phase simulate` harness for each version as well to check complete status sets and measure cycles per step under variable sink readiness.

To screen sensitivity to synthesis naming order, map two matched signal-name seeds for each version:

```sh
python3 experiments/07-openxc7/measure_phi_mapping.py "$baseline" "$candidate" \
    --stage "$mapping" --jobs 2
```

The script scrambles internal signal names with `rename -scramble-name -seed` before the same XC7 core mapping flow, retaining the scripts, logs, resource counts, input fingerprints, and output hashes. `results.json` identifies the requested seeds and gives individual results plus best, mean, population variance, and worst resource counts and ABC9 delay. These names are not stimulus seeds. If more samples are needed, repeat the command in the same stage directory with `--seeds 1 2 3 4 5`; verified completed mappings are reused. ABC9 delay is a mapping estimate, separate from routed timing.

When the question warrants physical measurement, run the physical runner separately for each version with the same placement seeds and constraints:

```sh
python3 experiments/07-openxc7/phi_timing.py "$baseline" \
    --stage "$baseline_physical" --phase route
python3 experiments/07-openxc7/phi_timing.py "$candidate" \
    --stage "$candidate_physical" --phase route
```

Check timing coverage and individual paired results as well as the distributions. A mapping improvement does not imply a routing improvement.

## Harness and checks

The application is synthesized out of context with `synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf`. The small harness is mapped separately, and the mapped decoder is then restored without another application synthesis pass. The assembly check requires the same multiset of decoder primitive types and parameters, plus a single global clock buffer feeding its active sequential clocks. This detects pruning or an accidental second clock; it is not a formal wiring-equivalence proof.

An independent LFSR varies both output-ready signals. Registers capture all output bits before a rotating activity digest, so the digest's XOR tree is separated from the decoder's output logic. The harness simulation checks accepted status/correction records, stall stability, nontrivial corrections on active planes when the periodic geometry permits them, every selected coordinate through step 32, and a defined activity output. It reports cycles per step between steps 8 and 32 for this stimulus.

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

`report.md` and `report.json` retain each seed's modeled critical path, logic/routing delay split, clock aliases, warnings, primitive coverage, and raw utilization, together with the sample count, mean, population variance, best, and worst partial-path MHz. The detailed path comes from the final clock report in the nextpnr log because this pinned version leaves its JSON `critical_paths` array empty. A clock alias is accepted only when the log has an unambiguous single clock.

`core-stat.json` and `mapped-stat.json` retain Yosys resource counts. nextpnr's `SLICE_LUTX` denominator counts separately addressable O5/O6 BELs, not physical LUT packages; do not present that ratio as physical LUT utilization. Compiler, netlist, chip-database, XDC, tool, and per-route output hashes identify the measurement inputs.

Run `python3 experiments/07-openxc7/test_phi_timing.py` for fast report, coverage, retention, and provenance checks. When Yosys is installed, it also maps and assembles a small synthetic core through the real two-stage flow; set `YOSYS` to choose its executable. CI runs these checks with Yosys; the native D3 physical run is an explicit experiment.
