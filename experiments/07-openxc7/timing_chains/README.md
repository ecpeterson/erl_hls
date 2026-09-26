# Arithmetic and control timing probes

These local experiments compare covered register-to-register paths on the Zynq-7030 database. They do not qualify a board clock. The calibrated backend restores selected exact-part RAM boundaries; registered-DSP, SRL and internal timing constraints remain incomplete. The older pinned backend also omits RAM boundaries. See [the coverage audit](../timing_coverage/README.md) and [the measured campaign](../results/timing-chains-2026-09-24.md).

## Arithmetic

`probe.py` places a DSLX `main` between preserved fabric registers. Supply vector inputs, one vector result, and a fresh stage. `--stages 2` measures the existing two-stage schedule; omitting it measures the whole combinational function. `--no-dsp` avoids the native model's misleading DSP cascade delays. The runner fingerprints sources, the standard library, tools and outputs, checks clock-boundary coverage, and rejects changing inputs or RAM/SRL mappings.

For the bulk recurrence, prepare one directory containing `phi_field.x`, `hls_fixed.x`, `hls_vec.x`, and this `bulk.x`:

```rust
import phi_field;
pub fn main(a: s32, b: s32, sum: sN[34]) -> s32 {
  phi_field::relax_bulk(a, b, sum as s64)
}
```

With native XLS/Yosys, the coverage-enabled nextpnr from the audit, and the checked `xc7z030sbg485.bin` database:

```sh
python3 experiments/07-openxc7/timing_chains/probe.py \
  --source "$SOURCES/bulk.x" --stage "$STAGE/seed-1" \
  --xls "$XLS" --yosys "$YOSYS" --nextpnr "$NEXTPNR" --chipdb "$CHIPDB" \
  --no-dsp --stages 2 --seed 1
```

Use matched sources/tools/constraints for each comparison. Start with one seed; check promising or ambiguous candidates across a few seeds. These small probes identify arithmetic changes, while the complete decoder simulation checks step throughput and the full core reveals control/routing limits.

## Exact rounded division

For signed width W and a positive non-power-of-two divisor D, choose K = W + ceil(log2 D) and M = ceil(2^K/D). Then `floor((n*M + 2^(K-1))/2^K)` rounds n/D to nearest with ties away from zero.

The positive reciprocal error times any representable n has magnitude strictly below 1/(2D). A non-tie is at least that far from a half integer, so its rounding cannot change. Positive ties round upward; negative ties move just below the half integer and round downward. Power-of-two divisors have zero reciprocal error and use the separate widened signed-bias path. The DSLX product is wide enough to avoid overflow.

```sh
python3 experiments/07-openxc7/timing_chains/prove_rounding.py \
  --z3 "$Z3" --output "$STAGE/rounding-proofs.json"
```

The solver checks the integer identity for every input at 110 width/divisor combinations, plus the four-neighbor bulk range bound. Deliberately rounding the reciprocal downward or allowing a fifth neighbor must produce counterexamples. This proves arithmetic identities, not compiler correctness; the DSLX interpreter/JIT properties and full RTL comparisons provide separate checks. Removing bulk saturation was measured and rejected because it worsened the two-stage schedule.

## Queue banks

The [queue-bank comparison](../results/control-queues-2026-09-25.md) retains the exact two- and nine-queue DSLX probes. Prepare separate source directories containing `bank2.x`/`bank9.x`, `axis.x`, and each version of `frame_queue.x`. The reference library is available at `97b6bf9`; the candidate is the retained `queue-local.patch` applied to a copy of that library. Run `probe.py` above with `--source "$SOURCES/bank2.x"`, omit `--stages` for the combinational bank transition, and use matched seeds 1/2 for both versions. Repeat with `bank9.x`.

The probe preserves all state/payload bits between fabric registers; its resource totals include those registers and the activity harness. It is separate from the complete decoder's area and throughput measurements. Check behavior with the compiled-RTL proof, which exhaustively compares the indexed reference and the selected candidate update for 1/2/3/9 queues:

```sh
python3 experiments/07-openxc7/timing_chains/prove_frame_queue.py "$XLS" \
  --yosys "$YOSYS" --library "$SOURCES"
```

Rejected variants remain reproducible without changing the compiler library. Copy the reference libraries into a fresh directory, then apply the recorded patches with `patch -d "$SOURCES" -p1`: `queue-local.patch` starts from `97b6bf9`; `queue-unconditional.patch` applies on top of it; `retirement-local.patch` starts from the reference mailbox. The exact `bank2.x`, `bank9.x` and `retire2.x` probes use those libraries. Preserve the ordinary `axis.x` and mailbox dependencies from the same reference revision.

`unconditional-proof.x` compares validity and live payloads for two queues; `retirement-proof.x` compares complete metadata for two actors/four entries. Compile each proof as combinational `main`, then run Yosys `read_verilog -sv`, `prep -top bank -flatten`, `opt`, and `sat -verify -prove out 1 -set-def-inputs`, using `--module_name=bank` at codegen. Enabled actor/queue addresses must be in range; disabled addresses are unrestricted. The bank proof runner additionally covers 1/2/3/9 queues with exact payload comparison.

## Selective registered-boundary screen

The [handoff experiment](../results/control-queues-2026-09-25/handoff-screen.json) records the exact two channel lines before/after editing, its input/output IR hashes, unchanged codegen flags and interface-trace summaries. Start from a separately compiled four-phi profile with the local queue update. Copy its optimized IR and replace only those exact lines; fail if either input line is absent or repeated. Reuse its recorded codegen command in a separate directory and retain a new manifest with the changed IR/RTL hashes. Never edit a published compiler-cache entry in place.

Run the profile testbench with width 2, height 1, both planes and `STALL_OUTPUTS=0/1`; compare accepted frames per actor against the unchanged profile. The existing `phi_profile_trace.c` profiler uses `ERL_HLS_PHI_PROFILE_SHARDS=1` and `ERL_HLS_PHI_PROFILE_PLANE_COUNT=2` here. Then map/route through the complete-core procedure below. Compare **period × cycles/step**; a lower clock period alone can conceal a slower decoder.

For a deliberately optimistic DSP sensitivity check, the [recorded edit](../results/control-queues-2026-09-25/dsp-sensitivity.json) changes only the fully combinational DSP branch of native `getCellDelay` to return zero propagation delay. Keep timing classes and connectivity intact; build a separate diagnostic binary, restore the source, and replay saved placements with `--no-pack --no-place --no-route --diagnostic-timing-paths`. This bounds the influence of those arc costs on the fixed native timing graph. It does not predict another placement, qualify missing paths or supply a usable timing model.

## Control fan-out

`replicate.py` copies combinational LUT drivers and partitions their consumers without inserting state or changing latency:

```sh
python3 experiments/07-openxc7/timing_chains/replicate.py mapped.json \
  --output replicated.json --limit 64
```

The input must have one flattened top and no combinational loops. Fixed-location LUTs and clock/reset consumers are excluded. The verification substitutes each replica output with its original wire and requires exact recovery of every original cell, parameter, port and attribute. One pass can increase upstream fan-out; the consumer limit is not a global fan-out guarantee. Route the separate output with the same harness, device, constraints and seed. This remains an experiment rather than a synthesis default.

## Reusing placement

Generate and map the complete four-phi/D3 workloads with [the profile timing guide](../phi-timing.md), selecting `--part xc7z030sbg485-1`. The retained mapping manifests record source digests and exact synthesis scripts. Use the coverage-enabled native binary for the routing commands below.

For expensive full cores, retain a placement checkpoint before routing:

```sh
"$NEXTPNR" --chipdb "$CHIPDB" --json mapped.json --xdc timing.xdc \
  --seed 1 --freq 25 --no-route --write placed.json --log place.log
"$NEXTPNR" --chipdb "$CHIPDB" --json placed.json --seed 1 --freq 25 \
  --no-pack --no-place --router router2 --timing-allow-fail \
  --report timing.json --timing-coverage coverage.json --log route.log
```

The XDC must contain the same target period (40 ns here); `--freq` does not override an existing clock constraint. Replay retains placement and clock constraints but restarts the router RNG, so it need not reproduce a single uninterrupted run. Record both commands and input digests. Placement-only estimates and interrupted routes are not completed routed timing results.

For cheaper diagnosis, install the optional path reporter into the dedicated pinned nextpnr source tree and rebuild a **separate** binary:

```sh
python3 experiments/07-openxc7/timing_chains/install_path_report.py "$NEXTPNR_SOURCE"
cmake --build "$NEXTPNR_BUILD" --target nextpnr-xilinx -j2
"$NEXTPNR_DIAGNOSTIC" --chipdb "$CHIPDB" --json placed.json \
  --no-pack --no-place --no-route --diagnostic-timing-paths \
  --report placement-estimate.json --timing-coverage placement-coverage.json \
  --log placement-paths.log
```

The installer is idempotent and rejects an unexpected command-driver layout. It adds an opt-in report after the selected flow stages; normal runs are unchanged. Saved-placement paths use estimated interconnect, can differ from routed paths, and must remain labeled **unrouted estimates**. Use them to locate candidate boundaries, then verify the chosen change by routing. Fingerprint this binary separately and never replace a binary while a measurement using it is active.

Render the retained arithmetic/control comparison with Matplotlib: `python3 experiments/07-openxc7/timing_chains/plot.py experiments/07-openxc7/results/timing-chains-2026-09-24`.

## Materialized XLS FIFOs

`fifo_experiment.py` replaces selected FIFO module definitions in retained application RTL. It requires identical port names/directions/widths and verifies that every non-FIFO module remains byte-identical. This isolates FIFO implementation changes from incidental codegen naming differences. Its manifest is an explicit derived experiment, never a compiler-cache entry.

Supply `--reference COMPILED_DIRECTORY --generated CANDIDATE_RTL --compiler CANDIDATE_CODEGEN --patch SOURCE_PATCH --stage FRESH_DIRECTORY`. Optional `--depth 1 --payload-bits 424` restrict replacement. The comparison checks both planes for 12,000 cycles, long output stalls and reset, requiring cycle-exact valid outputs and payloads. The resulting directory can be mapped with `phi_timing.py`.

`fifo_probe.py` measures one matching FIFO between preserved stimulus/capture registers: supply `--rtl RTL --yosys BIN --nextpnr BIN --chipdb BIN --stage FRESH_DIRECTORY`, optionally `--width`, `--depth` and `--seed`. Counts include the harness. It checks register timing coverage and rejects unexpected hard primitives. These isolated native paths do not establish whole-application timing; use the complete-core comparison before claiming a step-rate improvement.

`prove_fifo.py --baseline RTL --candidate RTL --yosys BIN --stage FRESH_DIRECTORY` exhaustively checks the selected 424-bit, depth-one FIFO over twelve symbolic cycles. The first cycle resets it; later data, readiness, validity and resets are unrestricted. Both handshakes and every valid payload must match. This bounded check complements the independent XLS FIFO interpreter tests; it is not an unbounded equivalence proof.

Apply one of the [recorded FIFO patches](../results/fifo-storage-2026-09-26.md) to a separate checkout of XLS `20bf86d9c9e90f9df380a0280a5973ce0c33a59a`, then build `//xls/tools:codegen_main` and test `//xls/codegen:maybe_materialize_fifos_pass_test`. For calibrated schedules, install the XC7 estimator first using the [timing-model instructions](../docs/timing-model.md). Freeze each binary before building another variant. Reuse the baseline optimized IR and recorded codegen flags, then pass that generated RTL to `fifo_experiment.py`; do not replace non-FIFO application logic. The report retains compiler, patch, baseline, netlist and testbench hashes.
