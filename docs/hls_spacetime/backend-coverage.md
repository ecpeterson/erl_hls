# Vivado and openXC7 viewer coverage

The repetition N2 decoder can now be inspected in both viewers at the same write, bit and clock. Both publications support placement, within-clock arrival, data/enable/reset cones, exact sink selection, timing colors, path neighborhoods and an independently identified static setup path. The principal remaining difference is how much physical routing geometry is available. The two implementations also have different delay models, device families and producer sidecars.

## Matched application witness

The six-actor run uses the same six archived RTL inputs and retained stimulus. The XC7 compile-only wrapper exposes both streams, status and all six fault flags on 100 pins. A three-bit selector exposes each actor’s 16-bit failure word in the same interval. Only the clock has a fixed board pin. Verilator matched every public trace field and all 581 taps (17,877 tap bits per cycle) over 2,369 cycles. The join checks the replay receipt, original logical recording, ordered synthesis inputs and the new implementation identity. This finite simulation witness supports reusing the logical events for that stimulus. Each backend supplies its own physical bindings.

The interval starts after completion C(3) at cycle 1774 and ends at C(4) at cycle 1873. The two recordings agree on the identities, cycles, resources, addresses and masks of all 468 writes to 51 words. Both recordings contain 7,637 writes overall. Vivado’s enriched recording contains 61,764 events and the XC7 replay contains 16,321. The retained Vivado implementation targets XCZU7EV and the local XC7 route targets XC7Z030-1. Their delay values describe their respective placements and models.

| Step-4 population | Vivado | openXC7 |
| --- | ---: | ---: |
| Mapped target-bit occurrences / 92,745 requested | 72,259 | 90,797 |
| Distinct mapped destination bits / 8,466 requested | 6,108 | 8,059 |
| Writes fully / partially / wholly unmapped | 263 / 205 / 0 | 331 / 137 / 0 |
| Registered data cones with known / unknown bound | 468 / 0 | 410 / 58 |
| Enable cones | 270 known, 198 outside registered scope | 202 known, 266 without a mapped enable pin |
| Reset cones | 468 outside registered scope | 468 outside registered scope |
| Distinct required net branches | 75,541 | 109,591 |
| Branch geometry | 44,493 resolved, 8,576 intrasite, 15,491 partial, 383 ambiguous, 6,598 unavailable | 376 resolved, 612 requested but unavailable, 108,603 outside the route request |
| Unique arc delays in these cones | 68,879 logic and 68,943 net known, 6,598 net missing | 98,462 logic and 109,591 net known |

Geometry and delay have separate denominators. Across the raw XC7 capture, nextpnr reported 53,366 routed sink delays, 71,773 predicted and 3,934 unavailable. It also returned 31,697 empty cell-delay queries, including structurally inapplicable pin pairs. Within the selected cones every admitted arc had a delay. One shared packer-inserted LUT feed-through lacked input correspondence. It accounts for the 58 unknown aggregate data bounds across two distinct data cones. Sinks whose fan-in excludes that LUT retain their known arrivals. Of the 407 unqualified destination bits, 364 lacked a nonconstant synthesis driver and 43 failed the packed FDRE qualification.

## What closed the gap

- **Storage and primitive boundaries.** The original 177-pin top exceeded the package limit and unscoped provenance exhausted the 100,000-object allowance. A four-bit pilot on the new wrapper located two distinct bits, or 28 target occurrences in step 4. With identical four-bit demand, the qualified pilot located all four bits, covered 114 target occurrences and produced known data bounds for 57 writes. The all-word capture then expanded the denominator. Applying the former primitive stops to the final graph, 3,661 distinct D bits reached CARRY4, 3,528 reached a dedicated mux and 7,956 reached an external input. The corresponding enable counts were 1,986, 1,642 and 2,636. The populations overlap. All 8,059 mapped resets reach an external input. The adapter now qualifies legal CARRY4 and MUXF7/F8 dependencies and distinguishes external launches. It verifies the constant-high slice-local enable on 5,423 mapped bits even where packing removes its wire. Unknown power-up values stay unknown.
- **Selected correction.** At cycle 1852, write `e/25066` targets `register/____state_154`. Vivado mapped 409 of 537 D bits and XC7 mapped 528. Of the latter, 527 have finite registered arrivals. Bit 202 has the longest of those known bounds, 38.646 ns over 71 arcs. All 36 demanded net branches occur in the frozen capture, with 20 resolved and 16 lacking endpoint geometry. Headless Chrome selected bit 202 in both published arrival views. Vivado showed 5.223 ns over 45 arcs. Both viewers opened the path neighborhood at that write. The openXC7 viewer omits missing route spans and keeps their delay in the ordered path.
- **Static timing.** Vivado supplies independent fast/slow SDF data plus a saved STA report. XC7 supplies one backend structural estimate and the ordered native setup report in integer ps. At the 5 ns request, the worst eligible same-clock, same-edge native check runs from `$auto$ff.cc:337:slice$40546/Q` to `$auto$ff.cc:337:slice$42155/D`. Its 53.623 ns data path plus 0.100 ns setup gives −48.723 ns slack. Of 69 STA branches, 47 resolved. The archived Vivado report gives 8.808 ns data and −3.997 ns slack on its own path. The viewer qualifies requirements and slack only for checks supported by the backend evidence.
- **Primitive timing witnesses.** An independent enumeration of 15 register-launched chains on the reconvergent fixture matched the backend’s ordered maximum of 2,935 ps and slack of 7,065 ps. Its four selected branches reach the exact native BEL wires. Ten connected carry DI pairs matched the placed-site Project X-Ray variant envelope within 1 ps. Reproducing the four-Phi scheduler’s RAMB36E1 SDP72 READ_FIRST mode, all 32 connected output bits launched at the calibrated 2,080 ps without the output register or 748 ps with it. Both native worst paths crossed from RAM into arithmetic. WRITE_FIRST left all 212 connected ports unqualified. The inferred-memory simulation ran 672 cycles, including read/write collisions. N2 itself contains no BRAM, SRL or DSP. The four-Phi comparison uses a mode-matched primitive witness and the historical application report. [BRAM behavior and board witness](../../platforms/xc7/docs/bram-sdp72.md)

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
npm --prefix apps/hls_spacetime start -- --data "$PWD/repeat/prepared"
```

For the primitive checks run `check_probes.py APIO CHIPDB TIMING_TOOLS TIMINGS CALIBRATION FRESH_OUTPUT` under the same guard. `TIMINGS` is the Project X-Ray `zynq7/timings` directory. `CALIBRATION` is the archived `experiments/07-openxc7/results/xc7-timing-model-2026-09-25.json`. The [compact evidence ledger](../../yap/hls_spacetime/g44-repetition.json) identifies both publications, the pilot, the native checkpoint, the timing probes and the saved selections. The project artifact archive contains the portable viewer, native capture and validation evidence under `runs/spacetime-g4-parity-2026-11-24/g44-repetition/`.

## Remaining work

1. **Route geometry at application scale.** The final export requested 74 of 39,811 packed nets. A whole-interval request already has 109,591 distinct branches against the 100,000-object geometry ceiling, before counting PIPs and constituent wires. Chunk requests against one checkpoint, deduplicate chip-wide constants, and keep a complete demand-to-disposition index. Independently qualify missing site attachments on permuted, fractured or packer-inserted LUTs. Re-run this ledger and the selected-bit browser check to measure recovered branches.
2. **Multicorner timing and other hard modes.** The XC7 estimate includes predicted wiring and compiled slice FF clock parameters. A new corner, generated/gated clock relationship, DSP register, SRL tap or RAM configuration needs its own pin, clock and mode evidence. Use a workload that exercises the class, then compare native and vendor reports on matched parts and constraints. Logical memory attribution also needs address, enable, latency and collision observations.
3. **Producer and regional views.** The XC7 publication supplies generic write lineage. The archived Vivado operand and region sidecars contain additional evidence. Generate checked operand masks from the matching logical producer, qualify their physical bindings separately, and derive regional routing counts from a complete native route census before comparing regional or step-level optimization metrics.
