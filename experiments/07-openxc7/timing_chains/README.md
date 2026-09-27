# Arithmetic and control timing probes

These local experiments compare covered register-to-register paths on the Zynq-7030 database. They do not qualify a board clock. The calibrated backend restores selected exact-part RAM boundaries; registered-DSP, SRL and internal timing constraints remain incomplete. The older pinned backend also omits RAM boundaries. See [the coverage audit](../timing_coverage/README.md) and [the measured campaign](../results/timing-chains-2026-09-24.md).

## Combined timing report

Use `path_report.py` after each completed physical run. It combines saved path reports, XLS stages/source locations and measured cycles per step; it does not invoke compilation or placement. The same manifest produces JSON for analysis and Markdown for review:

```sh
python3 experiments/07-openxc7/timing_chains/path_report.py MANIFEST.json \
  --artifacts "$EVIDENCE" --output "$REPORT"
```

Use `--full-json` when individual arc/source records are needed; the default JSON retains summaries, schedules and input fingerprints. The [retained manifest](../results/timing-paths-2026-09-27-manifest.json) is an example. Its compressed inputs are committed, so `--artifacts experiments/07-openxc7/results` reproduces that report without XLS, Vivado or local build caches. Each run names its tool, completed stage, requested period and path artifact. An artifact contains a relative `path`, optional tar `member`, and `sha256`; a hash mismatch aborts. Record cycles through `cycle_evidence` and `cycle_pointer`, rather than copying a number without its witness. Optional `path_sets` maps query labels to additional artifacts; identical paths are deduplicated. Optional `netlist` adds physical aliases and per-bit sink counts; `block_ir` adds source attribution; `scheduled_ir`, `schedule` and `process_pattern` add stage/dependency evidence. `architecture_schedule.py` retains both IR forms and requires replayed RTL to be byte-identical. Source attribution deliberately leaves unmatched paths unknown.

The report separates logic/interconnect, groups the available path families, and calculates the period needed to offset added cycles. The “untouched sample floor” is the worst *reported* path outside a group, assuming it is unchanged. It does not predict placement or reveal missing families. Vendor input must contain single-clock, single-cycle setup paths; truncated arcs and incompatible clock relations fail. Native text retains its 0.1 ns precision. Keep different tools, constraints and mapping policies separate.

Before an experiment, record the affected family, expected structural change, allowed cycle/area cost and rejection criterion in `yap/`. First check schedules and behavior; then map, audit timing coverage and route a matched pair. Keep failed hypotheses alongside successful ones. The vendor runner retains global, RAM-source, DSP-through and FF-control samples separately; global top-N paths alone can hide a neighboring limit. Use **period × measured cycles/step** to select a candidate, and confirm promising results with another seed.

For a control-pipeline change, also run `control_frontier.py CORE.json --output FRONTIER.json`. From each executor-result occupancy launch, it follows every reachable register/RAM input and records external or unsupported boundaries. `--launch REGEX` selects other scalar launch signals; add newly introduced control registers when evaluating a cut. All endpoint totals and maxima are computed before `--limit N` caps displayed representatives per category. Unknown primitives remain uncovered; top outputs have no implied downstream timing constraint. Conservative primitive levels are not sensitizable paths or delays. This supplements `control_cones.py`'s named-intermediate comparisons: deleting an old endpoint cannot establish success while a new enable holds the same long chain. The [pipeline plan](../yap/scheduler-pipeline-plan.md) defines ownership and the next two cuts.

## Executor input arrival

`executor_arrival.py` reschedules one stateless executor while keeping its ports, two requested stages, II=1 and all surrounding RTL. Supply `--reference COMPILED --stage FRESH --codegen BIN --table TSV --delay-ps 3000`; optional `--cell-only` changes the scheduling estimator. The allowance applies only to the receive channel (`--channel`, default `_request_in`). `--symmetric` is a control for XLS's generic input-delay option, which also penalizes the opposite channel direction.

Validate against the original prepared oracle with `architecture_validate.py FRESH PREPARED --cycle-exact --reference-rtl COMPILED`, then map with `phi_timing.py`. Retiming may let Yosys pack registers into DSPs. The native physical runner rejects those unsupported modes before placement; `--keep-product-inputs` preserves direct multiply-operand registers in fabric for a separate coverage-safe experiment. Retain the normally packed version for vendor evaluation: preserving registers changes the physical optimization space.

## Indexed-selector lowering

`selector_experiment.py --stage FRESH --codegen BIN --yosys BIN` proves and maps flat/default versus balanced binary selectors at 63/65/127 cases, 24-bit payloads and an 8-bit index. Dimensions are configurable. The SAT miter permits arbitrary payloads, indices and default values, including every out-of-range index. Counts include the preserved stimulus/capture registers. Structural depth is a conservative graph measure, not a delay prediction.

Route a mapped variant with `architecture_physical.py --stage MAPPED --nextpnr BIN --chipdb BIN --frequency 200 --seed 1`; repeat promising pairs with seed 2. `--frequency` sets both the XDC and native target in MHz (default 25). For vendor robustness controls, `timing_model/batch.py` accepts `--period 5 --placement Explore` on a fresh corpus. Compare matched directives; these deterministic strategies are not random seeds. A binary selector result does not establish an improvement for priority selection or for an application lacking that selector shape.

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

`staged_reciprocal.py --stage FRESH --xls XLS --yosys YOSYS` compares the existing signed-37 divide-by-twelve with explicit product/recombination/quotient register boundaries. It compiles separate DSLX stage functions, checks both generated and mapped RTL against independent integer rounding under stalls/reset, and retains resource counts and the longest serial DSP chain. Both wrappers have three enabled cycles of latency and II=1; the reference only delays its whole combinational result. This is a cut-placement control, not a comparison against an optimally scheduled three-stage executor. `-nosrl` matches the complete-core flow.

The candidate keeps its cuts in fabric using `xilinx_dsp.multonly`; the reference keeps ordinary DSP mapping. `--pack-candidate-registers` diagnoses register absorption instead, but still requires mapped simulation to pass. The retained failure reproduces without the arithmetic recombination, so it must be resolved before promoting the packed candidate.

After a successful screen, `staged_reciprocal_native.py --source SCREEN --stage FRESH --yosys YOSYS --nextpnr NEXTPNR --chipdb CHIPDB [--seed 1]` routes both variants through the existing coverage-checked physical workflow at a 5 ns target. It rejects registered DSPs and preserves identical launch/capture boundaries. The `vendor/` corpus also works with `timing_model/batch.py CORPUS timing_model/measure.tcl --period 5 --placement Default`. The isolated divider omits numerator preparation, saturation, actor state, queues and publication; its latency/resource counts must not be presented as whole-application step performance.

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

## Small-core architecture controls

`architecture.py` derives one experiment from a prepared two-plane, 2×1 profile bundle (including `compiled/*.command.json` and `oracle.json`). It rejects a different geometry or an unexpected source pattern. Use the calibrated model and frozen compact-FIFO compiler from the preceding experiment; this does not change compiler defaults.

```sh
python3 experiments/07-openxc7/timing_chains/architecture.py \
  --reference "$PREPARED" --stage "$STAGE/reference" --variant reference \
  --xls "$XLS" --codegen "$CODEGEN" --table "$TABLE" --keep-next-selects
python3 experiments/07-openxc7/timing_chains/architecture_validate.py \
  "$STAGE/reference" "$PREPARED"
python3 experiments/07-openxc7/phi_timing.py "$STAGE/reference" \
  --stage "$STAGE/reference-map" --part xc7z030sbg485-1 --phase map
python3 experiments/07-openxc7/timing_chains/architecture_physical.py \
  --stage "$STAGE/reference-map" --nextpnr "$NEXTPNR" --chipdb "$CHIPDB"
```

Repeat in fresh stages with `--variant dedicated`, `registered-selection`, `separate-entry`, `magnitude-rounding` or `registered-egress`. The dedicated variant gives each actor its own executor, register state and bounded ordinary mailbox. It retains the source-fragment collectors, routing groups and effect-window protocol; extra per-actor effect channels contribute buffering. It is an experimental architecture, not a replacement topology backend.

`--keep-next-selects` suppresses the optimizer's splitting of state updates into guarded next values. Use it on both sides of each comparison: it changes mapped logic even when cycles are unchanged. The dedicated variant otherwise produces a scheduling-normalization fan-in beyond the measured model. `--build-only --resume-from opt` reuses a verified IR conversion; skipped phases must match their recorded command and output hash.

Validation requires the complete 161-event BEAM witness with and without output stalls, plus matching per-actor prefixes through prolonged stalls and reset. It permits different cross-actor interleavings and does not prove every application state. Physical runs retain placement separately, record bounded failures, and check required FF/DSP/RAM endpoint classes after routing. Endpoint coverage does not qualify the native delay values or establish a board clock.

`width_mapping.py --stage "$STAGE/widths" --xls "$XLS" --yosys "$YOSYS" --library "$LIBRARY/hls_fixed.x"` measures resource thresholds for the bulk recurrence at widths 32/24/20/16/12; override with `--widths`. This isolated combinational screen measures neither the full decoder nor numerical quality. Reducing width requires an explicit decision about fractional precision and integer range.

Extract per-process XLS stage estimates with `architecture_schedule.py "$STAGE/reference" "$STAGE/dedicated"`. It replays each recorded codegen command with schedule reporting and requires byte-identical RTL. These estimates exclude combinational paths composed across process/FIFO boundaries; compare them with whole-core placement and routing.

## Actor-boundary experiments

`completion_experiment.py` isolates completion sharing in the small shared core. Generate `phi_halo_cell.x` with the candidate Erlang translator in `aggregate_only` mode. Supply `--reference` with the frozen source/IR-command bundle, `--rtl-reference` with the selective baseline, `--generated` with that new DSLX file, and explicit `--stage`, `--codegen` and `--table` paths. It substitutes only aggregate acceptance and executor dispatch in the frozen DSLX, replays conversion/optimization, then replaces only the executor module in the baseline RTL. Other modules and ports must remain identical. Source, tool, schedule and RTL hashes accompany the result.

Run `architecture_validate.py STAGE/compiled PREPARED --cycle-exact --reference-rtl BASELINE`, then map `STAGE/compiled` with `phi_timing.py`. Compare reciprocal-product counts and all primitive resources before routing. `python3 tools/test_shared_completion.py XLS --yosys YOSYS` separately proves complete executor-result equivalence for every request/state bit pattern in the count/member reduction fixture. The small-core cycle witness covers application behavior; neither check establishes routed frequency.

`mailbox_experiment.py --reference SOURCES --rtl-reference BASELINE --library LIBRARY/mailbox.x --codegen-command COMMAND.json --stage FRESH` replays the frozen shared-completion source/IR commands and whole-core codegen flags, replacing only the mailbox library. `--parallel-rows` additionally moves actor-row selection after each row's mailbox choice. It calls `module_substitution.py --reference BASELINE --generated CANDIDATE_RTL --stage FRESH --modules '.*SharedService.*'` to reject interface changes, require a matching baseline manifest and keep unselected RTL byte-identical. Only the four services change; the selective executor schedule remains untouched. Validate and map with the preceding commands.

`mailbox_widths.py --xls XLS --yosys YOSYS --stage FRESH` compares isolated selectors at actor counts 2/8/16, depth 5: the original sequential fold, parallel eligibility within the selected row, and parallel choices for all rows. Override `--actors`, `--depth` or `--variants`. These area measurements expose replication costs; they are not full-core percentages or timing results.

`control_cones.py BEFORE/core.json AFTER/core.json --output comparison.json` compares named result-FIFO occupancy dependencies through actor read addresses, service completion and reduction readiness in the small shared core. It retains cell chains and input hashes, stops at registers/RAMs, rejects reachable unmodeled primitives and requires matching endpoint reachability. Counts conservatively connect every cell input to every output: they are structural upper bounds, not sensitizable paths or delay estimates. Use them to screen a hypothesis before routing, not to infer MHz. `test_control_cones.py` covers attribution, reconvergence, register feedback and unsupported hard arithmetic.

`python3 tools/test_mailbox_formal.py XLS --yosys YOSYS` checks exact selection at `(actors, depth) = (1,1), (2,3), (2,5), (3,8)` and the metadata induction base/step at each depth. Legal live slots are distinct and in range; unused slots cannot remain postponed. Consume/postpone directives are exclusive, while phase changes, admission and reset vary independently. A reversed-priority mutation must produce a counterexample. See [formal contracts](../../../docs/formal-contracts.md) for the distinction between these finite-width, unbounded-history claims and the whole-core simulation witnesses.

`boundary_experiment.py --reference DEDICATED --stage FRESH --variant VARIANT` reuses verified dedicated-actor IR and the frozen compiler/table. Variants are `collector-register`, `actor-register`, `actor-ii2`, `actor-ii2-field-only`, and `actor-ii2-batch-register`. The register variants use depth-two FIFOs without forward bypass. The recurrence variants permit two cycles only on phi actor feedback arcs; `field-only` further restricts this to its two numerical field values. Every other state arc retains a one-cycle limit. Schedule audits require unrelated process schedules to remain identical. These are explicit derived experiments, not compiler-cache edits.

Validate with `architecture_validate.py FRESH PREPARED`, then map and route using the architecture commands above. `boundary_trace.py --rtl FRESH --stage TRACE` passively observes the dedicated fixture's aggregate and effect interfaces. It matches complete payloads in FIFO order, measures handoff latency and output blocking, and reports effect spacing as an observation rather than a causal dependency. It is specific to this fixture's generated module interfaces.

`egress_experiment.py --reference FRESH --stage EAGER` substitutes only `dedicated_egress.v`, checking identical ports and byte-identical surrounding RTL. This work-conserving merge retains blocked grants and preserves per-input order. It is an RTL counterfactual for the benchmark: the frozen XLS compiler rejects the repeated nonblocking receive needed by the direct DSLX expression. Run the normal/stalled/reset comparison and the directed test:

```sh
iverilog -g2012 -s dedicated_egress_tb -o "$STAGE/egress.vvp" \
  experiments/07-openxc7/timing_chains/dedicated_egress.v \
  experiments/07-openxc7/timing_chains/dedicated_egress_tb.sv
vvp "$STAGE/egress.vvp"
```

`factor_rounding.py --stage FRESH --xls XLS --yosys YOSYS --library hls_fixed.x --z3 Z3` proves the factored division identity and signed intermediate bounds, rejects an incorrect bias, compares compiled RTL against integer rounding, and measures isolated resources. `architecture.py --variant factored-bulk` applies it to the shared application. `factor_rounding.py --center` also checks the center component and its anyon offset; `architecture.py --variant factored-field` applies both expressions. The table includes their exact constant-product entry; reproduce that probe with `timing_model/characterize.py --ops smul_const_35_37_71_45812984491 --widths 71` and the explicit tool/stage flags from the timing-model guide. Keep vendor characterization and held-out kernel validation separate from local resource screening.

The arithmetic runner also writes `FRESH/vendor-kernels`, a `timing_model/batch.py`-compatible corpus containing both complete kernels between preserved input/output registers. Use it as held-out validation, separately from the constant-product calibration corpus. It prepares EDIF locally without invoking Vivado. The [vendor results](../results/vendor-followup-2026-09-26.md) compare isolated arithmetic with complete-core timing.

## Arithmetic resource mapping and DSP cascade dependencies

`phi_timing.py PREPARED --stage FRESH --part xc7z030sbg485-1 --phase map --no-dsp` maps the unchanged decoder into LUTs/carry chains. It preserves the XLS schedule and the separately mapped harness. The synthesis script and policy are part of the mapping provenance; retain `--no-dsp` on subsequent `phi_timing.py` mapping/report invocations. `architecture_physical.py` can route the mapped result directly and selects FF/RAM/DSP endpoint requirements from the primitives actually present.

The local coarse DSP timing model must exclude nonexistent A/B cascade dependencies before comparing DSP and LUT arithmetic. [UG479](https://docs.amd.com/api/khub/documents/gu4oRPFEh_Pm2uaAlfY6Kg/content) defines ACOUT/BCOUT as the selected A/ACIN or B/BCIN bus, independently of the multiplier result. With the corresponding registers bypassed, only the selected input's same bit can reach each cascade output. The [vendor follow-up](../results/vendor-followup-2026-09-26.md) supplies four measured forwarding delays for xc7z030-1.

```sh
python3 experiments/07-openxc7/timing_chains/install_dsp_cascade.py "$NEXTPNR_SOURCE"
cmake --build "$NEXTPNR_BUILD" --target nextpnr-xilinx -j2
cp "$NEXTPNR_BUILD/nextpnr-xilinx" "$NEXTPNR_CASCADE"
```

Use a dedicated experimental source tree and a new frozen binary path; retain the original binary for historical replay. The installer rejects an unexpected DSP model and can be rerun safely. It changes only combinational cascade dependencies and their selected-bus delays; registered support and non-cascade outputs remain unchanged. Unknown input selections keep the coarse delay. `test_phi_timing.py` runs C++ dependency/delay checks and, when Yosys is available, proves the cascade identities against its primitive model with symbolic data/control inputs. The proofs establish topology; the delay values come from audited SDF.

For an isolated model comparison, install with `--diagnostic-switch`, rebuild separately, then add `--diagnostic-dsp-cascade` to the native routing command. It routes with the historical dependency graph and delays, then rechecks timing with both corrections, asserting an unchanged cell/net/placement/routing checksum. The log retains both timing reports; the final JSON uses the corrections. This avoids the pinned reader's failure when reloading a fully routed JSON checkpoint. Without the diagnostic flag, the new binary uses both corrections throughout.

For vendor comparison, use `timing_model/prepare_application.py MAPPED_JSON FRESH --top phi_timing_harness --yosys "$YOSYS"` on both complete mappings, then run `timing_model/measure.tcl` with the same period/part and before/after graph audits. Changing mapping alone does not validate the existing DSP-trained XLS estimator for future LUT-only schedules.
