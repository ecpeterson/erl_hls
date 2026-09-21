# GTX configuration prerequisites

The pinned Zynq database still lacks the selected channel/common configuration-frame locations. The [Vivado reference batch](vivado-reference.md) has independently measured those locations and checked donor encodings against a full Ethernet image. The native writer also omits two reference-buffer default bits. Integrating these findings and checking the resulting complete native image remain outstanding.

| Tile type | Distinct enabled features | Encoded features | Fixed connections | Missing definitions |
| --- | ---: | ---: | ---: | ---: |
| GTX channel 1 | 735 | 323 | 412 | 0 |
| GTX common | 6 | 3 | 3 | 0 |
| GTX interface | 61 | 0 | 61 | 0 |

The [recorded audit](../results/gtx-coverage-2026-09-21.json) identifies its routed FASM, Zynq tilegrid and pinned donor files. It checks logical tile connectivity independently of family timing estimates, expands enabled FASM bits, and recognizes unconditional pseudo-PIPs. Unlike the coarse compile-probe audit, it does not require configuration bits for connections declared always present. Neither audit establishes encoding correctness or hardware operation.

Reproduce the audit without modifying either database:

```sh
python3 gtx/coverage.py /path/to/database/zynq7 \
  build/ethernet-board/loopback/probe.fasm build/gtx-coverage
```

## Device-specific reference

Prepare a small bundle on this machine, then run it where Vivado supports `xc7z030sbg485-1`:

```sh
python3 gtx/reference.py build/gtx-reference-only
cd build/gtx-reference-only
vivado -mode batch -source run.tcl
```

The bundle contains six **inert configuration references, never board images**. It uses the pinned [X-Ray channel](https://github.com/openXC7/prjxray/blob/ed3331c6200f421164101388759fc2860b0f5634/fuzzers/005-tilegrid/gtx_channel/generate.tcl) and [common](https://github.com/openXC7/prjxray/blob/ed3331c6200f421164101388759fc2860b0f5634/fuzzers/005-tilegrid/gtx_common/generate.tcl) procedures, including their DRC exemptions for unconnected primitives. Those exemptions do not belong in a board build. The bundle records the Vivado version and retains each checkpoint and bitstream. There are no hardware-manager or programming commands. All six references ran successfully under Vivado 2024.2; the independent attribute pairs agree on the selected tiles' locations.

Two separate attribute changes per tile provide a first consistency check: channel comma detection and CPLL lock configuration; common QPLL division and bias configuration. Return the complete bundle after execution. Decode the bitstreams with X-Ray `bitread`, compare each variant against its baseline, and check whether both changes imply the same frame origin and word offset using the donor definitions. Then validate the reference-clock buffer, remaining encodings and routed probe against independent Z7030 evidence. A matching pair alone is insufficient to enable assembly, and nothing here installs a speculative database overlay.

The retained reference data supports further native work without a running Vivado host. It covers this channel/common configuration, not every GTX site or feature combination. PS Ethernet and PL330 DMA remain independent of the native GTX assembly work.
