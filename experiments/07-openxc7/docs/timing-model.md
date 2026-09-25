# Local Z-7030 timing models

Two opt-in experiments improve timing estimates for **xc7z030sbg485-1**: an XLS operation-delay estimator calibrated through native Yosys mapping, and BRAM endpoint timing for the native nextpnr backend. Neither qualifies a board clock. The [measurements](../results/xc7-timing-model-2026-09-25.md) include scheduling regressions and omitted timing checks.

XLS costs guide pipeline boundaries before mapping; native timing evaluates a placed/routed mapped circuit. These are different estimates. Operation costs cannot describe placement congestion or all DSP fusion. A native report can omit paths altogether. Require endpoint coverage before interpreting its MHz, then verify clocks, hard-block constraints, hold and I/O timing separately.

## Use the XLS estimator

Install into a dedicated XLS checkout; existing models and defaults stay unchanged. The tested revision is `20bf86d9c9e90f9df380a0280a5973ce0c33a59a`.

```sh
python3 experiments/07-openxc7/timing_model/install_xls.py /path/to/xls-checkout
# In that checkout, using its supported Bazel/compiler environment:
bazel build --dynamic_mode=off --copt=-g0 --host_copt=-g0 //xls/tools:codegen_main
```

Select the model explicitly when scheduling:

```sh
/path/to/codegen_main --delay_model=xc7_7030 \
  --xc7_delay_table="$PWD/experiments/07-openxc7/timing_model/xc7_7030.tsv" \
  --pipeline_stages=3 input.ir > output.v
```

The table contains picoseconds excluding launch-register clock-to-Q and capture setup. Costs include measured local routing by default; `--xc7_routed_delays=false` selects cell-only costs. Both interpolate a monotone envelope between sampled widths, conservatively reuse the smallest sample below its width, and reject larger widths, unsupported operations and unsupported fan-ins. Pure wiring has zero intrinsic cost; its physical fan-out still matters after placement. The wide constant-multiply row applies only to its exact operand widths, result width and literal.

The estimates are **not upper bounds**. Report underestimates separately from overestimates; their cancellation in the mean is not evidence of safety. Pipeline placement also needs validation: overpricing one operation can leave another stage too crowded. The current model remains opt-in because both effects appear in the measurements. XLS may replace a detailed estimator error with its generic “No known delay model estimate” error.

## Use the native BRAM model

Prepare the [native endpoint-audit tools](../timing_coverage/README.md), retain `nextpnr-coverage` as the baseline, and apply the model to that dedicated source checkout:

```sh
python3 experiments/07-openxc7/timing_model/install_native.py /path/to/nextpnr-source
cmake --build /path/to/native-build -j 4
ctest --test-dir /path/to/native-build --output-on-failure
# Retain this new binary separately as nextpnr-calibrated.
```

Only the exact Z-7030 part and measured READ_FIRST modes qualify: RAMB18 SDP at width 36, RAMB36 SDP at width 72, and RAMB36 TDP with a 36-bit A write port/B read port, each with the measured output-register choices. ECC, cascades, inverted clocks and other widths/modes remain uncovered. Clock-to-output and setup/hold estimates use worst captured primitive arcs. They do not establish internal period/pulse-width constraints or hold closure.

```sh
python3 experiments/07-openxc7/timing_model/compare_native.py \
  --baseline /path/to/nextpnr-coverage --calibrated /path/to/nextpnr-calibrated \
  --yosys /path/to/yosys --chipdb /path/to/xc7z030sbg485.bin \
  --stage _build/timing-comparison
```

This checks six fixtures with unchanged logic/DSP behavior and restored RAM endpoints. `--application-ram CORPUS` adds the four SDP fixtures prepared by `ram_modes.py`. Registered DSP endpoints remain unsupported; their optimistic MHz must still be rejected by the coverage audit. The experiment does not change Yosys's ABC9 mapping library.

## Reproduce measurements

Python 3.11+, native XLS/Yosys, Icarus and Vivado 2024.2 are required for a complete campaign. Only the Vivado phase needs the vendor host; fitting, scheduling and native routing remain local. Use fresh output directories.

1. Run `characterize.py --codegen BIN --yosys BIN --stage CORPUS`. Widths 4, 8, 16, 32 and 64 train the model; width 24 is held out. The constant-multiply probe is a separate corpus: `--ops smul_const_37_39_76_183251937963 --widths 76`.
2. Transfer each corpus plus `batch.py`, `measure.tcl` and `connectivity.py` to the Vivado host. Source Vivado's settings, then run `env -u PYTHONHOME -u PYTHONPATH python3 batch.py CORPUS measure.tcl`. It uses two workers by default with a three-minute limit per probe. `collect.py CORPUS results.tar.gz` exports completed evidence without checkpoints.
3. Unpack locally and run `analyze.py CORPUS CALIBRATION --extra-corpus CONSTANT_CORPUS`. It requires full internal timing coverage, routed nets, unchanged primitive parameters and identical pin connectivity. `xc7_7030.tsv` excludes held-out measurements. Separate `--extra-corpus` arguments can combine operation batches.
4. Run `validate.py` and `validate_kernel.py` with explicit `--stage`, `--codegen`, `--table`, `--yosys`, `--iverilog` and `--vvp` paths. Both compare models at identical latency and II and check streamed RTL results. Measure these mapped corpora with the same Vivado batch tool.
5. `hard_blocks.py STAGE YOSYS` prepares the primitive fixtures. `ram_modes.py --help` describes extraction of actual RAM configurations from a mapped application. Measure them with the same import/coverage checks. `sdf.py` extracts instance-specific primitive arcs; `report.py --help` describes compact evidence export.

The importer preserves Yosys's mapped cells and uses `write_edif -pvector bra`. A pin-graph audit catches reversed bus bits; a parameter audit catches changed DSP register modes and LUT truth tables. The only import exceptions are the exact INV-to-LUT1 alias and absent controls for provably bypassed DSP registers. Explicitly wired controls remain checked. Timing probes define otherwise unspecified startup bits; their streaming contract begins after pipeline fill.

Run the fast local regressions and optional installed-tool checks:

```sh
python3 experiments/07-openxc7/timing_model/test_model.py
python3 experiments/07-openxc7/timing_model/test_codegen.py \
  /path/to/codegen_main experiments/07-openxc7/timing_model/xc7_7030.tsv
```

Retain raw reports/SDF, mapped inputs, manifests and tool fingerprints. Checkpoints and duplicate intermediate netlists can be removed once those records are complete. No new CI job or automatic vendor measurement is enabled.

## Retargeting

The current scripts retain Z-7030 assumptions; changing a part name alone is insufficient. The [retargeting plan](../yap/timing-model/retargeting.md) outlines target profiles, resumable campaigns, generated model data and qualification on a second target.
