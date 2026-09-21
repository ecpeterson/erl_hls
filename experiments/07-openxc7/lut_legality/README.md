# XC7 LUT placement regression

Two experimental patches for pinned nextpnr-xilinx `68aeeb39` preserve usable O5 placements and correct truth-table generation when physical inputs share several logical names. They are isolated from the installed toolchain. See the [measurement report](../results/lut-legality-2026-09-21.md) for evidence and limits.

A physical XC7 LUT has an O6 output and an O5 output sharing five inputs. A single-output logical LUT may occupy either half if its input requirements and its neighbors permit it. The packer initially names its output `O6`; after choosing an O5 placement, nextpnr must rename that output and preserve the logical function through input permutation.

- `nextpnr-output-pin.patch` makes the XC7 candidate/repair check accept the provisional `O6` name. Connected sixth inputs, two-output cells, memory restrictions and fixed placements retain their existing checks. Non-XC7 candidate checks are unchanged.
- `nextpnr-pin-origins.patch` joins nonempty input-origin strings with separators. It locally adapts upstream [2d3005e](https://github.com/openXC7/nextpnr-xilinx/commit/2d3005e755a2b1009f434efdb5acf2103ffe4d92), adding empty-origin filtering. The previous join could produce `I4I2` and empty tokens; FASM generation interpreted unknown names as input zero, producing wrong LUT contents. This shared code change is tested here on XC7 only.

Upstream also hardened its FASM reader in [7cfd1e9](https://github.com/openXC7/nextpnr-xilinx/commit/7cfd1e90682370accd00f63fcf7c16c5bcd24007). These local patches isolate the measured changes on our older pin; they are not a substitute for qualifying an updated toolchain. The output-name restriction is still present in upstream `4524cbd` (September 20).

## Build and compare

On Apple Silicon, install the command-line compiler, CMake, pkg-config and Homebrew Boost. Eigen and nextpnr are downloaded into a **new** build directory and checked against pinned SHA-256 digests. The build uses four jobs, no GUI/Python binding and no OpenMP. It does not build LLVM or require a VM.

From `experiments/07-openxc7`:

```sh
./lut_legality/build.sh "$PWD/build/lut-legality"
python3 test_lut_legality.py \
  --baseline build/lut-legality/bin/nextpnr-baseline \
  --candidate build/lut-legality/bin/nextpnr-candidate \
  --yosys .apio/packages/oss-cad-suite/bin/yosys \
  --chipdb build/chipdb/xc7z030sbg485.bin \
  --tilegrid .apio/packages/openxc7/share/nextpnr/external/prjxray-db/zynq7/xc7z030/tilegrid.json \
  --stage build/lut-legality/probe
```

Prepare the [exact-part database](../zynq7030.md) first. Each mapping, pack and route phase has a 60-second limit; every fixture uses seed 1. `--fixtures fixed tied` selects a subset. The JSON report retains hashes, repair counts, completed-route artifacts and checker results. A failing phase aborts with its logs retained. The unchanged baseline is required to reproduce the known tied-input truth-table failure; every candidate must pass.

The intermediate `nextpnr-placement-only` binary applies only the first patch. Use it as `--baseline` with `--fixtures tied` to isolate the second fix. All three binaries retain the same CMake version label to avoid rebuilding unrelated objects; their SHA-256 hashes, not that label, identify them.

## What is checked

The fixtures cover five- and six-input LUTs, split dual-output LUTs, carry helpers, RAM32X1D, SRLC32E and an explicitly pinned O5/O6 pair. Asymmetric truth tables expose input-order mistakes. The checker compares packed net identities with physical pin assignments and enumerates every reachable combinational truth-table row against the emitted FASM INIT bits. Its expected function comes from the packed inputs, independently of the router's final input-origin annotations.

Placement checks cover output-pin choice, shared input agreement, imported BEL retention and SLICEM use for RAM/SRL cells. RAM/SRL checks preserve connectivity and parameters; they are **not** sequential memory proofs. The pinned router sometimes drops a constant memory-pin origin: the checker accepts this only when the same physical pin remains tied to the same constant, and reports the count. Combinational constant-input origins may likewise disappear; acceptance requires a retained physical constant and the full independent function check. An unattributed shared A6=VCC on an O5 cell does not suppress its lower-half truth checks.

Run the portable checker tests directly, or through the existing CI entry point:

```sh
python3 lut_legality/test_check.py
python3 test_phi_timing.py
```

These checks do not prove route connectivity, bitstream encoding or silicon timing. The native CTest suite supplies additional backend unit coverage; no physical board has been programmed with either patch.
