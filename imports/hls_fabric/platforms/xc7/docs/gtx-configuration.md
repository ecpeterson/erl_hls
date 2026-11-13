# Native GTX candidates

The experiment assembles PRBS, Ethernet loopback and external-SFP candidates for TE0715-05-71C33-A on TEF1002-03-A using native Apple Silicon tools. Assembly requires the matching retained Vivado reference and rejects a GTX configuration mismatch. No command programs hardware. The [bounded board witnesses](gtx.md) cover the retained PRBS images; they do not qualify native timing, other configurations or sustained link operation.

## Build

From `platforms/xc7`, with the [pinned tools](../README.md#setup) installed:

```sh
bash gtx/build_backend.sh build/native-backend
export ERL_HLS_NEXTPNR="$PWD/build/native-backend/bin/nextpnr-gtx"
bash run_ethernet_probe.sh
# Or: bash run_ethernet_probe.sh --external
# Or: bash run_gtx_probe.sh
```

The separate backend includes the LUT placement/input-origin fixes, the SDP72 width encoding, three clocking fixes and constant-carry-head relocation. When both the sum and carry leave a constant carry-chain head, the packer now recovers the initial carry value before relocating the sum; otherwise those consumers can compete for one physical output mux at every placement. Reference-buffer swing settings are emitted with or without a shared PLL. Converting a BASE clock primitive to ADV leaves its nonexistent second clock input disconnected; genuine ADV clock inputs remain intact. Constant-low `MMCME2_BASE.PWRDWN` is represented by the required pin inversion instead of powering the MMCM down. Existing installed tools are unchanged.

For an offline, serial build of only the final backend, copy `gtx/offline-recipe.json` to a local recipe and set its two archive paths, seven patch paths, executable tool paths and Boost directory. Keep the source hashes, patch order and execution settings unchanged. Absolute paths are simplest; relative paths resolve beside the supplied recipe. The pinned nextpnr source is `68aeeb39f92e39bfb239c7e4a44dd93451fc1889`; Eigen is 3.4.0. Obtain those exact archives separately before starting: this builder never downloads missing inputs.

Launch this command under an external process-tree memory/time guard, with no overlapping heavy job; the recipe calls for a 6 GiB memory ceiling:

```sh
python3 gtx/build_offline.py --recipe /path/to/build-recipe.json \
  --output /path/to/fresh-native-backend
```

The builder rejects an existing output directory, freezes and hashes its inputs, applies the seven patches in order and compiles with one job. It retains failure evidence instead of resuming. Success produces `bin/nextpnr-gtx`, `result.json`, the normalized `recipe.json`, `build-script.py`, patched-source hashes and individual phase logs/receipts. These are the portable backend artifacts consumed by board image drivers. They identify the actual local tool build; they do not claim a platform-independent binary hash, native equivalence, timing or board qualification. `python3 -m unittest test_gtx_offline_build` exercises recipe rejection, archive boundaries and receipt generation with simulated external commands.

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

Use the matching FASM, reference and `--profile` for `ethernet-external` or `prbs`. The database is the SBG485 overlay prepared by the probe scripts. The [reference report](../../../docs/artifacts.md#historical-reports) (`experiments/07-openxc7/results/vivado-reference-2026-09-21.json`) identifies the retained archive and accepted vendor images. Output must be new; failures retain diagnostics without publishing `candidate.bit`.

Pass `--source-cache DIRECTORY` to seed the coverage step from a retained set of pinned donor files. The assembler parses the generated `.bit` header before replacing only its date and time with fixed values; the result record retains the normalized header and deterministic image hash.

## What is checked

The overlay changes only the measured channel/common tile mappings and the missing feature tables. Other GTX sites, the other reference buffer and shared-QPLL profiles are rejected. Installed database files remain unchanged.

- Independent vendor references locate channel `GTX_CHANNEL_1_X186Y17` at frame base `0x00442480`, word offset 22, and common `GTX_COMMON_X186Y23` at that base, offset zero. Ten inert references cover two independent mapping checks per tile and the bonded buffer controls.
- Every candidate must match the vendor image over the entire 1,933-bit known GTX mask, including unset bits. Donor hashes and tile connectivity are checked; unconditional interface wires need no frame bits.
- The missing 32 bottom-half clock-cascade definitions come from the pinned Artix table. All 2,804 existing Zynq definitions agree, all additions match Zynq's top-half table, and the bottom-half tile graphs match. This is corroborated database reuse, **not an independent measurement of those 32 locations**. No clock-frame addresses or timing estimates are copied from Artix.
- Every supplied non-ECC frame bit must survive assembly and decoding. This checks serialization, not whether every encoded resource implements its intended function. Ethernet routing separately checks LUT connectivity and emitted truth tables.

The [native results](../../../docs/artifacts.md#historical-reports) (`experiments/07-openxc7/results/native-gtx-2026-09-21.json`) record three completed images and their limits. Matching GTX settings does not qualify the whole native configuration, generated clocks, CDC constraints, analog channel or DAC. The native Ethernet routes still miss their partial 125-MHz targets.

## Regression and new configurations

CI checks overlay boundaries, donor disagreements, immutable reuse and substituted references without proprietary tools. To exercise the patched backend against a retained Ethernet route:

```sh
python3 gtx/check_backend.py --nextpnr "$ERL_HLS_NEXTPNR" \
  --chipdb build/gtx-probe/chipdb.bin \
  --stage build/ethernet-board/loopback --output build/backend-checks
```

Its 11 cases check default/explicit swing values, buffer controls, BASE/ADV clock retention and MMCM power-down polarity. Nondefault reference-buffer settings are inert writer tests, never board candidates.

For another GTX site or configuration, obtain independent evidence before extending the accepted scope. `gtx/reference.py` prepares six tile-location references and `vivado/refclk.py` four buffer references for a Vivado host. These unconnected primitives deliberately use X-Ray fuzzer DRC exemptions: **never program them or reuse those exemptions in a board build**. The retained references suffice for the current candidates; no running Vivado host is needed.

## Constant carry-head regression

`gtx/carry_head_fixture.v` keeps separate sum and carry consumers for constant-zero, constant-one and dynamic carry inputs (`MODE=0,1,2`). Preserve those explicit primitives: ordinary synthesis can fold away the topology that exercises this defect. Read Xilinx primitive declarations as a library, elaborate and flatten the fixture, and export only its top module with Yosys `write_json -selected`. Set `IOSTANDARD LVCMOS33` on each of its 14 named ports; the pinned nextpnr XDC parser does not expand `get_ports *`. No pin placement or clock constraint is needed for this pack-only check.

Run the patched backend with `--pack-only --write packed.json`, then `python3 gtx/check_carry_head.py --packed packed.json --mode MODE`. The auditor checks the actual relocated LUT's four Boolean assignments and rejects simultaneous external O/CO claims; it rejects inputs larger than 4 MiB. Each of the three patched cases must pass. Against the previous backend, the two constant cases must expose the head conflict while the dynamic case must pass. This finite packer witness does not establish whole-image equivalence, placement legality, timing or board behavior.

`python3 -m unittest test_carry_head` checks the auditor's acceptance and rejection cases without invoking native tools. The hardware-independent FSBL staging regression is `python3 -m unittest test_fsbl_staging`. The existing backend builder downloads pinned sources, builds historical variants and uses four compiler jobs; it is not the serial, offline campaign recipe. Run it only with an appropriate external resource budget.
