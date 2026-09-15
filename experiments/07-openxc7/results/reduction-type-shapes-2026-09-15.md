# Source type shapes: reduction placement and D3 validation

This compares PR #108 (`5697453d8ae4be8a3de9e7ef6b1280de3d2350c9`) with `codex/reduction-type-shapes`. The [machine-readable report](reduction-type-shapes-2026-09-15.json) records compiler inputs, tool and RTL fingerprints, individual mapping samples, source-analysis samples, and verification log hashes. All 42 generated DSLX inputs and the wrapper from the final implementation are byte-identical to the measured build.

The registered prediction was unchanged area and throughput: replacing two constant indexed reads with `[Phi0, Phi1]` should produce the same element wiring, and source-shape assertions are evaluated at compile time. Throughput is unchanged. Mapping shows a small resource shift: mean LUTs fall 0.29%, flip-flops fall by 12, and mean ABC9 delay rises 0.35%. With two naming seeds, this is a screening measurement, not evidence of a general area or timing improvement.

## Source and hardware contract

The decoder's guardless contribution head destructures `values :: phi_field:field()`. Source analysis follows its `-type` aliases to a two-element vector without executing or loading its provider. An exact `[Phi0, Phi1]` head is total for that shape. Each dimension used by the proof becomes a DSLX constant assertion against the actual message type; a provider whose emitted length disagrees cannot compile the source-fragment contribution function. Ordinary variable fields do not require reading their providers' source.

Source-only and clean compiled interfaces agree in both checkouts. Their resulting reduction plans retain the same two source-fragment planes, and the public interface facts match after excluding `failure_origins`: removing the two indexed reads removes two candidate failure sites and renumbers later codes. Separate tests cover stale provider BEAMs, changed type headers, macro contexts, changed working directories, `compile:forms`, deterministic builds, nested and parameterized aliases, missing and recursive aliases, and partial patterns. A changed routing fact invalidates the embedded actor interface. Single-level and nested source/DSLX dimension mismatches fail their constant assertions.

## Behavior and throughput

The D3 profile uses three scheduler shards per plane, two pipeline stages, II=1, and no debug instrumentation. Both revisions reach step 32 at **180 cycles/step** with request-paced sinks and **182.583333 cycles/step** with variable sink readiness. A 12,000-cycle comparison including long stalls and reset matches public outputs cycle by cycle: 635 X frames, 626 Z frames, and identical stalled-cycle counts (X=1,452; Z=1,708).

The generated decoder RTL differs; the wrapper and RAM implementation are byte-identical. The shape proof and assertions do not change wire formats or reserve additional runtime state.

## Matched XC7 mapping

Both variants use the same native XLS tools, standard library, scheduling options, RAM configuration, and Yosys files. The flattened core is renamed with seed 1 or 2 and mapped using `synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf`. Every mapping passes `check -assert` and `scc -expect 0`. The #108 measurements are reused only after revalidating their exact input, script, tool, and output fingerprints; two fresh candidate mappings were run.

| Metric | Version | Best | Mean | Population variance | Worst |
| --- | --- | ---: | ---: | ---: | ---: |
| Core LUTs | #108 | 125,330 | 125,485.5 | 24,180.25 | 125,641 |
| Core LUTs | Candidate | 124,843 | 125,117 | 75,076 | 125,391 |
| Flip-flops | #108 | 83,640 | 83,640 | 0 | 83,640 |
| Flip-flops | Candidate | 83,628 | 83,628 | 0 | 83,628 |
| CARRY4 | #108 | 2,438 | 2,438.5 | 0.25 | 2,439 |
| CARRY4 | Candidate | 2,440 | 2,444 | 16 | 2,448 |
| ABC9 delay (ps) | #108 | 16,874 | 16,874 | 0 | 16,874 |
| ABC9 delay (ps) | Candidate | 16,874 | 16,933.5 | 3,540.25 | 16,993 |

Every sample has zero LUT RAM, 104 RAMB18, 16 RAMB36, and 144 DSPs, with zero variance. Seed 1 changes LUTs by −250 and delay by 0 ps; seed 2 changes LUTs by −487 and delay by +119 ps. These seeds describe mapping sensitivity, not a confidence interval. ABC9 delay is a mapping estimate, not routed timing or a validated maximum clock. No new place-and-route or power run was performed.

The last placed-and-routed design remains [PR #102](d3-arbitration-2026-09-14.md): 118,906 LUTs, 81,058 flip-flops, 104 RAMB18, 16 RAMB36, and 144 DSPs in its unrenamed core mapping. Its partial-path frequency estimates were 14.46, 11.89, and 12.62 MHz (best 14.46, mean 12.99, population variance 1.1693 MHz², worst 11.89). Subsequent changes predate this PR and altered that design; these historical routes do not measure this branch. Missing BRAM timing and approximate device/register/DSP models prevent those estimates from establishing a complete-design clock limit.

## Source-analysis cost

Seven warmed samples of `phi_noise_topology_dslx:scheduler_plan({phi_shards, 3})`, measured sequentially after mapping completed, give:

| Version | Source reads | Best (ms) | Mean (ms) | Population variance (ms²) | Worst (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| #108 | 6 | 22.890 | 23.167 | 0.02327 | 23.325 |
| Candidate | 8 | 25.153 | 26.081 | 0.78963 | 27.729 |

The two additional reads resolve `phi_field` once in each interface-analysis pass. Reads remain bounded by distinct source dependencies rather than actor count. These local timings describe this probe, not a controlled compiler-speed benchmark; other verification work was running. Full workload samples are retained in the JSON report.

## Validation and reproduction

Native validation passes 926 EUnit tests, 3,456 existing bounded-pattern interpreter/JIT and RTL vectors, 256 BEAM-derived ordinary/aggregate reduction vectors, 20 existing reduction DSLX/JIT tests and their compile targets, and macro-configured source-context tests. Public debug queries inspect 19 actors at two pipeline schedules, find an external stall, observe recovery after release, and pass structural and cycle-by-cycle instrumentation noninterference. [Linux CI](https://github.com/ecpeterson/erl_hls/actions/runs/34974027027) passes all behavioral checks, including generated RTL, the host bridge, and complete D3 debug integration; its sole failure is the previous phi-halo RTL digest, refreshed from its tested artifacts.

Run `bash tools/test_type_shapes.sh "$xls"`, `bash tools/test_patterns.sh "$xls"`, `bash tools/test_reduction_dslx.sh "$xls"`, and `bash tools/test_actor_debug.sh "$xls"`. For D3, use `ERL_HLS_PHI_PROFILE_TRACE=0 bash tools/run_phi_decoder_profile.sh "$stage" "$xls"`; run `experiments/07-openxc7/phi_timing.py` with `--phase simulate` and `--phase compare --reference BASELINE_RTL`. Compare mapping with `measure_phi_mapping.py BASELINE_RTL CANDIDATE_RTL --stage AREA_STAGE --seeds 1 2 --jobs 2`. Run `escript tools/profile_interfaces.escript CHECKOUT OUTPUT.json` against each prepared checkout for source-analysis samples. The native cold D3 compile took 114.1 seconds converting, 281.3 optimizing, and 170.1 generating RTL, with maximum recorded RSS about 531 MiB.
