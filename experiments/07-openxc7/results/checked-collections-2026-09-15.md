# Checked collection access: correctness and synthesis

This compares main `129279ab9ab33c2466876fe8be980e79abf7a746` with implementation `8e57f063a2f0b2e99b354287f7328d093bb161e9`. The [machine-readable report](checked-collections-2026-09-15.json) retains individual mapping samples, source/tool/RTL fingerprints, and validation evidence.

The prediction before synthesis was a modest logic increase from dynamic bounds checks, with constant accesses optimizing to wiring. The final `regsvc` measurement instead saves **18.70% of core LUTs on average**, with unchanged flip-flop count. This measures the combined collection lowering and overflow-safe application guard; it does not isolate their individual contributions. The constant-access probe lowers actual Erlang calls and optimizes to zero logic cells.

## Bounds and failure behavior

`nth/2` and `set/3` require a one-based index in `1..Size`. Both slice operations require the complete selected range to fit. `sublist/4` retains the declared output size by appending zeros; `array_slice/4` returns the requested positive constant length and permits a dynamic start. A zero-count sublist may start at `Size + 1`. Empty collection values remain supported by host codecs, but translating them reports `empty_xls_collection` because XLS IR does not support empty array values.

The static `hls_lists.x` module checks the full signed/unsigned index and count before truncating to the array index width. It widens bound comparisons and uses `count <= size + 1 - start` to avoid wraparound. Typed array access/update/slicing stays at the call site: XLS currently emits invalid IR symbols when type-generic helpers are instantiated with parameterized structs such as `APFloat`, including nested arrays. Float regressions cover serialized IR, not just interpreter/JIT execution. [`xls_collection_type_repro.x`](../../../test_data/xls_collection_type_repro.x) retains a minimal reproducer for the upstream fix; the source and Roadmap record the resulting simplification opportunity.

Invalid selected accesses produce `badarg` through the existing source-located failure carrier. Argument evaluation order, first-failure selection, branch masking, and actor recovery policy are unchanged. A failed access's placeholder data cannot become the callback's committed result/effect. Constant initializer failures reject compilation. GS replies decode the reason, and public shared-actor debug queries resolve failures to included-helper source locations. No new history buffer, recovery protocol, or actor-state field is introduced; XLS may pipeline dynamic checks.

The `regsvc` bulk-read guard uses `Start <= REGISTER_COUNT - Count` after bounding `Count`. Its previous `Start + Count` could wrap at 32 bits and accept a request rejected by BEAM. The large-start regression now selects the same `function_clause` failure on both targets.

## Matched regsvc mapping

Both versions compile their generated `regsvc` `Top` with the same native XLS tools and standard library, one pipeline stage, the `unit` delay model, unflopped inputs, flopped outputs, synchronous reset, and XLS-generated FIFOs. Each core is flattened and optimized, renamed with seed 1 or 2, then mapped using `synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf`. All four mappings pass `check -assert` and `scc -expect 0`.

| Metric | Version | Best | Mean | Population variance | Worst |
| --- | --- | ---: | ---: | ---: | ---: |
| Core LUTs | Main | 2,913 | 3,034 | 14,641 | 3,155 |
| Core LUTs | PR | 2,429 | 2,466.5 | 1,406.25 | 2,504 |
| Flip-flops | Both | 1,226 | 1,226 | 0 | 1,226 |
| CARRY4 | Main | 24 | 24 | 0 | 24 |
| CARRY4 | PR | 24 | 34 | 100 | 44 |

Every sample has zero LUT RAM, BRAM, and DSPs. Seed 1 changes 2,913 to 2,504 LUTs; seed 2 changes 3,155 to 2,429. The mean savings is 567.5 LUTs. Two synthesis naming seeds provide a screening measurement, not a confidence interval. No `regsvc` timing, power, or placed/routed measurement was taken, and the result does not establish an area bound for arbitrary collection sizes or actor programs.

## D3 and the last routed design

The decoder-only profile uses three scheduler shards per plane, two pipeline stages, II=1, and no debug instrumentation. The final native build again measures **180 cycles/step** with request-paced sinks and **182.583333 cycles/step** with variable sink readiness, completing all coordinates through step 32. A 12,000-cycle comparison against merged main matches public outputs cycle for cycle through long stalls and reset (635 X and 626 Z frames, with identical stalled-cycle counts). These checks cover the benchmark workload, not arbitrary programs.

Unlike `regsvc`, this profile's collection indices are constant. Their bounds checks optimize away, but the emitted RTL is not byte-identical: failure-site numbering and compiler node naming change. The wrapper and RAM implementation remain byte-identical. The matched D3 mapping below measures the final RTL; it must not be inferred from the small service's area reduction.

Both versions use the same native tools, standard library, profile, and RAM configuration. The flattened decoder core is mapped with `synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf`, after renaming with seeds 1 and 2. All mappings pass structural checks and have zero combinational SCCs.

| Metric | Version | Best | Mean | Population variance | Worst |
| --- | --- | ---: | ---: | ---: | ---: |
| Core LUTs | Main | 124,182 | 124,593.5 | 169,332.25 | 125,005 |
| Core LUTs | PR | 125,330 | 125,485.5 | 24,180.25 | 125,641 |
| Flip-flops | Both | 83,640 | 83,640 | 0 | 83,640 |
| CARRY4 | Main | 2,448 | 2,452.5 | 20.25 | 2,457 |
| CARRY4 | PR | 2,438 | 2,438.5 | 0.25 | 2,439 |
| ABC9 mapping delay (ps) | Main | 16,874 | 17,164.5 | 84,390.25 | 17,455 |
| ABC9 mapping delay (ps) | PR | 16,874 | 16,874 | 0 | 16,874 |

Every sample has zero LUT RAM, 104 RAMB18, 16 RAMB36, and 144 DSPs, with zero variance. Mean LUT count increases **892 (0.72%)**. Seed 1 increases by 1,459 LUTs; seed 2 increases by 325. The constant checks disappearing does not guarantee identical mapping: changed error encodings and RTL structure/naming can affect optimization and mapping choices. Two samples do not isolate these effects or provide a confidence interval. The 1.69% smaller mean ABC9 delay is a mapping-stage estimate, not measured routed timing or a validated clock improvement.

The last placed-and-routed design remains [PR #102](d3-arbitration-2026-09-14.md): its unrenamed core mapping used **118,906 LUTs, 81,058 flip-flops, 104 RAMB18, 16 RAMB36, and 144 DSPs**. Its partial-path frequency estimates were 14.46, 11.89, and 12.62 MHz (best 14.46, mean 12.99, population variance 1.1693 MHz², worst 11.89). PR #105 subsequently changed the D3 design; that historical route is not a timing result for this PR. Missing BRAM timing and approximate register/DSP/device models prevent those estimates from establishing a complete-design clock limit. No new placement/routing or power run was performed here.

The final cold native compile logged 197.0 seconds for IR conversion, 358.5 seconds for optimization, and 168.7 seconds for code generation, with maximum recorded RSS about 455 MiB. Other validation was running concurrently, so these are provenance and planning data, not a controlled compiler-speed benchmark. The incremental build cache remains applicable.

## Validation

All 888 EUnit tests pass. The collection corpus compares actual lowered Erlang expressions with BEAM results over all signed and unsigned eight-bit index/count pairs, plus 32/64-bit boundary and deterministic samples: **132,730 RTL vectors**, each checking indexing, update, padded sublist, and exact slice. Wider cases include values that would become valid if truncated to 32 bits, and signed cases include negative bounds. The emitted constant probe, including failure outputs, optimizes to wiring with zero cells.

The control-failure regression passes 59 interpreter/JIT cases and 708 service vectors at each of 1 stage/II=1, 2/1, and 3/2. It checks skipped failures, first-error precedence, helper propagation, failed constant initializers, stalled replies, and recovery. Public actor debug checks identify nth/set/slice failures at lines 23/27/32 of the included helper while a neighboring actor skips its invalid branch successfully.

The [pinned Linux implementation run](https://github.com/ecpeterson/erl_hls/actions/runs/34957847676) passes every behavioral step, including binary16/32/64, generated/bridged regressions, and complete D3 debug composition. Its only failure is the expected RTL digest mismatch. The manifest is refreshed from its tested artifacts; both compact DSLX goldens and the two phenom-cell RTL digests already match. Native binary16 arithmetic and actor tests also pass; the remaining native float sweep was stopped to avoid duplicating Linux validation.

## Reproduction

Run `bash tools/test_collections.sh "$xls"`, `bash tools/test_control_failures.sh "$xls"`, and `bash tools/test_float_arithmetic.sh "$xls"`. The CI actor-debug regression exercises the public query endpoint and verifies instrumentation noninterference.

For `regsvc` area, obtain the compact `regsvc.erl.x` and `priv/xls/lib` from each revision. Convert top `Top`, optimize, then codegen with `--pipeline_stages=1 --delay_model=unit --flop_inputs=false --flop_outputs=true --use_system_verilog=false --module_name=measured --reset=reset --fifo_module=`. The JSON retains exact tool commands, Yosys scripts, standard-library fingerprints, source hashes, and log hashes. `${REPO}` abbreviates the checkout path in that report; hashes refer to original files. Full generated RTL and solver/synthesis logs remain build artifacts.

For D3, run `ERL_HLS_PHI_PROFILE_TRACE=0 bash tools/run_phi_decoder_profile.sh "$stage" "$xls"`. Use `experiments/07-openxc7/phi_timing.py` with `--phase simulate` and `--phase compare --reference BASELINE_RTL` for variable-readiness and cycle comparisons. Run `experiments/07-openxc7/measure_phi_mapping.py BASELINE_RTL CANDIDATE_RTL --stage AREA_STAGE --seeds 1 2 --jobs 2` for matched mapping. The final pass reuses verified baseline mappings; only the changed candidate RTL is remapped.
