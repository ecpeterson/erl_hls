# XC7 LUT placement and function checks

**The patched four-cell decoder routes in 17.8 minutes with zero placement repairs and a 16.52 MHz partial-path estimate.** Matched native placement reduces occupied physical LUTs by 5.1%. The regression also reproduces a known upstream truth-table bug missing from our pinned release.

The experiment uses the unchanged `68aeeb39` source and a candidate with two isolated patches, built with the same Apple Clang 21, CMake 4.3.1, Boost 1.90.0 and Eigen 3.4.0 settings. The installed toolchain is unchanged. Our source pin dates to August 18, despite the package's August 20 release label. The [JSON evidence](lut-legality-2026-09-21.json) records source/tool hashes and every reported attempt.

## Small regressions

Each row uses one mapped netlist and seed 1 on `xc7z030sbg485-1`. All 16 routes complete. Every candidate passes the physical truth-table checker; the unchanged baseline is required to fail the tied-input function check. These are deterministic regression observations, not a routing-speed benchmark.

| Fixture | Packed LUT cells | Baseline repairs | Candidate repairs |
| --- | ---: | ---: | ---: |
| LUT5 + registers | 100 | 65 | 1 |
| LUT6 + registers | 100 | 2 | 2 |
| Dual-output LUTs | 188 | 20 | 0 |
| Carry chain + LUT5 | 170 | 83 | 0 |
| Distributed RAM + logic | 188 | 19 | 0 |
| Shift registers + logic | 100 | 2 | 2 |
| Fixed O5/O6 pair | 5 | 1 | 0 |
| Fixed pair with tied-high inputs | 5 | 1 | 0 |

The first fix accepts the packer's provisional `O6` output name on a legal O5 placement, matching the tile check and later output rename. In the LUT5 fixture, 64 LUTs stay in O5 slots instead of being relocated to O6 slots. True six-input logic retains its placement restrictions; its completed FASM is unchanged in the LUT6 fixture. The residual repairs are preserved, not disabled globally.

The second fix repairs input-origin joining. In the tied-high fixture, a `LUT5` with INIT `0x6789ef01` and all inputs high should output zero; the old FASM makes it output one. Removing both BEL constraints still reproduces the wrong function. Applying only the placement fix also retains the failure, isolating the second patch's effect.

This is a rediscovered version-specific bug, not an unreported upstream discovery. Upstream [2d3005e](https://github.com/openXC7/nextpnr-xilinx/commit/2d3005e755a2b1009f434efdb5acf2103ffe4d92) corrects the separator and describes hardware failures; [7cfd1e9](https://github.com/openXC7/nextpnr-xilinx/commit/7cfd1e90682370accd00f63fcf7c16c5bcd24007) hardens the FASM reader against unknown names. Our local adaptation also skips empty origins. The placement restriction remains in inspected upstream `4524cbd`; it needs reproduction on that revision before an upstream submission.

The candidate checks enumerate **28,672 reachable combinational truth-table rows**, using packed logical net identities as the oracle and emitted FASM INIT bits as the result. They also check shared physical inputs, fixed BEL retention and SLICEM placement. RAM/SRL checks cover connectivity and parameters, **not sequential memory behavior or memory INIT encoding**. Two missing memory constant-pin annotations are accepted only after checking the unchanged physical constant connection.

## Decoder comparison

The unchanged four-cell netlist, constraints and chip database are reused from [September 20](z7030-decoder-2026-09-20.md), application revision `3724231`. Both new native builds use seed 1 at a 100 MHz requested clock with router2. Their analytical-placement wire lengths agree before repair. The baseline stops after placement; the candidate has a one-hour total budget. No second candidate seed or new D3 route is requested.

| Matched native build | Post-placement repairs | Occupied physical LUTs | O5 / O6 cells | Outcome |
| --- | ---: | ---: | ---: | --- |
| Baseline | 9,616 | 35,572 | 3,608 / 35,572 | Placement completed in 10.9 min; routing not requested |
| Candidate | 0 | 33,748 | 13,224 / 25,956 | Route completed in 17.8 min |

Both contain 39,180 packed LUT cells. Occupancy counts distinct `(slice, LUT letter)` pairs, so a shared O5/O6 pair counts once. Exactly 9,616 LUT cells change location. The candidate uses 1,824 fewer physical LUTs (5.1%) without changing the mapped logic. Its analytical placement takes 542.14 s, refinement 90.56 s and routing 414.07 s.

The candidate's **1,859,552 reachable combinational LUT rows pass** against the emitted FASM. Two carry helpers lose ground-input annotations; their physical ground connections and complete truth tables remain correct. All other original LUT port identities agree. This is additional physical-function evidence beyond the earlier RTL/BEAM checks.

One completed seed gives mean/best/worst **16.52 MHz** and population variance **0 MHz²**; one seed does not estimate seed sensitivity. The 100 MHz requested target is not met. The critical path has **3.9 ns logic and 56.6 ns routing**, passing through executor results, scheduler egress, reduction batching and selection. The detailed path is in the JSON.

The earlier packaged-tool attempts relocated 9,503/9,536 clusters or cells and exhausted their one-hour budgets with 1,147/9,255 overused wires. They are historical context: their compiler/dependency build differs from these matched native binaries. Since the native baseline was not routed, this is not a controlled measurement of routing speedup. The last routed D3 result on Z-7100 remains best 14.46, mean 12.99, variance 1.1693 MHz² and worst 11.89 over three seeds. Its population, device and application revision differ, so the new 16.52 MHz result is not a matched improvement over it. The current D3 capacity bound remains at least 86,783 physical LUTs, above Z-7030 capacity; changing the output-name gate does not relax the sharing rules behind that bound.

No RTL or synthesis mapping changes are made, so the four-cell core remains **33,818 LUT primitives**, with 29,477 FFs, 902 CARRY4s, 48 DSP48E1s, 44 RAMB18s and eight RAMB36s. Placement can change packing and wiring, but this experiment makes no core-area reduction claim.

The completed route yields only the backend's partial timing estimate: BRAM sequential timing is omitted, combinational DSP timing is coarse, FF checks use fixed 0.1 ns values, and speed-grade timing is uncalibrated. Earlier utilization/timing logs remain measurements of those tool outputs; they were not proofs of emitted-bitstream correctness. No previous board image is retroactively certified by these LUT fixtures.

## Validation and reproduction

The native baseline and candidate builds pass CTest. All 21 portable timing/checker regressions pass, including real mapping/assembly and ten checker tests that reject corrupted INIT bits, wiring and constraints. The 19 source-contract tests pass with no new audit gaps; Dialyzer succeeds.

Use the [isolated build and fixture commands](../lut_legality/README.md). Full artifacts are retained under `experiments/07-openxc7/build/lut-legality-20260921/` in the saved checkout. The patches are review material for the experiment; no upstream PR or board programming is performed.
