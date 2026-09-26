# Local Z-7030 timing models

Two opt-in experiments improve timing estimates for **xc7z030sbg485-1**: an XLS operation-delay estimator calibrated through native Yosys mapping, and BRAM endpoint timing for the native nextpnr backend. Neither qualifies a board clock. The [measurements](../results/xc7-timing-application-2026-09-26.md) include scheduling regressions and omitted timing checks.

XLS costs guide pipeline boundaries before mapping; native timing evaluates a placed/routed mapped circuit. These are different estimates. Operation costs cannot describe placement congestion or all DSP fusion. A native report can omit paths altogether. Require endpoint coverage before interpreting its MHz, then verify clocks, hard-block constraints, hold and I/O timing separately.

## Use the XLS estimator

Install into a dedicated XLS checkout; existing models and defaults stay unchanged. The tested revision is `20bf86d9c9e90f9df380a0280a5973ce0c33a59a`.

```sh
python3 experiments/07-openxc7/timing_model/install_xls.py /path/to/xls-checkout
# In that checkout, using its supported Bazel/compiler environment:
bazel build --dynamic_mode=off --copt=-g0 --host_copt=-g0 \
  //xls/tools:codegen_main //xls/estimators/delay_model/models:xc7_audit_main
```

Select the model explicitly when scheduling:

```sh
/path/to/codegen_main --delay_model=xc7_7030 \
  --xc7_delay_table="$PWD/experiments/07-openxc7/timing_model/xc7_7030.tsv" \
  --pipeline_stages=3 input.ir > output.v
```

The table contains picoseconds excluding launch-register clock-to-Q and capture setup. Costs include measured local routing by default; `--xc7_routed_delays=false` selects cell-only costs. Both interpolate a monotone envelope across measured payload widths and fan-ins. Index widths round up to a measured family that retains overflow/default decoding. The model reuses the smallest sample for smaller shapes and rejects upper extrapolation and unsupported operations. Pure wiring has zero intrinsic cost; its physical fan-out still matters after placement. The wide constant-multiply row applies only to its exact operand widths, result width and literal.

The estimates are **not upper bounds**. Report underestimates separately from overestimates; their cancellation in the mean is not evidence of safety. Pipeline placement also needs validation: overpricing one operation can leave another stage too crowded. The current model remains opt-in because both effects appear in the measurements. XLS may replace a detailed estimator error with its generic “No known delay model estimate” error.

Audit the **entire optimized package** before scheduling. The auditor calls the installed C++ estimator for every node, reports all missing shapes, and exits unsuccessfully if any are unsupported:

```sh
/path/to/xc7_audit_main --xc7_delay_table=/path/to/xc7_7030.tsv \
  application.opt.ir > coverage.tsv
```

Coverage includes full and partial binary selectors, one-hot/priority selectors, variadic bit operations, wide comparisons, variable shifts, and one-dimensional array reads/updates. Nested dynamic reads compose measured mux layers; multidimensional dynamic updates remain unsupported. Width, fan-in, and index width are independent dimensions. The table is the authority on measured limits; the auditor is the authority on whether a particular package qualifies.

For a model comparison, put the application's existing codegen options in a JSON array, without delay-model or output flags:

```sh
python3 experiments/07-openxc7/timing_model/application.py \
  --ir application.opt.ir --table /path/to/xc7_7030.tsv \
  --codegen /path/to/codegen_main --audit /path/to/xc7_audit_main \
  --options codegen-options.json --stage _build/application-timing
```

This retains the audited IR, table, tool hashes, commands, both RTL outputs, and per-proc schedules at identical stage-count/II options. The compiler/profile tools also accept `--delay-model xc7_7030 --delay-table PATH`; the table is copied into their build artifacts and its content hash invalidates codegen caches.

**A complete package schedule is not timing analysis of the assembled RTL.** Proc I/O has zero scheduler cost, as in XLS's standard technology estimators. Generated FIFO ready/valid logic, RAM adapters, cross-proc combinational chains, clock networks, and global placement require mapped timing analysis. Wiring likewise has no intrinsic operation cost, but its physical fan-out is not free.

For a concise selection inventory before planning more measurements:

```sh
python3 experiments/07-openxc7/timing_model/selection_shapes.py input.opt.ir \
  --output selection-shapes.json
python3 experiments/07-openxc7/timing_model/test_selection_shapes.py
```

The inventory groups flattened result widths, case counts and selector widths, with source locations and input/table hashes. Review flags identify dimensions absent from the calibration corpus. They neither estimate delays nor qualify coverage: other operations, operand constraints and physical wiring require separate checks. Unsupported selection syntax fails explicitly.

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

Python 3.10+, native XLS/Yosys, Icarus and Vivado 2024.2 are required for a complete campaign. Only the Vivado phase needs the vendor host; fitting, scheduling and native routing remain local. Use fresh output directories.

1. Run `characterize.py --codegen BIN --yosys BIN --stage CORPUS`. Widths 4, 8, 16, 32 and 64 train the model; width 24 is held out. The constant-multiply probe is a separate corpus: `--ops smul_const_37_39_76_183251937963 --widths 76`.
2. The [application campaign plan](../results/xc7-timing-model-2026-09-26-plan.json) includes the original arithmetic grid and its wider application neighborhood. Replay it with `expand.py --plan PATH --stage CORPUS --codegen BIN --yosys BIN`. Use `expand.py --plan-only --stage PLAN` to inspect the broader width/fan-in/index grid. `--plan PLAN/plan.json` replays that exact grid; `--existing-table TABLE` explicitly omits already-measured training shapes. Supply `--codegen BIN --yosys BIN` to prepare the mapped probes. Preparation resumes only when input and tool fingerprints still match.
3. Transfer each corpus plus `batch.py`, `measure.tcl`, `circuit_audit.tcl` and `connectivity.py` to the Vivado host. Source Vivado's settings, then run `env -u PYTHONHOME -u PYTHONPATH python3 batch.py CORPUS measure.tcl --timeout 900`. Two workers and a three-minute timeout are defaults; large selectors need longer. Successful unchanged cases resume; failed or changed cases require a fresh output directory. `collect.py CORPUS results.tar.gz` exports completed evidence without checkpoints.
4. Unpack locally and run `analyze.py CORPUS CALIBRATION --extra-corpus CONSTANT_CORPUS`. It requires full internal timing coverage, routed nets, unchanged primitive parameters and identical pin connectivity. `xc7_7030.tsv` excludes held-out measurements. Both pre-route and post-route graph audits are mandatory; older archives with only the import audit need their retained checkpoints rechecked or the circuits rerun. Separate `--extra-corpus` arguments can combine operation batches.
5. Run `validate.py` and `validate_kernel.py` with explicit `--stage`, `--codegen`, `--table`, `--yosys`, `--iverilog` and `--vvp` paths. Both compare models at identical latency and II and check streamed RTL results. Measure these mapped corpora with the same Vivado batch tool.
6. `hard_blocks.py STAGE YOSYS` prepares the primitive fixtures. `ram_modes.py --help` describes extraction of actual RAM configurations from a mapped application. Add `hard_blocks.py STAGE YOSYS --extended` for DSP input/M/P register combinations and variable-address SRL16E/SRLC32E. These measurements supply future model work; collecting an arc does not enable that mode in native nextpnr. Measure them with the same import/coverage checks. `sdf.py` extracts instance-specific primitive arcs; `hard-clock-constraints.rpt` retains separate minimum-period and pulse-width requirements; `report.py --help` describes compact evidence export.

To time an already mapped application, run `prepare_application.py MAPPED_JSON STAGE --top TOP --yosys BIN`, then pass its `mapped.edf` to `measure.tcl`. The mapped top must contain a `clock` input and registered internal paths. External I/O paths are deliberately excluded. The importer records removal of source-scope metadata and explicit choices for unspecified INIT/SRVAL bits, including LUT don't-care entries; it does not prove behavior for originally unspecified states.

The importer preserves Yosys's mapped cells and uses `write_edif -pvector bra`. Placement-time logic replication and clock-buffer insertion are disabled, and the pin graph and explicit primitive parameters are checked both before and after routing. A pin-graph audit catches reversed bus bits; a parameter audit catches changed DSP register modes and LUT truth tables. The only import exceptions are the exact INV-to-LUT1 alias and absent controls for provably bypassed DSP registers. Explicitly wired controls remain checked. Streaming arithmetic probes define otherwise unspecified startup bits; their contract begins after pipeline fill.

Run the fast local regressions and optional installed-tool checks:

```sh
python3 experiments/07-openxc7/timing_model/test_model.py
python3 experiments/07-openxc7/timing_model/test_estimator.py \
  --auditor /path/to/xc7_audit_main --table /path/to/xc7_7030.tsv \
  --plan /path/to/plan.json --stage _build/estimator-consistency
python3 experiments/07-openxc7/timing_model/test_codegen.py \
  /path/to/codegen_main experiments/07-openxc7/timing_model/xc7_7030.tsv
```

Retain raw reports/SDF, mapped inputs, manifests and tool fingerprints. Checkpoints and duplicate intermediate netlists can be removed once those records are complete. No new CI job or automatic vendor measurement is enabled.

## Retargeting

The current scripts retain Z-7030 assumptions; changing a part name alone is insufficient. The [retargeting plan](../yap/timing-model/retargeting.md) outlines target profiles, resumable campaigns, generated model data and qualification on a second target.
