# Native timing of the two-edge Phi numerical rebalance

**The matched routed measurement improves substantially without changing the finite cycle schedule.** The fixed-constraint setup-equivalent period falls from 8.997 ns to 5.560 ns (38.2%), at a cost of 809 LUTs and 329 flip-flops. The original 5 ns setup target still fails. This result qualifies the constant-enabled variant of the [existing-boundary rebalance](spacetime-numerical-rebalance-witness-1.md); it does not switch the production backend or replace the viewer’s baseline physical catalogue.

## Matched result

| Measurement                                 |              Baseline |             Rebalance |
| ------------------------------------------- | --------------------: | --------------------: |
| Routed setup slack at 5 ns                  |             −3.997 ns |             −0.560 ns |
| Static setup-equivalent period, 5 ns − WNS  |              8.997 ns |              5.560 ns |
| LUTs                                        |                12,131 |        12,940 (+6.7%) |
| Flip-flops                                  |                 6,839 |         7,168 (+4.8%) |
| DSP / BRAM / latches                        |             0 / 0 / 0 |             0 / 0 / 0 |
| Worst hold slack                            |             +0.014 ns |             +0.013 ns |
| Worst pulse-width slack                     |             +2.225 ns |             +2.225 ns |
| Selected step / five-step interval / suffix | 99 / 498 / 593 clocks | 99 / 498 / 593 clocks |

The period column holds the reported clock constraints/skew fixed. It is not an independently validated alternate clock or measured device frequency. Multiplying by the unchanged cycle counts gives static-bound estimates of 0.891→0.550 µs for the selected step and 4.481→2.769 µs for the five-step interval. Those are estimates, not demonstrated execution times.

Both implementations use Vivado 2024.2, `xczu7ev-ffvc1156-2-e`, OOC synthesis with rebuilt hierarchy, two threads, a BUFG clock, and Default placement, physical optimization and routing. The four native controls—including the complete implementation Tcl—are byte-identical. Only the arithmetic core differs among the five RTL inputs. External nonclock input/output paths are false; internal reset, control and data remain timed.

All 14,638 routable nets are fully routed, with zero routing errors and zero default-ruledeck OOC DRC violations. Hold and pulse-width checks pass. Internal no-clock, unconstrained-endpoint and loop checks are zero. The 36 input/89 output delay warnings reflect the external false paths. Missing OOC `HD.PARTPIN_LOCS` and `HD.CLK_SRC` retain the original board-interface/upstream-clock limitations; this is not board timing closure. The tool also warns that OOC DRC omits some connectivity checks. The setup target remains a recorded failure: 3,310 endpoints fail at 5 ns, with TNS −899.399 ns.

## Constant-enabled qualification

The diagnostic bypass and enable input are removed. Numerical completion always stores two signed 36-bit numerators and non-phi metadata at the existing action edge, then finalizes phi and enters/publishes at the existing following edge. Ordinary actions explicitly preserve phi so obsolete parallel arithmetic can prune. One outstanding action, old-state outbox admission and blocked-entry retention remain unchanged.

Exactly one fresh RTL witness runs from reset with the transformation enabled throughout. All 70 input words and 153 output words across 30 frames retain baseline values and acceptance clocks. The 2,369 pre-edge samples include 127,926 matching source-bound controls, 56,856 shared exact-width owner fields and 4,738 matching committed-machine samples. Reconstructing the partial representation matches all 346 active baseline private actions. The recording exercises 243 numerical launches—including 100 before the model window—and 37 blocked numerical holds. No diagnostic enable tap remains.

The unchanged frozen model covers C1775–2367 and matches all 99/498/593-clock intervals, 1,209 Phi boundary events, 17,790 control values and accepted-word clocks. Ten narrowed/eliminated fields remain explicitly uninterpreted. Fresh source/IR/RTL bindings show all four numerator registers feeding their own committed-state and outbox D logic. The prior arithmetic/owner unit qualification is reused; this new recording qualifies removal of the diagnostic mode for the finite workload. It is not unrestricted or native equivalence, a new-workload prediction, or a sensitized bitwise dependency proof.

## Changed limiting population

The final worst path starts at Phi actor 2’s `enter_pending` bit and ends at its reduction accumulator: `____state_136_reg[336]` to `[439]/D`. The displayed path passes through selection/sender-order logic and reduction add/selection. It has 22 logic levels (four CARRY8 and eighteen LUTs), with 1.820 ns logic plus 3.656 ns routing; routing contributes 66.8% of its 5.476 ns data delay. A notable 0.605 ns net drives 69 sinks between the displayed X91/Y212 and X83/Y183 slices. These names and source layouts associate the path with functionality; they do not establish dynamic sensitization or isolate why placement chose those locations.

The worst 50 reported endpoint paths span only 46 ps of slack, from −0.560 to −0.514 ns. Their destinations comprise 34 Phi actor-2 machine/private-state paths, six activation-to-actor-0 private-state paths, six transport capture/order paths, and four gateway receive-order paths. The activation source is a named native replica; the actor-0 private word is narrowed and is not decoded as source bits. The result supports the arithmetic rebalance, while showing a broader remaining control/communication population rather than another single dominant numerical chain.

## Execution and retention

One native attempt ran for 735.771 seconds, with no guard trigger, 4.71 GB peak process-group RSS and at least 27.76 GB available memory. Synthesis took 311.686 s, optimization 4.466 s, placement 143.973 s, physical optimization 18.411 s and routing 212.899 s. Reports, checkpoints, functional-netlist export and 5.524 s of remaining startup/exit overhead are recorded separately. Local compile/build/witness work ran serially under the 6 GiB guard; it did not overlap native execution.

Terminal verification checks all 12 frozen inputs, all 31 outputs and the actual runner/process group’s disappearance. The single collection contains 571,825 compressed bytes, with full raw reports and checkpoints retained remotely. All 174 original compiled files remain unchanged. No implementation restart, repeated route attempt, settings search, geometry export or live-device test occurred.

Artifacts: `/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-08/numerical-rebalance-physical-1/`. `final-review.json` combines qualification, physical comparison, source-path assessment and runtime evidence. The 3,966,083-byte reproduction archive contains 424 hash-verified files: exact candidate source/IR/RTL, passive harness and recordings, frozen prediction, baseline comparison inputs, controls, reports and terminal evidence. SHA-256: `f2b0bdd5ea3fb7b6c65262def014d1547b20c960e10968e4fa609441bad42d49`. The archive’s README explains path relocation and reused tools. Bulk products remain subject to seven-day retention review.
