# Aggregate delivery: isolate backward readiness

A single bypassing slot at each final reduction-aggregate handoff removes the measured combinational dependency from scheduler result occupancy to reduction-plane readiness. The 2×1 attribution fixture keeps its step cycles; this is **not a routed clock measurement** or a result for the target 2×4-qubit patch.

The [registered hypothesis and ownership ledger](../yap/aggregate-ready-boundary.md) distinguish accepting an aggregate from committing actor state. The implementation changes only `scheduler_channels/2`: final handoffs use XLS depth-one bypass FIFOs, while aggregate-source mux inputs remain unchanged. Empty transfers have no added latency. A full buffer cannot accept a replacement while draining, so other workloads may acquire recovery bubbles.

## Matched screen

Baseline: DSP integration `dbc9c90`, two planes, one shard per plane, two executor stages. The screen uses the same optimized IR and calibrated codegen as the preceding [reciprocal integration](reciprocal-integration-2026-09-27.md), changing only the two final aggregate channel configurations. It substitutes only their generated FIFO module bodies into frozen RTL; all application procs and ports remain byte-identical. A fresh production DSLX conversion independently checks the generated depth/bypass/register configuration.

| Measure | Before | Buffered |
|---|---:|---:|
| Normal cycles/step | 79.25 | 79.25 |
| Stalled-output cycles/step | 79.833333 | 79.833333 |
| Mapped core LUTs | 34,234 | 33,876 (−1.05%) |
| Fabric FFs | 21,786 | 22,130 (+344; +1.58%) |
| DSP48E1 | 20 | 20 |
| CARRY4 | 592 | 592 |
| RAMB18E1 / RAMB36E1 | 44 / 8 | 44 / 8 |
| SRL primitives | 0 | 0 |

The storage increase is below the 438-bit raw payload/occupancy estimate because mapping removes constant bits and redundant FIFO bookkeeping: each payload contains 45 constant bits in the mapped netlist. LUT count is an observed whole-core mapping result, not an independently attributable count of removed handshake logic.

Each aggregate channel delivers 924 items with zero producer-blocked cycles in both profile runs, before and after. There are 462 adjacent transfers per channel. This supports the registered unchanged-cycle prediction for this workload; it does not exercise a full aggregate buffer.

## Which dependency changed?

These are conservative mapped primitive levels from executor-result FIFO occupancy, with all cell inputs connected to every output. They establish structural connectivity, not sensitizable paths or delay. Both comparisons preserve the same named source and endpoint sets; a missing signal is rejected rather than counted as a cut.

| Endpoint | Before | Buffered |
|---|---:|---:|
| X reduction-plane output readiness | 23 | No combinational dependency |
| Z reduction-plane output readiness | 23 | No combinational dependency |
| X scheduler stage completion | 21 | 24 |
| Z scheduler stage completion | 22 | 22 |
| X / Z state-RAM read address | 13 / 12 | 13 / 12 |
| Syndrome schedulers' completion | 10 / 10 | 10 / 9 |

The intended cross-proc cuts succeed. The longer X scheduler cone is a real caveat: remapping the forward bypass/selection logic is not uniformly beneficial. The scheduler's retirement/eligibility/issue dependency survives. There is no evidence yet that the overall clock improves; arithmetic/RAM limits also remain. The next architectural candidate is a reserved dispatch boundary, with fresh actor/output ownership captured before execution and separate ordered retirement, rather than another cached eligibility bit.

## Complete storage frontier

**Correction to the initial screen:** disappearance of the named reduction-ready endpoint does not establish that a critical path leaves the limiting set. Following the same launches to actual storage pins finds 25/23-level paths to the new X/Z buffer occupancy enables. The old report omitted these newly introduced endpoints.

`control_frontier.py` now follows every reachable input of supported registers and RAMs, and retains external outputs and unsupported primitives explicitly. Shared enable nets are grouped with their full sink counts; only the displayed path details are capped. These are structural maxima over the selected result-occupancy launches, not all possible design launches or timing delays.

| Deepest reachable category | X before | X buffered | Z before | Z buffered |
|---|---:|---:|---:|---:|
| Register CE | 24 | 25 | 24 | 24 |
| Register D | 24 | 25 | 24 | 25 |
| RAM ADDRARDADDR | 23 | 24 | 23 | 23 |
| RAM ADDRBWRADDR | 23 | 23 | 23 | 24 |
| RAM ENARDEN | 23 | 24 | 22 | 22 |

The deepest buffered X enable chain crosses `scheduler_2_state.rd_addr` after 13 of 25 levels; Z crosses its corresponding address after 12 of 24. This is a useful candidate midpoint. However, a 25-level Z path into `one_hot_sel_168978` updates the mailbox order array, and a 24-level mailbox write-address path does not cross that landmark. Dispatch and admission both consume freshly retired metadata. Cutting only the actor-address signal would leave these neighboring chains.

The initial named-endpoint cut therefore passes its narrow connectivity check, **not** a complete control-depth or routed-timing promotion gate. The [end-to-end pipeline plan](../yap/scheduler-pipeline-plan.md) first makes metadata visible across a clock boundary before both arbiters, then registers a reserved dispatch ticket before load. It preserves one metadata authority and explicitly budgets the possible recurrence-cycle cost.

The [before](aggregate-ready-boundary-2026-09-27/frontier-before.json) and [after](aggregate-ready-boundary-2026-09-27/frontier-after.json) reports retain hashes, category maxima, total reachable pin/net counts, and the deepest representative per category. DSP `CEB2`/`CEM` pins appear as uncovered boundaries one supported level from the launch; they are not silently counted as generic register endpoints. This audit neither traverses unknown DSP modes nor supplies their timing.

## Validation and reproduction

- Each normal/stalled application run matches 161 BEAM-oracle events. A 12,000-cycle comparison matches per-actor outputs through long stalls and reset; it permits different transfer cycles.
- A separate 6,000-cycle queue-model witness runs on generated and mapped FIFO RTL: 1,445 accepted, 1,438 delivered, seven discarded by reset, 698 immediate bypasses, 511 full-buffer recoveries, and 2,750 full-stall cycles. It checks occupancy-only upstream readiness, payload order and stability while stalled. This is a simulation witness, not a universal proof.
- EUnit: 1,180 tests, zero failures. Dialyzer: 118 modules, success. Source contracts: zero changed-declaration gaps. Seven control-cone and twelve path-report tests pass.

Retained [measurements](aggregate-ready-boundary-2026-09-27/summary.json) include input/netlist hashes, exact dependency chains, traffic and application results. The adjacent files contain the generated FIFOs, queue witness logs, and portable Yosys recipe. Full build trees are not committed.

Reproduce with the same frozen inputs used by the reciprocal report:

```sh
python3 experiments/07-openxc7/timing_chains/aggregate_boundary.py \
  --reference BASELINE_COMPILED --ir FROZEN_OPT_IR \
  --command CODEGEN_COMMAND_JSON --stage FRESH_STAGE
python3 experiments/07-openxc7/timing_chains/aggregate_traffic.py \
  FRESH_STAGE/compiled --stage FRESH_TRAFFIC
python3 experiments/07-openxc7/timing_chains/architecture_validate.py \
  FRESH_STAGE/compiled ORACLE_BUNDLE --reference-rtl BASELINE_COMPILED
python3 experiments/07-openxc7/timing_chains/control_cones.py \
  BASELINE_CORE_JSON CANDIDATE_CORE_JSON --allow-cuts --output CONES_JSON
```

Map both cores with the existing `phi_timing.py --phase map` flow. The boundary script also runs the generated FIFO witness; use the retained `fifo-map.ys` recipe and the same testbench plus Yosys `cells_sim.v` for its mapped counterpart. Physical timing remains a separate gate: native registered-DSP coverage is incomplete, and this turn did not use EC2.
