# Native timing endpoint audit

Check timing coverage before comparing clock estimates. This probe exports **the running backend's** port classifications and clock associations; it does not infer support from primitive names. A required register port classified as `ignore`, lacking a recognized clock, absent, or unplaced fails the audit. Passing is necessary, not sufficient: combinational arcs, delay accuracy, clock relationships, hold and I/O constraints still need qualification.

The pinned XC7 backend omits BRAM endpoints and registered DSPs. The [measured corpus](../results/native-timing-coverage-2026-09-24.md) demonstrates how these omissions hide paths. No new clock frequency is qualified by this experiment.

## Build and measure

Use the native compiler, CMake, Homebrew Boost and the [prepared Z-7030 database](../zynq7030.md). Both binaries include the existing LUT correctness patches; only the second adds `--timing-coverage`. Neither replaces the installed tools. The optional archive cache avoids downloads.

From the repository root:

```sh
bash experiments/07-openxc7/timing_coverage/build.sh \
  "$PWD/_build/timing-tools" \
  /path/to/existing/lut-legality-build

python3 experiments/07-openxc7/timing_coverage/run.py \
  --baseline _build/timing-tools/bin/nextpnr-baseline \
  --nextpnr _build/timing-tools/bin/nextpnr-coverage \
  --yosys /path/to/oss-cad-suite/bin/yosys \
  --chipdb /path/to/chipdb/xc7z030sbg485.bin \
  --stage _build/timing-probes
```

Each output directory must be new. Six small circuits use one seed each, with a 120-second limit per mapping/routing phase. The runner checks primitive/register modes, identical programmed FASM features and identical detailed timing paths with and without the observer. It retains tool/input/artifact hashes, raw reports and failed attempts. `status: complete` means the experiment finished; inspect `endpoint_requirements_met` separately. Failed endpoint coverage is expected for several pinned-backend probes.

## Audit another circuit

Add `--timing-coverage coverage.json` to a native placement/routing command. Audit the completed placement; pack-only exports can classify unplaced carry cells as ignored. Declare the required endpoints independently, for example:

```json
[
  {"type": "RAMB36E1_RAMB36E1", "port": "DOBDO[0-9]+", "class": "register_output"}
]
```

```sh
python3 experiments/07-openxc7/timing_coverage/check.py \
  coverage.json requirements.json --output audit.json
```

The checker exits nonzero when a requirement fails. Selectors are full regular-expression matches. The export includes connected ports, including tied inputs and unused output nets; counts are not counts of sensitizable paths. Requirements express necessary endpoints, not a complete timing specification.

A candidate that moves registers into a DSP must establish its new setup/hold and clock-to-output paths before its reported MHz can support an improvement. Keeping the same excluded primitive count is also insufficient: an optimization can change the unmeasured logic between those boundaries.

Fast checker tests run through `test_phi_timing.py` in the existing CI job. Native builds/routes remain opt-in.
