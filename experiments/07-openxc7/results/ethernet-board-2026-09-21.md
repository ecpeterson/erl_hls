# TE0715 Ethernet compile probe — 2026-09-21

Both internal PMA loopback and external SFP profiles synthesize and route natively on Apple Silicon for `xc7z030sbg485-1`. Neither is programmable yet. The external profile differs only in GTX loopback/polarity constants; both runs have the same area and partial timing results. See [the probe contract](../docs/ethernet-board.md) and [machine-readable inputs/results](ethernet-board-2026-09-21.json).

| Complete probe resource | Count |
| --- | ---: |
| Occupied physical LUT sites | 1,645 |
| LUT output slots (`SLICE_LUTX`, including carry helpers) | 2,387 |
| Flip-flops | 1,376 |
| RAMB36E1 / MMCM / BUFG / GTX channel | 2 / 2 / 9 / 1 |

With production timers and the same packet core, the isolated supervisor changes mapped LUT1–6 cells from 729 to 979 and flip-flops from 961 to 1,152; both versions retain two RAMB36E1s. These synthesis counts exclude dedicated carry/memory/mux cells and are not directly comparable to routed LUT-slot counts. [Full comparison](../ethernet-recovery-result.json).

| Clock | Requested MHz | Partial modeled MHz |
| --- | ---: | ---: |
| Control | 25 | 92.19 |
| TX full | 125 | 106.55 |
| RX full | 125 | 123.72 |
| TX half | 62.5 | 591.37 |
| RX half | 62.5 | 519.48 |

Both profiles use router2, seed 1 and the isolated [LUT-corrected backend](lut-legality-2026-09-21.md), SHA-256 `02490f35c4ec3c02672bd59d22d2023b6e80e69053de6892f48d7fce18230c21`. Each full compile/check takes about 14–15 seconds. Dedicated clock routing succeeds; the independent placement/connectivity/FASM checker passes 78,528 LUT truth-table rows per profile. This does not verify route connectivity or hard-primitive configuration.

Digital checks pass before and after XC7 mapping: interrupted frames, all four stopped user clocks, lock/reset-done failures, held RX frames, explicit restart, stale startup lock and reset with no RX clock edge. Both divide-by-two phases are covered. The complete recovery regression takes 139 seconds locally; simulation shortens only the startup timeout, retaining the 1,024-cycle clock watchdog. Independent frame/FCS and alignment regressions also pass. The board's frame generator/checker, held-beat behavior and coherent snapshots pass separately. The Linux client passes native fake-MMIO checks and builds as a static ARM Linux ELF; it has not run on the board.

Three limits remain:

- **Configuration:** the checked database lacks GTX channel/common frame mappings and feature encodings. Current upstream [Zynq tile data](https://github.com/openXC7/prjxray-db/blob/a90f27c1caefee5276f47440f4c730b50519a86f/zynq7/xc7z030/tilegrid.json) also leaves the selected channel and common tile `bits` empty, with no GTX segbits files in that revision. This blocks bitstream generation. Vivado may be needed to establish a reference or build the initial Ethernet image; this result does not establish that open support is impossible.
- **Timing:** even the partial model misses 125 MHz. BRAM sequential paths, calibrated flip-flop timing and generated-clock relationships are not covered adequately; asynchronous crossings still need physical timing constraints. A slower Ethernet user clock is not a valid workaround for the required line rate.
- **Hardware:** GTX analog behavior, MMCM phase/skew, comma alignment, elastic buffers, reset sequencing, carrier reference clock and DAC operation remain unqualified. Functional simulation cannot replace those checks.

PS Ethernet and the existing PS–PL DMA experiments remain usable without solving the GTX configuration gap.
