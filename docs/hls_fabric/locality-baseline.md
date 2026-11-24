# Reproducing the retained Snowflake locality baseline

This opt-in experiment preserves the accepted `local-admission-descriptors-2026-10-15` combination as a comparison point for future architectures. It does not change ordinary backend lowering. Build the matching umbrella revision using [the normal prerequisites](building.md), OTP 28.0.2 and rebar3 3.24.0.

The cumulative pipeline retains source-derived receive capture and conditional decoding, phase specialization and barrier grant summaries, private consumer-payload erasure, admission predecode, and local admission/descriptors. The final pass registers actor-local free-cell/capacity proposals and masks, separates validity from private payload, and prepares ordinary/refill descriptors independently at the existing boundary. Consumer erasure remains part of this measured combination; its isolated result is not the combination's result. Later refill-selection, refill-payload-bank and owner-local-completion experiments are excluded.

## Reproduction status

The original reproduction driver and its fixed reference inputs remain external to
the umbrella. This page retains the accepted evidence and its bounds, but does not
define a runnable in-tree workflow.

## Retained evidence

The reference manifest retains all nine historical file digests, a location-independent projection-layout digest, and the external evidence inventory. The original backend RTL passed a 128-round, 1,125-correction witness with every event byte, including cycle numbers, equal to its parent. A separate reset-at-cycle-600 witness retained RAM, reset with eight outstanding operations, produced a fresh 128 rounds and 1,125 corrections, and stalled each output for 1,000 cycles. These are finite witnesses, not arbitrary-history theorems.

The original default Vivado 2024.2 XCZU7EV-2 out-of-context measurement used 173,704 LUTs, 102,075 FFs and 48 BRAM36s, with no BRAM18s. Its 6.409 ns period proxy and 274.48818897637796 mean cycles give 1.7591948031496063 µs per step. The proxy is `5 ns − WNS`; negative WNS means the original 5 ns constraint was not met. Hold and pulse checks passed and all nets routed without routing errors. These historical numbers apply to the bound RTL, original options and toolchain, and are not a promise for another build or a new measurement of this PR.

Keep experiment outputs in the [artifact archive](artifacts.md). The repository carries lowering, checks, fixed inputs and compact identities; it does not carry generated RTL, routing checkpoints or large timing reports.
