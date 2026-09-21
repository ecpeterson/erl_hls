# Native GTX candidates

The experiment assembles PRBS, Ethernet loopback and external-SFP candidates for TE0715-05-71C33-A on TEF1002-03-A using native Apple Silicon tools. Assembly requires the matching retained Vivado reference and rejects a GTX configuration mismatch. No command programs hardware. Native timing and physical operation remain unqualified; use the [timing-closed vendor candidates](vivado-reference.md) as the initial board baseline.

## Build

From `experiments/07-openxc7`, with the [pinned tools](../README.md#setup) installed:

```sh
bash gtx/build_backend.sh build/native-backend
export ERL_HLS_NEXTPNR="$PWD/build/native-backend/bin/nextpnr-gtx"
bash run_ethernet_probe.sh
# Or: bash run_ethernet_probe.sh --external
# Or: bash run_gtx_probe.sh
```

The separate backend includes the LUT placement/input-origin fixes and two clocking fixes. Reference-buffer swing settings are emitted with or without a shared PLL. Converting a BASE clock primitive to ADV leaves its nonexistent second clock input disconnected; genuine ADV clock inputs remain intact. Existing installed tools are unchanged.

Routing retains `probe.fasm` under `build/ethernet-board/{loopback,external}` or `build/gtx-probe`. Assembly is a separate, checked step:

```sh
python3 gtx/assemble.py \
  --database /path/to/prepared-database/zynq7 \
  --fasm build/ethernet-board/loopback/probe.fasm \
  --reference /path/to/retained-release/results/ethernet-loopback/candidate.bit \
  --profile ethernet-loopback \
  --tools .apio/packages/openxc7/bin \
  --output build/native-loopback
```

Use the matching FASM, reference and `--profile` for `ethernet-external` or `prbs`. The database is the SBG485 overlay prepared by the probe scripts. The [reference report](../results/vivado-reference-2026-09-21.json) identifies the retained archive and accepted vendor images. Output must be new; failures retain diagnostics without publishing `candidate.bit`.

## What is checked

The overlay changes only the measured channel/common tile mappings and the missing feature tables. Other GTX sites, the other reference buffer and shared-QPLL profiles are rejected. Installed database files remain unchanged.

- Independent vendor references locate channel `GTX_CHANNEL_1_X186Y17` at frame base `0x00442480`, word offset 22, and common `GTX_COMMON_X186Y23` at that base, offset zero. Ten inert references cover two independent mapping checks per tile and the bonded buffer controls.
- Every candidate must match the vendor image over the entire 1,933-bit known GTX mask, including unset bits. Donor hashes and tile connectivity are checked; unconditional interface wires need no frame bits.
- The missing 32 bottom-half clock-cascade definitions come from the pinned Artix table. All 2,804 existing Zynq definitions agree, all additions match Zynq's top-half table, and the bottom-half tile graphs match. This is corroborated database reuse, **not an independent measurement of those 32 locations**. No clock-frame addresses or timing estimates are copied from Artix.
- Every supplied non-ECC frame bit must survive assembly and decoding. This checks serialization, not whether every encoded resource implements its intended function. Ethernet routing separately checks LUT connectivity and emitted truth tables.

The [native results](../results/native-gtx-2026-09-21.json) record three completed images and their limits. Matching GTX settings does not qualify the whole native configuration, generated clocks, CDC constraints, analog channel or DAC. The native Ethernet routes still miss their partial 125-MHz targets.

## Regression and new configurations

CI checks overlay boundaries, donor disagreements, immutable reuse and substituted references without proprietary tools. To exercise the patched backend against a retained Ethernet route:

```sh
python3 gtx/check_backend.py --nextpnr "$ERL_HLS_NEXTPNR" \
  --chipdb build/gtx-probe/chipdb.bin \
  --stage build/ethernet-board/loopback --output build/backend-checks
```

Its 11 cases check default/explicit swing values, buffer controls and BASE/ADV clock retention. Nondefault reference-buffer settings are inert writer tests, never board candidates.

For another GTX site or configuration, obtain independent evidence before extending the accepted scope. `gtx/reference.py` prepares six tile-location references and `vivado/refclk.py` four buffer references for a Vivado host. These unconnected primitives deliberately use X-Ray fuzzer DRC exemptions: **never program them or reuse those exemptions in a board build**. The retained references suffice for the current candidates; no running Vivado host is needed.
