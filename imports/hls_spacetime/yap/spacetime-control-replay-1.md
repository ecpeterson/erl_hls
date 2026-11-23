# Clocked control replay of the numerical-only Phi pipeline

The user chose to refine the cycle model instead of measuring a new physical period. This change adds a bounded control-only replay to the existing latency-analysis work. No Vivado, EC2, compilation or RTL simulation was run. The original baseline, pipeline witness, source payloads and failed 99/109 predictions are preserved.

## What changed

The previous solver propagated delays through a recorded event DAG while absorbing or preserving unexplained gaps. It correctly predicted the first 20 numerical result/commit pairs but missed public completion and following-episode scheduling. The new model executes the source control rules: owner/private/commit stages, one outbox per actor, independent publisher recipients, FREE/FULL/LEASED capture slots, registered release, sender order, held reservations, postponement, endpoint arbitration, cyclic gateway polling, absolute output-ready windows and causal host commands.

The supplied profile interprets 581 future operations across all six actors, 207 batches and 426 deliveries from the baseline capture. Operation records have no scheduling timestamps. Candidate clocks are comparison evidence only. Fixed values and branch decisions remain assumptions; reordered work is rejected rather than silently scheduled in the old order. Source machine encodings narrowed by XLS remain opaque.

Replay starts at C1775 from the exact shared prefix. The gateway is idle after accepting an endpoint-1 final word at C1774, so its next polling cursor is management. The initial inbox, capture, sender-order, publisher and endpoint states come from source-bound taps. Actor 2 has a retained outbox; actor 3 has one remaining delivery in its publication. Ingress ownership is checked empty. Failure-free operation is separately verified against the original capture and bound source inputs.

The source rules explain the selected step without a fitted offset. A ten-clock shift in frame availability misses a cyclic poll, shifting first output validity from C1841 to C1853. The shifted frame sequence encounters five fewer stalled output clocks. Thus public completion moves seven clocks: 99→106. The same rules govern later steps and host feedback; no later-step timing constants were added.

## Retained comparison

| Completion           | Baseline clocks | Pipelined clocks | Model error |
| -------------------- | --------------: | ---------------: | ----------: |
| Step 4 interval      |              99 |              106 |           0 |
| Step 5 interval      |              99 |              122 |           0 |
| Step 6 interval      |             110 |              106 |           0 |
| Step 7 interval      |              92 |              113 |           0 |
| Step 8 interval      |              98 |              115 |           0 |
| Step 9 interval      |              95 |              112 |           0 |
| Steps 4–8 together   |             498 |              562 |           0 |
| Entire replay suffix |             593 |              674 |           0 |

The model matches all 90 output-word acceptances and 36 input-word acceptances in the suffix, including payload, last-word flag and exact clock, for both baseline and candidate. All 18 remaining public frames match. Readout completion is C2306 at baseline and C2367 with the pipeline, also reproduced. Public frame identity is joined by logical sender and occurrence, not forced global ordering.

Internal checks independently match all 1,612 baseline actor operation/publication timestamps and 17,790 control values. For the candidate, 1,195 observable Phi timestamps, 509 transaction identities/full values, and 20,220 control values across all six actors match. These controls include every zero and nonzero acceptance, take, postpone, release and publication indication in the compared ranges. The suffix contains no asserted postponement; that rule is exercised by isolated fixtures. One predicted step-10 launch at the final C2448 edge has no following C2449 register observation and is not claimed as validated; it cannot feed the already accepted C2448 public result. `internal-comparison-1.json` retains the initial missing-observation failure, and `internal-comparison-2.json` states the precise finite disposition.

These later steps were already observed before this model was written. This is retrospective validation, not a blind holdout. The zero-intervention replay is nevertheless a substantive check: unlike the old DAG model, its internal clocks are recomputed from source state and handshakes, not retained as release floors.

## Boundaries and next use

The model preserves recorded numerical work and branch decisions; it does not execute Erlang or DSLX arithmetic, infer dynamic gate causality, or predict a placed/routed period. Exact cycle correspondence does not establish RTL equivalence or unrestricted progress. Actor 2 has further internal work beyond the captured script, and the final actor-3 step-10 batch lacks complete delivery evidence. Those tails cannot produce a new completion score. The qualified step-9/public-readout targets complete before they are needed; equal live terminal state remains unclaimed.

A genuinely new workload or unobserved ready/latency intervention is the next prospective validation opportunity. Freeze its profile and prediction before obtaining that witness. No new hardware run is needed to retain this model improvement, and no physical speedup is claimed.

## Reproduction and retention

Artifacts are under `/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-08/control-replay-1/`. The baseline-only `extract_host.py`, `extract_profile.py`, `refine_terminal.py` and `normalize_profile.py` retain source identity, exact initial ownership and explicit terminal dispositions. Baseline timing evidence is separate in `expected.json`/`host-expected.json`; comparison helpers never feed candidate measurements back into a profile. `profile.json` and the refined `profile-2.json` are both retained.

The first report named `replay-fence8-1.json` accidentally selected a step-9 public ID along with the step-8 IDs; its name does not define its scope. Its explicit target list remains authoritative. `replay-final-1.json` and `compare-final-1.json` cover the full intended suffix. The final source-bound input/report are `replay-profile-2.json` and `replay-final-3.json`; `final-schedule-verification-1.json` checks that every schedule, control and accepted word is unchanged from the independently qualified report. An intermediate report conservatively censored a known final-edge commit because its future batch deliveries were incomplete. The corrected boundary stops before admitting those unknown deliveries to the publisher, rather than discarding an independent final public transfer; a regression covers this case. The normalizer's initial variable-shadowing failure occurred before any profile or report was created and required no witness rerun.

Usage and model interfaces are documented in [latency scenarios](../docs/latency-scenarios.md). Small independent fixtures cover missed polling turns, ready-window phase, credit visibility, outbox reuse, held grants, per-sender ordering, postponement, causal host releases, resets, finite tails and changed-order rejection.

## Local qualification

All 513 JavaScript tests and 155 Erlang tests pass, together with JavaScript/Erlang formatting, Dialyzer and the 18-file source-contract audit with zero findings. Checks ran serially under the 6 GiB guard; both owned process groups are gone. The first Erlang attempt hit an existing cross-VM temporary-directory collision: its test helper used VM-local `unique_integer/1` under a fixed `/tmp` prefix. Atomic creation with random suffixes fixes that collision while preserving old witnesses; the failed attempt remains retained. Only the failed/unrun checks were repeated. No remote CI was invoked.

## Prospective rebalance witness

The [existing-boundary numerical rebalance](spacetime-numerical-rebalance-witness-1.md) now passes a new RTL witness against the zero-extra-latency schedule frozen before implementation: 99, 498 and 593 clocks, with exact public timing, committed state and observable controls. Numerical private storage contains partial arithmetic, so comparison reconstructs its logical action and does not equate the raw representation with a finished result. This prospectively validates preservation of the existing control schedule; it does not test an unseen workload or predict a new physical period.
