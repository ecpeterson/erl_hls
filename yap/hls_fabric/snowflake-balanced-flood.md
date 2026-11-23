# Balanced neighbor selection

Reviewed 2026-10-01. Implemented and retained in the full actor baseline. The isolated comparisons below establish their stated local results; later combined routes do not supply an isolated timing attribution. Current work is in [the campaign plan](topology-specialization.md).

Preregistered after the combined control/effect synthesis, before changing the kernel. Its leading six replicated paths end at `SharedExecutor/p0__14__5`, the fourth sequential signed-CID comparison in `merge_surface`. The input comes through the executor request FIFO and callback/entry selection; the whole path is not just the comparisons. It has eight CARRY8 cells, 30 logic levels and a synthesis-estimated 7.266 ns period. Mailbox paths follow at 6.964 ns. These are unplaced estimates.

Replace sequential neighbor visitation by an ordered balanced tree. A subtree retains its lowest valid CID (left wins ties), whether unrooting stops visitation, and whether a visited neighbor contributed growth before that stop. The first component can inspect all neighbors because a stop overrides the final CID/pointer; the growth component must preserve the visited prefix exactly. Keep the original N/W/D/U/E/S surface priority and W/E/D/U repetition priority, signed 32-bit IDs, all failure checks and the ordinary actor path.

Hypothesis: the six dependent CID comparisons become three tree levels including the actor's own candidate. There are no new actor activations or pipeline stages. Expect identical per-input transition results, including unrooting, pointer ties and growth before a stop. This does not predict a 50% clock improvement: selection and callback logic precede the tree, mapping can rebalance it, and other paths remain. First compare the two lowered transition functions for every defined input bit with SAT and run the independent stream fixtures. Measure isolated mapped structure before spending another full-core compilation/route.

Do not narrow CID width or remove malformed-input checks as part of this experiment. Retain the old generated transition as the equivalence reference, with its source hash; use a deliberately wrong tie-order control to check that the harness can find a counterexample. A finite-domain combinational equivalence result covers one transition at those widths, not an unbounded decoder execution or physical timing.

## Initial result

The surface transition now has an ordered balanced tree; repetition deliberately retains the serial control. The 212 existing ERTS stream tests passed before adding two directed growth/unrooting tests, which also pass. A repeated full-suite run under concurrent compilation hit the existing five-second timeout in `surface_d5_continuous`; there were no assertion failures. Scoped Dialyzer and source contracts pass. Local helper type aliases are not currently accepted by the lowerer, so the two tuple specifications use source macros rather than duplicated long specs.

`flood_equivalence.py` compares the old and new normally lowered surface transitions over all 364 input bits: seven complete 46-bit nodes, an eight-bit access mask, two flags and a signed 32-bit reset ID. SAT found no counterexample (71.85 s including compilation). Replacing strict CID comparison by less-or-equal produces a counterexample (15.91 s). The comparison preserves failure presence and exact successful state/transfer; source-line-based failure-site numbers are intentionally excluded. This proves the stated finite combinational equivalence, not decoder liveness or physical correctness.

The reference is the generated kernel before editing `snowflake_node_impl.hrl` at private commit `966c0f6`. Local evidence is `_build/balanced-flood/{before,after,sat}`; `sat/results.json` pins generated modules, compiler/solver binaries and all contract/solver artifacts. Reproduce with `flood_equivalence.py --before OLD_GENERATED_X --after NEW_GENERATED_X --stage FRESH_DIRECTORY --xls TOOLS --codegen CODEGEN --stdlib STDLIB --library PUBLIC_LIBRARY --yosys YOSYS`.

The isolated native comparison wraps the complete transition with input/output registers, retains all 364 input and 55 result/failure bits, and uses the same 5 ns constraint and ZU7EV-2 target. Those registered kernels are not the actor's actual request-FIFO/entry context. A favorable isolated result still needs a matched complete decoder compilation and measurement before adoption.

## Complete-core result

The frozen header-only comparison preserves the entire stress-eight RTL transcript. At the same two-stage XLS schedule and 5 ns ZU7EV-2 synthesis constraint, LUTs change 152,271→152,066 (−0.135%), FFs 122,864→123,032, and BRAM36 remains 72. The setup-derived period changes 7.266→6.964 ns (−4.16%). All twenty saved leading paths now run from routers to mailbox RAM (6.869–6.964 ns); the prior executor arithmetic leader is absent from that sample.

The isolated registered transition changes 8.192→4.452 ns, with 484→489 LUTs and 344→334 FFs. Its 36→18 logic levels and 12→4 carry cells validate the intended local structural change, but do not forecast a comparable whole-core improvement. The full-core result reaches the previously sampled mailbox limit, which is why the actual gain is much smaller.

Retain the implementation: it removes the identified arithmetic chain without added activations or meaningful full-core area cost. Neither this variant nor its composition with local advancement/completion LUTRAM has a routed result. The [campaign evidence](../../docs/hls_fabric/artifacts.md#historical-reports) (`experiments/snowflake/actors/control-compaction/measurements.md`) keeps those cohorts separate. SAT fixes record tags to the normal node shape and trusts lowering; it does not prove the translator or the global protocol.
