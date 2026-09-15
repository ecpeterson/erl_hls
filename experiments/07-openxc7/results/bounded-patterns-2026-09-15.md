# Bounded patterns: D3 validation

This compares PR #107 (`e5066371b37ddd7e089d8ddb1090612e56208ad7`) with the bounded-pattern implementation (`b79068f3293d3ddf1eaaead5c4605dfec7964aba`). The [machine-readable report](bounded-patterns-2026-09-15.json) records compiler inputs, tool and RTL fingerprints, individual mapping samples, commands, and validation log hashes. The later verification changes affect the D1 testbench, documentation, and checked digest, not the D3 hardware.

The prediction registered before mapping was unchanged throughput and essentially unchanged logical area: the decoder's production change replaces a constant indexed read with `[Phi0 | _]`. Both mapping seeds return exactly the parent branch's measured resources and ABC9 delay estimate. This measures the maintained decoder workload; arbitrary new guarded helper clauses can introduce the comparisons and selections their behavior requires.

## Behavior and throughput

The D3 decoder uses three scheduler shards per plane, two pipeline stages, II=1, and no debug instrumentation. Both versions complete through step 32 at **180 cycles/step** with request-paced sinks and **182.583333 cycles/step** with variable sink readiness. Public outputs match cycle by cycle across a 12,000-cycle comparison with long stalls and reset: 635 X frames, 626 Z frames, and identical stalled-cycle counts (X=1,452; Z=1,708).

The wrapper and RAM implementation are byte-identical. The generated decoder RTL differs, so resource equality is measured rather than inferred from byte identity. The existing source-fragment reduction placement is preserved; the production edit is in the phi-halo entry, outside its contribution capture prefix.

## Matched XC7 mapping

Both variants use the same native XLS tools, standard library, scheduling options, RAM configuration, and Yosys tool files. After flattening and optimization, each core is renamed with seed 1 or 2 and mapped with `synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf`. All mappings pass `check -assert` and `scc -expect 0`. The parent samples are reused only after revalidating their exact input, script, tool, and output fingerprints; two fresh candidate mappings were run.

| Metric | Version | Best | Mean | Population variance | Worst |
| --- | --- | ---: | ---: | ---: | ---: |
| Core LUTs | Both | 125,330 | 125,485.5 | 24,180.25 | 125,641 |
| Flip-flops | Both | 83,640 | 83,640 | 0 | 83,640 |
| CARRY4 | Both | 2,438 | 2,438.5 | 0.25 | 2,439 |
| ABC9 delay (ps) | Both | 16,874 | 16,874 | 0 | 16,874 |

Seed 1 uses 125,641 LUTs and 2,438 CARRY4; seed 2 uses 125,330 LUTs and 2,439 CARRY4, in both versions. Every sample has zero LUT RAM, 104 RAMB18, 16 RAMB36, and 144 DSPs, with zero variance. Two naming seeds are a screening measurement, not a confidence interval. ABC9 delay is a mapping-stage estimate, not a routed timing result or validated maximum clock. No new placement/routing or power run was performed.

The last placed-and-routed design remains [PR #102](d3-arbitration-2026-09-14.md): 118,906 LUTs, 81,058 flip-flops, 104 RAMB18, 16 RAMB36, and 144 DSPs in its unrenamed core mapping. Its partial-path frequency estimates were 14.46, 11.89, and 12.62 MHz (best 14.46, mean 12.99, population variance 1.1693 MHz², worst 11.89). Subsequent reduction-failure changes altered the design before #107; that historical route is not a timing measurement of this branch. Missing BRAM timing and approximate device/register/DSP models still prevent those estimates from establishing a complete-design clock limit.

## Validation and reproduction

The compiler change passes 900 EUnit tests; 32 BEAM-derived pattern/helper cases over 3,456 interpreter/JIT and RTL inputs; 1,920 existing helper vectors and all-input inline/factored equivalence; and 708 control-failure vectors at each of three pipeline schedules. Public queries inspect 19 shared actors at two schedules, including included-file pattern and helper-head failure origins, backpressure recovery, and instrumentation noninterference. The native generated-RTL and host-bridge regression passes. The [Linux implementation run](https://github.com/ecpeterson/erl_hls/actions/runs/34967560822) passes every behavioral step and complete D3 debug integration; its sole failure is the old phi-halo digest, refreshed from its tested artifacts.

The D1 testbench's state RAM widths are corrected to 449/540/449 bits. It passes against native and Linux-generated RTL without width warnings. A deliberate 434-bit data-RAM override fails its new port-width assertion at time zero. Optional RAM logging prints raw words instead of decoding obsolete field offsets.

Run `bash tools/test_patterns.sh "$xls"`, `bash tools/test_helpers.sh "$xls"`, `bash tools/test_control_failures.sh "$xls"`, and `bash tools/test_actor_debug.sh "$xls"`. For D3, use `ERL_HLS_PHI_PROFILE_TRACE=0 bash tools/run_phi_decoder_profile.sh "$stage" "$xls"`; run `experiments/07-openxc7/phi_timing.py` with `--phase simulate` and `--phase compare --reference BASELINE_RTL`. Compare mapping with `measure_phi_mapping.py BASELINE_RTL CANDIDATE_RTL --stage AREA_STAGE --seeds 1 2 --jobs 2`. The native cold D3 compile took 120.0 seconds converting, 295.1 optimizing, and 170.9 generating RTL, with maximum recorded RSS about 485 MiB. Other tests ran concurrently, so these are provenance data, not a compiler-speed benchmark.
