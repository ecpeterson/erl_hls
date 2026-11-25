# Vivado and openXC7 viewer coverage

The repetition N2 decoder can now be inspected in both viewers at the same write, bit and clock. Both publications support placement, within-clock arrival, data/enable/reset cones, exact sink selection, timing colors, path neighborhoods and an independently identified static setup path. The XC7 publication traces 97.80% of the step-4 branches. Both publications include selected-operand ancestry, a latency profile, a whole-device regional map and ranked setup paths. Their placement coverage, timing models and target devices differ.

## Matched application witness

The six-actor run uses the same six archived RTL inputs and retained stimulus. The XC7 compile-only wrapper exposes both streams, status and all six fault flags on 100 pins. A three-bit selector exposes each actor’s 16-bit failure word in the same interval. Only the clock has a fixed board pin. Verilator matched every public trace field and all 592 taps in the enriched producer recording (18,335 tap bits per cycle) over 2,369 cycles. The join checks the replay receipt, original logical recording, ordered synthesis inputs and the new implementation identity. This finite simulation witness supports reusing the logical events for that stimulus. Each backend supplies its own physical bindings.

The interval starts after completion C(3) at cycle 1774 and ends at C(4) at cycle 1873. The two recordings agree on the identities, cycles, resources, addresses and masks of all 468 writes to 51 words. Both recordings contain 7,637 writes overall. Both enriched recordings contain the same 61,764 logical events and 151,134 versions. The initial 581-tap XC7 replay contained 16,321 events. The retained Vivado implementation targets XCZU7EV and the local XC7 route targets XC7Z030-1. Their delay values describe their respective placements and models.

| Step-4 population | Vivado | openXC7 |
| --- | ---: | ---: |
| Mapped target-bit occurrences / 92,745 requested | 72,259 | 90,797 |
| Distinct mapped destination bits / 8,466 requested | 6,108 | 8,059 |
| Writes fully / partially / wholly unmapped | 263 / 205 / 0 | 331 / 137 / 0 |
| Registered data cones with known / unknown bound | 468 / 0 | 468 / 0 |
| Enable cones | 270 known, 198 outside registered scope | 202 known, 266 without a mapped enable pin |
| Reset cones | 468 outside registered scope | 468 outside registered scope |
| Distinct required net branches | 75,541 | 109,591 |
| Branch geometry | 44,493 resolved, 8,576 intrasite, 15,491 partial, 383 ambiguous, 6,598 unavailable | 107,182 resolved, 2,409 disconnected constant branches |
| Unique arc delays in these cones | 68,879 logic and 68,943 net known, 6,598 net missing | 98,462 logic and 109,591 net known |

Geometry and delay have separate denominators. Across the raw XC7 capture, nextpnr reported 53,366 routed sink delays, 71,773 predicted and 3,934 unavailable. It also returned 31,697 empty cell-delay queries, including structurally inapplicable pin pairs. Within the selected cones every admitted arc had a delay. In the original capture one inserted LUT buffer blocked 58 write bounds across two data cones. The packer now records its actual input net, driver pin and new output net before rewiring. For this LUT the source is a native ground driver. The packed LUT1 retains identity INIT, has no physical input mapped to I0, drives the recorded output and selects its LUT6 half with tied-high A6. The configured half repeats INIT[0], so the viewer can stop at its constant output. This check qualified one LUT among 5,310 inserted buffers in the focused export. Of the 407 unqualified destination bits, 364 lacked a nonconstant synthesis driver and 43 failed the packed FDRE qualification.

## What closed the gap

- **Storage and primitive boundaries.** The original 177-pin top exceeded the package limit and unscoped provenance exhausted the 100,000-object allowance. A four-bit pilot on the new wrapper located two distinct bits, or 28 target occurrences in step 4. With identical four-bit demand, the qualified pilot located all four bits, covered 114 target occurrences and produced known data bounds for 57 writes. The all-word capture then expanded the denominator. Applying the former primitive stops to the final graph, 3,661 distinct D bits reached CARRY4, 3,528 reached a dedicated mux and 7,956 reached an external input. The corresponding enable counts were 1,986, 1,642 and 2,636. The populations overlap. All 8,059 mapped resets reach an external input. The adapter now qualifies legal CARRY4 and MUXF7/F8 dependencies and distinguishes external launches. It verifies the constant-high slice-local enable on 5,423 mapped bits even where packing removes its wire. Unknown power-up values stay unknown.
- **Selected correction.** At cycle 1852, write `e/25066` targets `register/____state_154`. Vivado mapped 409 of 537 D bits and XC7 mapped 528. All 528 have finite registered arrivals. Bit 202 has the longest of those known bounds, 38.646 ns over 71 arcs. All 36 demanded net branches resolve on the frozen checkpoint. The chip database identifies the input permutation on 16 of them. Headless Chrome selected bit 202 in both published arrival views. Vivado showed 5.223 ns over 45 arcs. Both viewers opened the path neighborhood at that write. The openXC7 viewer omits missing route spans and keeps their delay in the ordered path.
- **Static timing.** Vivado supplies independent fast/slow SDF data plus a saved STA report. XC7 supplies one backend structural estimate and the ordered native setup report in integer ps. At the 5 ns request, the worst eligible same-clock, same-edge native check runs from `$auto$ff.cc:337:slice$40546/Q` to `$auto$ff.cc:337:slice$42155/D`. Its 53.623 ns data path plus 0.100 ns setup gives −48.723 ns slack. All 69 branches on that check resolve, including 22 with permuted LUT inputs. Ranking the 11,671 eligible capture pins by slack gives 50 retained checks from −48.723 to −46.944 ns. All 3,522 net-branch occurrences resolve across those checks. The archived Vivado report gives 8.808 ns data and −3.997 ns slack on its own path. The viewer qualifies requirements and slack only for checks supported by the backend evidence.
- **Primitive timing witnesses.** An independent enumeration of 15 register-launched chains on the reconvergent fixture matched the backend’s ordered maximum of 2,935 ps and slack of 7,065 ps. Its four selected branches reach the exact native BEL wires. Ten connected carry DI pairs matched the placed-site Project X-Ray variant envelope within 1 ps. Reproducing the four-Phi scheduler’s RAMB36E1 SDP72 READ_FIRST mode, all 32 connected output bits launched at the calibrated 2,080 ps without the output register or 748 ps with it. Both native worst paths crossed from RAM into arithmetic. WRITE_FIRST left all 212 connected ports unqualified. The inferred-memory simulation ran 672 cycles, including read/write collisions. N2 itself contains no BRAM, SRL or DSP. The separate [four-Phi application witness](#four-phi-scheduler-state) follows one RAM output into a multiply on the same part. [BRAM behavior and board witness](../../platforms/xc7/docs/bram-sdp72.md)

## Logical and regional coverage

The 592-tap replay supplies 19,228 selected-operand reads, 19,228 selected values, 6,929 register computations and ten public completion boundaries. The step-4 completion links to two accepted transfers at C1873. The replay join checks the producer bundle digest, every RTL input and the exact trace. The latency profile checks the entire logical graph before binding its 1,186 groups and 3,359 source obligations to the new recording. Its five choices describe fixed-work schedule changes with partial dependency evidence.

The XC7 regional map bins 36,269 placed cells, 542,316 installed switches and 1,381,401 tile-wire memberships into 182 occupied 16×16-tile regions. The census includes all 39,811 packed nets, including 2,012 with no bound routing resource. Verification reconciles every fixed switch and its owner and independently compares the per-bin wire counts for all 237 nets in the selected export. Installed counts measure use. Capacity and congestion require other evidence.

## Frozen interval routing

The original 74-net capture resolved 376 of its 988 step-4 branches. For a permuted LUT input, the exporter now checks the placed LUT half, packed net bit and physical input against the chip database’s permutation switch on that net. Its router-side wire must be reachable from the recorded driver. This recovers the other 612 selected branches. The saved physical BEL wire and router-side endpoint remain separately inspectable.

The interval publisher derives its demand from all 468 writes and their cones. It reconciles the named checkpoint wires with the numeric fixed PIPs for 35,629 nets. Of the 109,591 distinct branches, 50,333 attach directly and 56,849 use a qualified input permutation. The other 2,409 stop at 172 local constant wires. The saved tree omits the connection from the global driver to these ties for 2,176 ground and 233 supply branches. Each record names its local cut. Independent traversal checked every branch, and all 988 overlapping branches in the original selected-net export agreed on the ordered PIPs and constituent tile wires.

The larger ranked-path export independently agrees on 1,919 overlapping branches. The tables store each of 497,856 nodes and 462,229 switches once. A focused sink fetches the shards for its path. In the headless browser witness, opening the recording fetched zero geometry shards. Selecting the initially displayed sink then filled all 74 previously missing branches on its 51.924 ns path. Arc 190170 exercised a further 19-switch branch outside the original net request. The arrival view draws connectivity between occupied switch tiles. Site spans and intermediate heights are schematic. [Interval evidence](../../yap/hls_spacetime/g44-geometry.json)

## Reproduce and inspect

From the umbrella root, use the local process guard from the retained N2 archive, a fresh output directory per run, 1,200 seconds and 6 GiB process-group RSS. Set `ARCHIVE` to `hls_artifacts/runs/spacetime-2026-11-06`, `APIO` to the installed Apio home, `CHIPDB` to the matching Z-7030 package database and `TIMING_TOOLS` to a fresh build directory. The Vivado publication is `runs/spacetime-2026-11-08/published-gallery/viewer-data.tar.gz` in the project archive. The [native workflow](native.md) lists the prerequisites.

```sh
SPACETIME_CARRY_MODEL=1 SPACETIME_BRAM_MODEL=1 \
  bash platforms/xc7/timing_coverage/build_spacetime.sh "$TIMING_TOOLS" "$ARCHIVE_CACHE"
rebar3 as spacetime escriptize
witness=apps/hls_spacetime/test/native/openxc7/repetition
python3 "$ARCHIVE/case-1/local-guard.py" first-guard 1200 \
  python3 "$witness/capture.py" "$ARCHIVE" "$APIO" "$CHIPDB" "$TIMING_TOOLS" first --all-words
node "$witness/demand.mjs" first/prepared > demand.json
python3 "$ARCHIVE/case-1/local-guard.py" repeat-guard 1200 \
  python3 "$witness/capture.py" "$ARCHIVE" "$APIO" "$CHIPDB" "$TIMING_TOOLS" repeat --all-words --demand demand.json
node "$witness/compare.mjs" "$VIVADO_GALLERY" first/prepared repeat/prepared
node "$witness/demand.mjs" repeat/prepared
node "$witness/verify-geometry.mjs" repeat/prepared repeat/native
npm --prefix apps/hls_spacetime start -- --data "$PWD/repeat/prepared"
```

For the enriched recording, pass `--ancestry --profile "$PROFILE"` to the second all-word capture. Set `PROFILE` to the archived `runs/spacetime-2026-11-08/candidate-prediction-1/source-profile-2.json`. Compare its prepared publication with the Vivado gallery using the same commands, then run `node "$witness/verify-coverage.mjs" repeat/prepared repeat/native` to verify the complete switch census, selected wire footprints, ranked timing branches and logical sidecars. The [coverage ledger](../../yap/hls_spacetime/g44-coverage.json) identifies the enriched publication.

For the primitive checks run `check_probes.py APIO CHIPDB TIMING_TOOLS TIMINGS CALIBRATION FRESH_OUTPUT` under the same guard. `TIMINGS` is the Project X-Ray `zynq7/timings` directory. `CALIBRATION` is the archived `experiments/07-openxc7/results/xc7-timing-model-2026-09-25.json`. The [compact evidence ledger](../../yap/hls_spacetime/g44-repetition.json) identifies both publications, the pilot, the native checkpoint, the timing probes and the saved selections. The project artifact archive contains the portable viewer, native capture and validation evidence under `runs/spacetime-g4-parity-2026-11-24/g44-repetition/`.

The enriched viewer is `runs/spacetime-g4-parity-2026-11-24/g44-coverage/prepared.tar.gz` in the project artifact archive. Extract it into an empty directory and serve that directory with the viewer. The sibling native and reproduction archives retain the new observer export, joined recording, metadata, replay receipt and source profile.

To inspect the earlier frozen result directly, extract `runs/spacetime-g4-parity-2026-11-24/g44-geometry/prepared.tar.gz` into an empty directory and serve it with the viewer. To reproduce it offline, extract the sibling `reproduction.tar.gz` and the preceding `g44-repetition/native.tar.gz` in one directory, then follow the [frozen capture commands](native.md#publish-interval-geometry-from-a-frozen-openxc7-capture). The [geometry ledger](../../yap/hls_spacetime/g44-geometry.json) records the artifact hashes.

## Four-Phi scheduler state

The closed 2×1-per-plane Phi workload provides a matched hard-block witness on `xc7z030sbg485-1`. Both implementations take the same two-pin harness and decoder RTL, a 20 ns internal clock target, Y14 clock and V13 activity pins. The [Vivado reference](../../platforms/xc7/docs/vivado-reference.md) supplies the routed checkpoint and reports. Only internal paths are compared. Vivado also constrains its activity output delay.

The passive Icarus monitor samples the 540-bit scheduler state RAM and one executor multiply for 4,096 edges. It checks enabled writes against both stored rows, the read-first output against the previous contents, and each accepted product against its 38-bit operands. The replay checked 1,325 writes, 1,321 reads and 1,320 accepted multiplies, including 1,262 changes from the preceding accepted operand. It observed zero same-address collisions. Address 0 was written at C32 and read at C36. Bit 84 changed, and the next request contained the entire written word. At C37 the rounded operand was `0x24004` and the sliced result register captured `0x3000`. Open **Scheduler state write and readback** for the address, mask, value and response edge. **Accepted multiply and DSP stages** shows the operand, product and the placed DSP pipeline settings. The event inspector lists the primitive pins in path order. The flat chip connects their reported sites schematically. Clock coincidence and a static path do not establish gate-level sensitization.

To reproduce, build the Spacetime profile, then run the witness under the serial 6 GiB process-group guard. Supply the September 21 `erl-hls-vivado-evidence-20260921.tar.gz` from the artifact archive, the SDP72-qualified Yosys executable, the G4 Spacetime nextpnr binary with its build receipt, the Z-7030 package chipdb and fresh directories. Capture verifies the archived reference SHA-256 before extraction. The default capture stops after placement. Pass `--native-stage routed` to attempt a full route with the same seed and 50 MHz target. The one-hour route attempt reached its time limit with 2,120 overused wires in the last completed iteration. The scoped publication admits one path per backend, at most 512 steps per path, 512 MiB for the native checkpoint and 16 MiB for the two viewer documents together.

```sh
rebar3 as spacetime compile
witness=apps/hls_spacetime/test/native/four_phi
python3 "$witness/capture.py" "$REFERENCE_ARCHIVE" "$YOSYS" "$NEXTPNR_SPACETIME" "$CHIPDB" "$RUN"
python3 "$witness/publish.py" "$RUN" "$CHIPDB" "$GALLERY"
npm --prefix apps/hls_spacetime start -- --data "$GALLERY"
```

The following measurements describe the original C32–C37 capture with stock Apio synthesis. The full replay below uses a corrected native checkpoint. The [four-Phi ledger](../../yap/hls_spacetime/g44-four-phi.json) identifies the portable gallery in `runs/spacetime-g4-parity-2026-11-24/four-phi/`. Its two recordings share four events and three versions. Each has a separate checkpoint and pin bindings.

| Measurement | Vivado | openXC7 |
| --- | --- | --- |
| Scheduler bit 84 | `RAMB36_X0Y9/DOADO[12]`, SDP72 | `RAMB18_X1Y30/DOADO11`, SDP36 |
| Path into the multiply | 27 primitive visits in the slow setup report. The DSP at X0Y18 drives X0Y19 over cascade bit 47. | 10 placed cells ending at `DSP48_X1Y26/A11`. The two placement checksums match those from the timed-out route attempt. |
| Identified DSP partial products | 5 | 6 |
| Timing | The complete reported setup path has 19.263 ns data delay and +0.462 ns slack. | Selected branch delay and routing geometry remain unmeasured. |

Both memories use READ_FIRST with their optional output register bypassed. All identified partial products bypass AREG, BREG, MREG and PREG. Across the entire implementation Vivado enables PREG on 18 other DSPs and Yosys enables it on none. N2 remains the witness for broader route and register coverage.

## Whole four-Phi execution

The paired gallery opens on the first accepted public frames at C105. Scrub from C0 to C4095 or jump to a frame. **Window** selects one clock, a short history, or the union over the entire replay. Both maps count distinct primitives with a known change between successive settled output samples. Click a tile for measured instance names and types. Zoom both maps around that tile to inspect its neighbors. Unknown comparisons have a separate count and can coexist with a known change on another output. C0 initializes the observer.

The source timeline covers 21 generated processes, 42 FIFOs, eight scheduler RAMs and the X/Z output interface. It records 238 handshakes, enables and public probes before the active edge, plus addresses and accepted 128-bit frames. An interface can appear at both ends of a transfer. **Only selected instance** uses retained synthesis hierarchy, unambiguous named output nets and checked public capture registers. Shared or unnamed logic remains in the whole-design view. The physical maps are functional simulations of each technology netlist on its own placement. The openXC7 checkpoint ends at placement. The 3D view below adds Vivado static timing to the sampled activity.

The opening comparison covers 70,418 Vivado primitives and 65,381 openXC7 primitives. Each simulated primitive has a location on its own implementation. Over the full replay 19,800 Vivado primitives and 18,545 openXC7 primitives changed output. At C32 alone the counts were 2,702 and 2,252. Source RTL accepted 86 X and 86 Z status frames between C105 and C4017, with steps 0 through 42 for both coordinates on each plane. This input emitted zero correction frames. The public activity pin, initialized capture register lanes and six handshake-related register lanes per backend are checked at each edge. The design retains 99 physical payload lanes per plane in Vivado and 103 logical payload lanes backed by 102 distinct registers per plane in Yosys. The corrected C32 drill-down follows ten placed cells from `RAMB18_X2Y32/DOADO11` to `DSP48_X2Y56/A7`.

The November 24 G4 exporter selected the stock Apio installation. Its August 19 package bundles a March 24 Yosys release. The earlier repetition N2 netlist inferred no block RAM. The small SDP72 timing probes directly instantiate RAMB36E1 with both parity inputs tied low. Neither exercised inferred SDP72 data mapping. The earlier TE0715 work retained a separate SDP72-corrected copy. Both use the same Yosys executable. G4 originally chose the stock mapping library, which duplicates the lower parity inputs. In the four-Phi simulation, scheduler 0’s first bad mailbox read at C12 returned `0x80000080de1769b906000003` for `0x800000009e3779b906000003`. Resolving unspecified startup bits alone reproduced the failure. The four-Phi capture now runs the board library audit, verifies which map synthesis opened and records its digest. [Board qualification and guards](../../platforms/xc7/docs/bram-sdp72.md) · [Original board PR](https://github.com/ecpeterson/hls_fabric/pull/75)

The [workload evidence ledger](../../yap/hls_spacetime/g44-four-phi-workload.json) identifies the paired gallery and its raw observations in `hls_artifacts/runs/spacetime-g4-parity-2026-11-24/four-phi-workload/`. To open the retained view from the umbrella root:

```sh
node apps/hls_spacetime/scripts/serve.mjs --data ../hls_artifacts/runs/spacetime-g4-parity-2026-11-24/four-phi-workload/gallery
```

For a fresh run, take `yosys-0.63-sdp72/libexec/yosys` from the retired Fabric `board-tools.tar.zst` and run the preceding capture and transaction publication with it. Use its complete package directory so Yosys finds its own technology maps and ABC. The corrected library SHA-256 begins `a1afcda1610f`. Use absolute paths for all input and output directories in the commands below. Supply JDK 21, the RapidWright 2026.1.2 standalone JAR, the Xilinx UNISIM library at `1c8e05fd1e9a79ceb8b996a0996674122eed086f` and the serial process-group guard. RapidWright reads physical locations from the archived Vivado DCP using readable EDIF translated from its matching structural Verilog. For an offline replay, set `RAPIDWRIGHT_PATH` to the `rw/` directory retained with the observations. The reader checks the part, device and primitive database digests.

```sh
workload=apps/hls_spacetime/test/native/four_phi/workload
python3 "$workload/sdp72.py" "$YOSYS" "$UNISIM/verilog/src" "$LANE_PROBE"
python3 "$workload/measure.py" "$RUN" "$WORK" "$UNISIM/verilog/src" "$RAPIDWRIGHT_JAR" "$GUARD" "$YOSYS"
python3 "$workload/pack.py" "$RUN" "$WORK" "$CHIPDB" "$GALLERY" "$PAIRED"
npm --prefix apps/hls_spacetime start -- --data "$PAIRED"
```

### Within-clock signal flow

Choose **3D signal flow** in the paired gallery. Opening `workload.html?view=flow&cycle=32` selects a busy clock. Drag either scene to orbit both, scroll to zoom and click a line for its endpoints. **Both primitives changing** selects connections between cells with known output changes at that clock. **Changing driver** also includes fanout to cells whose outputs stayed stable. The simulation observes settled primitive outputs. Pin-specific transitions, glitches and actual subcycle event times are unobserved.

Vivado height uses maximum SDF arc delays, accumulated from a local launch clock pin through each reachable input and output. Bus-wide arcs expand over connected lanes. A net rises by its own interconnect delay. Switch-tile heights interpolate that delay along the retained directed branch. Of 273,350 non-launch-clock connections, 273,349 have a clock-launched arrival. Of those, 260,265 connect through fabric switches, 3,963 are direct and 9,121 use a selected site mux. All 2,823 consecutive net pin pairs across the 100 saved slow setup paths appear in the gallery, including repeated occurrences. Cell arcs use their individual delays. These structural arrival envelopes omit clock skew, timing exceptions and input sensitization.

The original openXC7 logic-depth view shows 234,038 placed driver/sink cell pairs reachable from clocked boundaries. Its vertical axis counts combinational cells along the longest structural chain. Pairs collapse multiple pins on the same two cells. At C32 the default filter shows 4,565 Vivado net connections and 22,087 primitive arcs alongside 2,780 openXC7 pairs. The route and delay of the full native implementation remain open under G4.4b. [Flow evidence ledger](../../yap/hls_spacetime/g44-four-phi-flow.json)

Serve `runs/spacetime-g4-parity-2026-11-24/vivado-physical-branches/four-gallery` from the artifact archive for the updated four-worker comparison. To reproduce the flow sidecars from the paired replay, use its `RAPIDWRIGHT_PATH`, the JDK 21 executable, the same physical device database and the archived checkpoint's readable EDIF. Run under the preceding serial process-group guard with a fresh output directory.

```sh
python3 "$workload/flow.py" --gallery "$PAIRED" --run "$RUN" --archive "$REFERENCE_ARCHIVE" \
  --edif "$WORK/vendor.edf" --java "$JAVA" --jar "$RAPIDWRIGHT_JAR" --chipdb "$CHIPDB" --output "$FLOW"
npm --prefix apps/hls_spacetime start -- --data "$FLOW"
```

### openXC7 placement timing

The 3D view in the enriched four-Phi gallery opens on placed pins. nextpnr writes SDF from the same placement with packing, placement and routing disabled. The exporter checks the router, device database and checkpoint hashes, matches every driven packed input to its unique driver, and propagates from clock pins through modeled primitive arcs. Each connection uses its own predicted interconnect delay. An input stops at its own arrival even if a different input reaches the same cell later. The vertical scale is nanoseconds. Tick **Shared ns scale** to compare heights directly.

Pins use their placed tile coordinates. Local strokes show cell delays. Picking a pin reveals one schematic connection, and **Endpoint spans** draws all of them as dashed lines. **Cell pairs** restores logic depth, including connections without qualified timing. The placement contains 85,828 net records and zero bound switch lists. Neither the endpoint spans nor the placement estimates establish the wires used by a completed route.

Across the design, 204,760 packed pin connections and 364,736 primitive arcs have both clock-launched estimates and observed cells at both ends. At C32, the activity filter selects 3,484 connections and 64,664 primitive arcs. Bus-wide DSP timing can produce many coincident arcs. Cell-level activity cannot distinguish which bit propagated. The old C32 view drew 1,152 connections across multiple logic levels, with a maximum jump of 30. Along the ten-cell scheduler bit-84 path from RAM output `DOADO11` to DSP input `A7`, the nine modeled cell arcs sum to 4.002 ns and the nine predicted net increments sum to 11.565 ns. This is a structural estimate for that path. [Placement timing evidence and coverage](../../yap/hls_spacetime/g44-four-phi-placement-timing.json)

The original placement-timing gallery is archived under `four-phi-placement-timing/gallery`. To reproduce from the flow gallery above, run under the same process-group guard.

```sh
python3 "$workload/placed_flow.py" --gallery "$FLOW" --run "$RUN" --router "$NEXTPNR_SPACETIME" --chipdb "$CHIPDB" --output "$PLACED_FLOW"
npm --prefix apps/hls_spacetime start -- --data "$PLACED_FLOW"
```

#### Four-Phi routed parity campaign

The routed two-worker pair already exercises the scheduler RAM, capture register, DSP operand and correction path. Revisit four-worker routing for a specific congestion, fanout or implementation question. Feature coverage uses the smallest design that exercises the missing mode.

1. **Obtain a legal native route.** The stock-map run ended its hour with 2,120 overused wires. Mapping the decoder and harness separately with the corrected SDP72 map retained 64,989 decoder primitives, 48 DSPs and 52 block RAMs. At 20 ns and seed 1 it ended its hour with 80 overused wires. A retry requesting `--no-tmdriv` on the original frozen placement reached one conflict, then stopped at two after 50 iterations without improvement. That placement also restores timing-driven routing. Both contested wires carry the same scheduler output bit. Try a different routing seed on that placement and compare the named conflicts before repeating a full placement. The four-worker native gallery still uses placement estimates. [Routing attempts and input identities](../../yap/hls_spacetime/g44-phi-routing.json)
2. **Bind the replay to that implementation.** Match packed pins, placement and simulated primitives to the routed checkpoint. Repeat the 4,096-clock replay and the public capture-lane checks if synthesis changes. Establish correspondence of the C32–C37 RAM transaction before attaching any route or timing to the comparison.
3. **Qualify and expand the physical view.** Trace used switches to each sink on scheduler bit 84 first, including the inserted carry-input LUT and any packed LUT input permutation. Check the native model and timing provenance at each hop, then export the whole design. Report routed, direct, predicted and unresolved branches separately for the whole design and for C32. Registered hard-block timing and per-output-bit switching each need their own witnesses.

#### Two-worker X-plane routed witness

Both tools implemented the same two adjacent X workers, four RTL files, two-pin harness, XC7Z030-1 and 20 ns clock. Both routed the design. Vivado 2024.2 routed all 22,711 routable nets, with +5.588 ns setup and +0.052 ns hold slack. The seed-1 openXC7 placement took 119 seconds and the original route took 64 seconds, ending with zero conflicts. Its stored placement enables timing-driven router2. The pinned frontend imports that setting after parsing the CLI, overriding the historical `--no-tmdriv` argument. Omitting the flag reproduced the checkpoint, all 509,097 fixed switches, SDF and both timing reports byte for byte. The old delay lookup reported 41.06 MHz. With corrected LUT terminal lookup the same routed implementation reports 40.92 MHz against 50 MHz.

The shared 4,096-clock stimulus elicited 36 status frames and six corrections. Each mapped functional replay checked the public digest against RTL on every clock, along with the physically retained capture and handshake registers for the enabled X plane. Vivado retains 102 X payload bits. The native mapping retains all 128. All observed primitives were located in their own implementation.

| Two-worker replay | Vivado | openXC7 |
| --- | ---: | ---: |
| Located primitives | 29,059 | 28,419 |
| Timed data connections in the viewer | 108,835 | 100,758 |
| Connections with unresolved physical spans | 0 | 0 |
| Active connections / primitive arcs at C90 | 821 / 3,294 | 674 / 3,284 |
| RAM clock → capture D for state bit 84 | 2.809 ns | 3.697 ns |
| Capture clock → executor DSP operand | 3.293 ns to A9 | 5.215 ns to A8 |

Vivado supplied a pin-to-pin interconnect delay for all 108,836 data connections. One lacks a clock-launched arrival. Of the 108,835 drawn, 100,277 have fabric switch tiles, 1,208 are direct and 7,350 pass through a selected site mux. On openXC7, 8,725 of 113,931 nonclock SDF connections lack a modeled launch and 4,448 more lack an observed endpoint. All 100,758 drawn branches have switch geometry and an SDF increment. Both panels interpolate height between endpoint times.

Picking an openXC7 branch reports its SDF delay and an independent sum along the traced switches. After routing, nextpnr legalises the packed LUT inputs onto their physical pins. Its timing lookup now finds the retained permutation switch for that pin on the same net and LUT site. All 53,469 direct and 47,289 remapped connections in the paired viewer agree with the switch sums within 1 ps of SDF serialization. Both panels use their own SDF for the vertical axis. The earlier openXC7 gallery used placement predictions for the remapped population, with a median absolute difference of 270 ps. [Original wire audit](../../yap/hls_spacetime/g44-pin-coverage.json)

Across the complete native SDF, 70,088 direct and 49,910 permuted connections agree with the physical branch sums. All 7,828 remaining records are distributed constant sinks outside the traced timing population. The ordinary clock report and the ranked endpoint export give a worst period of 24.439 ns and slack of −4.439 ns. The audit checked all 1,711 routing increments across the critical path and 100 ranked endpoint paths, their cumulative times and slack. The verbose clock report reproduced the ordered names and model delays of all 199 switches on the worst path. The checkpoint and functional replay retain their original identities. [Delay lookup and report checks](../../yap/hls_spacetime/g44-lut-route-delay.json)

The activity filter checks settled output bits on 2,547 Vivado and 2,232 openXC7 carry, RAM and DSP outputs, with primitive-level filtering on other rows. Every known bit change fell on the same cell’s known-change mask in the original 4,096-clock replay. At C90 the Vivado executor DSP changed P[32] while P[41] held zero. Under the former cell filter 1,077 Vivado and 919 openXC7 net branches lit up. Requiring the observed driver bit on covered branches reduces those counts to 821 and 674.

Open `/workload.html?view=flow&cycle=90` in the paired gallery. In **Connections**, select **State RAM → capture D** or **Capture Q → DSP input** to isolate bit 84 in both panels. Vivado shows five then 21 switch-tile visits, collapsing consecutive switches in a tile. The first stage also traverses the selected CFFMUX.O6 site switch on its 55 ps capture span. openXC7 shows 13 then 39 switch visits. Both simulations matched all 4,085 known RTL RAM samples. At C89 only the RAM output changed among the three sampled pins. At C90 the RAM output, capture Q and DSP operand changed on both designs.

```sh
base=../hls_artifacts/runs/spacetime-g4-parity-2026-11-24
npm --prefix apps/hls_spacetime start -- --data "$PWD/$base/vivado-physical-branches/gallery" --port 49715
```

For the corrected routed timing, `two-phi-lut-route-delay/evidence.tar.gz` includes the SDF, both sets of timing reports, the patched tool and a replay command for the frozen placement. Its `verify-routes.py` uses the switch delays in `two-phi-pin-coverage/evidence.tar.gz`.

To rebuild the original paired witness, unpack `two-phi-routed/{capture,observations}.tar.gz` and `two-phi-paired/{vivado-reference,vivado-observations}.tar.gz` in a fresh directory. Use the pinned Java, RapidWright JAR, device data, chip database and Xilinx `constids.inc` from the witness. The paired input archive also records Vivado's synthesis inputs and Tcl. [Input identities and clock-by-clock checks](../../yap/hls_spacetime/g44-phi-routing.json)

```sh
workload=apps/hls_spacetime/test/native/four_phi/workload
python3 "$workload/pair_two_phi.py" publish --run "$stage/capture" --native-work "$stage/obs" \
  --vendor "$stage/results/phi-20.0ns" --work "$stage/observed" --java "$JAVA" --jar "$RAPIDWRIGHT_JAR" \
  --chipdb "$CHIPDB" --constids "$CONSTIDS" --output "$stage/gallery"
```

To rerun the Vivado functional simulation, use `measure` with a fresh `--work` directory, the same capture, native observations, vendor results, Java and JAR, plus `--models`, `--yosys` and `--guard`. Both commands use the pinned data in `RAPIDWRIGHT_PATH`.

#### Vivado references for the remaining G4 work

The artifact archive keeps the Vivado inputs, routed checkpoints, netlists, SDF and verification records for local analysis. The 512-clock dynamic-tap fixtures checked all 16 addresses on SRL16E and all 32 on SRLC32E. Both exercised 246 shift clocks and 266 holds. The routed output changed 204 and 217 times respectively. The September micro checkpoint already includes a DSP with MREG and PREG enabled. The original four-worker route has 18 PREG-enabled DSPs available for workload probes.

The September four-worker RTL produced 704 status frames per plane and zero corrections in 32,768 clocks. A separate current 2 × 1 X/Z build with one shard per plane emits corrections on both planes. The measurement harness preserves all 256 existing payload capture bits and adds two ready samples. Its RTL and the standard harness agreed on every accepted frame. Both the post-route Vivado netlist and the openXC7 synthesis netlist matched all 89 accepted 128-bit payloads and their clock indices, including six X and eleven Z corrections. The first X correction was accepted at C237 and the first Z correction at C239. Vivado routed all 45,119 routable nets. The original four-worker gallery and its openXC7 routing campaign retain their own checkpoints.

#### Vivado block RAM and carry exits

One logical block RAM address, enable or write-enable pin can drive two physical pins. The two-worker gallery contains 183 such connections and the four-worker gallery contains 346. The viewer draws both routes with the logical pin pair’s SDF delay. When the routes occupy the same sequence of tiles, picking the line lists both pins. Two pairs on the two-worker decoder and seven on the four-worker decoder diverge at tile resolution. The four-worker checkpoint also routes 394 carry connections through flip-flop sites configured for pass-through. Picking one shows the selected site mux and the D→Q exit.

The two checkpoint exports cover every displayed, clock-launched Vivado connection. A separate walk of Vivado’s exported physical endpoint nodes and assigned PIPs checked all 1,452 recovered paths and 13,588 switch visits in order. The original bit-84 path still includes the 55 ps C6LUT/O6 → CFFMUX → CFF/D span at SLICE_X6Y21. [Physical branch checks](../../yap/hls_spacetime/g44-vivado-physical-branches.json)

#### Dynamic shift-register taps

The two-worker and original four-worker Vivado inventories contain the same primitive types. The four-worker openXC7 inventory adds SRL16E and SRLC32E, all with fixed tap addresses. Two small variable-tap fixtures use the same RTL, XC7Z030-1 and 20 ns constraint on both backends. Their openXC7 routes finished with zero conflicts. The native and Vivado mapped simulations agreed with an independent shift-register model on address, enable, input, tap output and captured output at every one of 512 clocks per fixture.

| Selected storage cell | SRL16E | SRLC32E |
| --- | ---: | ---: |
| Tap addresses exercised | 16 / 16 | 32 / 32 |
| Output changes after a disabled shift and a changed address | 109 | 112 |
| Changing address pins with an openXC7 SDF arc to Q | 2 / 4 | 3 / 5 |
| Changing address pins with a Vivado SDF arc to Q | 4 / 4 | 5 / 5 |
| Vivado clock-to-Q delay, slowest reported value | 1,102 ps | 1,109 ps |

The original exporter retained pre-rename port labels. The packer overlay now moves the original pin name with the SRL address, data and output port. On fresh routes the live addresses bind to A2–A5 and A2–A6 respectively. Native SDF now lists all four and five address paths to Q at 124 ps each and drops the spurious A1 path. The value comes from a generic LUT model. Clock-to-Q and data/enable setup and hold are still absent, so timed flow continues to exclude these storage arcs. [Original SRL witness](../../yap/hls_spacetime/g44-srl-taps.json) · [Overlay results](../../yap/hls_spacetime/g44-pin-coverage.json)

The 10 ns XC7Z030-1 DSP micro design retains a DSP48E1 with MREG and PREG enabled and both operand registers bypassed on each backend. The two mapped UNISIM replays agreed on 512 signed operand pairs and M-register products, and all 511 next-clock P captures. Vivado reports a maximum 383 ps CLK → P[47:0] and 42 setup/hold records. Its SDF exposes the external pins of the DSP. The internal M stage was observed in the functional model. The openXC7 routed SDF has an empty cell entry for this registered mode. [DSP witness](../../yap/hls_spacetime/g44-pin-coverage.json)

To reproduce the named-output replay, restore the two-worker observation archives and overlay the functional netlists and VPI observers from the feature evidence archive (or rebuild the observer from `transitions.cpp` for the host). Run `pin_activity.py --help` next to `pair_two_phi.py` for the gallery, routed checkpoint, work directories and pinned model inputs. The evidence archive retains the switch-delay probe, the row-by-row comparison and the script that attaches its sums.

## Remaining work

| Feature to qualify | Smallest existing witness and completion check |
| --- | --- |
| Variable-tap storage | Supply a mode-specific address-to-Q model, clock launch and data/enable checks for the two dynamic-tap fixtures, then admit the qualified arcs into timed flow. |
| Registered DSP arithmetic | Add native CLK-to-P and input timing checks for the witnessed MREG/PREG mode. Keep the internal register cycle explicit in the viewer. |
| Block RAM write modes | The RAMB36E1 SDP72 READ_FIRST probe covers both output-register settings. Its WRITE_FIRST variant leaves 212 connected ports unqualified. When an application uses that mode, check same-address reads and writes and qualify its mode-specific timing. |
| Activity on other output ports | Extend the named-pin monitor when another multi-output primitive or port is exercised. |
| Routed checkpoint import | The original and patched nextpnr binaries both fail in the Series-7 PIP-name import when reopening the routed JSON. Reproduce timing from the frozen placement and seed. Qualify the inverse PIP and wire-name mappings for direct checkpoint reopen. |

1. **Distributed constant ties.** The 2,409 missing global-to-local constant branches are outside this visualization round. Their cut wires remain inspectable.
2. **Multicorner timing and other hard modes.** The XC7 estimate includes predicted wiring and compiled slice FF clock parameters. A new corner, generated/gated clock relationship, DSP register, SRL tap or RAM configuration needs its own pin, clock and mode evidence. Use a workload that exercises the class, then compare native and vendor reports on matched parts and constraints. The four-Phi replay supplies RAM addresses, enables and read latency for one memory. Same-address read/write collisions were exercised in the smaller inferred-memory witness.
3. **Storage mapping and producer scope.** The 407 unqualified XC7 destination bits and unsupported scalar expressions remain explicit. Additional workloads need their own logical recording and implementation bindings. A changed-schedule timing claim requires a new implementation.
