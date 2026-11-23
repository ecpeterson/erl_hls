# Coordinated shared partition reference (#12)

This records commit `9f0c401`; the current [actor-local design](actor-outbox-progress.md) replaces its global credit. That reference changes storage/processing placement while retaining the complete D3 witness: acquisition/noise, neighbor exchange, reduction, correction application and measurement closeout. The direct backend stays as an independent placement reference. Private partition transport and deployment logic stay in this repository.

## Admission argument to check

The public executor and effect router already implement one shared lookahead reservation for a connected scheduler domain. Independent per-board arbiters would multiply that reservation without a progress argument. This experiment instead has one owner and transports remote request/grant/release pulses on separately credited lanes. The client protocol already tolerates delayed grants, including returning an unusable grant. Each signal lane is FIFO/exactly-once under the existing link assumptions; common reset clears all ownership and transport state together.

A release cannot overtake the request that earned its grant: the owner must receive the request before producing the grant, and the remote client must receive that grant before releasing it. A later request may precede the previous release because their lanes are independent; the arbiter retains it in the pending bit while the old ownership remains active. The client permits only one ungranted request. Delayed unused grants are returned through the same release path. Common reset discards all three paths together.

This preserves the public rule, but finite workload tests are not a proof of arbitrary cyclic graphs. The link arbiter must continue polling control lanes while application destinations are blocked; control consumers must not depend on actor admission. Reserved receive storage provides that separation. Grant traffic still competes for link bandwidth. Each one-bit signal currently uses the ordinary five-beat data packet: a remote request/grant/release cycle uses 15 data beats plus three eventual returned-credit beats. A compact control encoding is a candidate to measure, not yet an attribution of the observed throughput loss.

Each actor gets its own producer pending slot after its fair incoming-lane merge. A separate slot returns effect credit. Startup is preloaded and bounded by mailbox capacity. Source-side reduction fragments are deliberately absent so ordinary reductions exercise actor state RAM.

## Evidence to collect

- [x] Direct and shared complete D3 witnesses at 6/14 ns clocks, including held link, stopped peer, blocked events and active reset. The shared witness also passes with device clocks reversed to 14/6 ns.
- [x] Public actor/mailbox snapshots diagnose postponed syndrome work and show recovery; all 54 final actor snapshots report no failure.
- [x] Complete-device XC7 synthesis with two matched seeds, including debug and crossings. All repeats agree; the pair saves 14.9% LUTs but adds 7.5% FFs and 196 RAMB18-equivalents, with DSPs reduced from 216 to 48. See the [report](../docs/artifacts.md#historical-reports) (`experiments/results/partition-shared-schedulers-2026-09-21.md`).
- [x] Fresh-activation status rounds 8–18 average 26,143.6 ns direct versus 34,324.2 ns shared: 23.8% lower paced step rate, with different executor sharing and remote window traffic together.

Follow-on distributed ownership needs an explicit bounded progress argument and measurements. Recovery remains coordinated abort/restart; this task does not change application failure semantics.

## Elaboration finding

A 12-contender public effect-window arbiter caused severe XLS type-inference growth; isolated actors and a 36-lane bridge did not. Replacing its conditional whole-array capture with one unconditional slot update reduced the isolated conversion from over a 90-second limit to 13 seconds. Public PR #161 contains that equivalent rewrite and a bounded large-domain regression. The generated scheduler capture had the same conditional-array shape: six actors/seven producers exceeded three minutes; the equivalent per-slot update converts in 41–49 seconds for the two actor probes. This experiment pins its commit atop the previous dependency revision, avoiding unrelated application/compiler changes in the storage comparison.

The direct reference with the current reset adapter passed the full witness. Accepted complete status rounds 8–18 averaged 26,143.6 ns (range 25,914–26,292 ns; population variance 10,748.64 ns²) at 6/14 ns device clocks with periodic link stalls. These timestamps include host pacing. Direct device 0 maps to 102,148 LUTs including distributed RAM and 106,907 FFs; device 1 maps to 190,459 LUTs and 194,507 FFs. Both naming seeds agree. Shared counts are 98,068/150,866 LUTs and 126,156/197,874 FFs; wider sharing improves the LUT tradeoff, but storage and control overhead remain substantial.
