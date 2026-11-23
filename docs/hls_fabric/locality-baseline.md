# Reproducing the retained Snowflake locality baseline

This opt-in experiment preserves the accepted `local-admission-descriptors-2026-10-15` combination as a comparison point for future architectures. It does not change ordinary backend lowering. Build with the pinned compiler using [the normal prerequisites](building.md), OTP 28.0.2 and rebar3 3.24.0.

The cumulative pipeline retains source-derived receive capture and conditional decoding, phase specialization and barrier grant summaries, private consumer-payload erasure, admission predecode, and local admission/descriptors. The final pass registers actor-local free-cell/capacity proposals and masks, separates validity from private payload, and prepares ordinary/refill descriptors independently at the existing boundary. Consumer erasure remains part of this measured combination; its isolated result is not the combination's result. Later refill-selection, refill-payload-bank and owner-local-completion experiments are excluded.

## Generate and qualify

Run from the repository root, with a new output directory outside the checkout. `emit` generates the fixed 128-round fixture and seven source-bound proof plans, then checks the complete generated inventory against `experiments/local_admission/reference.json`. Eight hardware-generating files must match byte for byte. The inspection-only actor projection must match every layout field; its source-location identities remain freshly generated and validated by ordinary lowering. This establishes reproduction, not qualification.

```sh
rebar3 compile
python3 experiments/local_admission/baseline.py emit --stage "$HLS_ARTIFACT_ROOT/locality-reproduction"
```

Use the XLS tool directory and DSLX standard library from your installed toolchain and an explicit Yosys executable. Proofs run serially; each external proof stage has a 180-second limit. Completed and failed outputs are preserved, and an existing proof result cannot be silently overwritten. `--proof` selects one of the seven directories listed in `emission.json`.

```sh
python3 experiments/local_admission/baseline.py prove --stage "$HLS_ARTIFACT_ROOT/locality-reproduction" \
  --xls-tools "$XLS_TOOLS" --xls-stdlib "$XLS_STDLIB" --yosys "$YOSYS"
python3 experiments/local_admission/baseline.py release --stage "$HLS_ARTIFACT_ROOT/locality-reproduction"
python3 experiments/local_admission/baseline.py verify --stage "$HLS_ARTIFACT_ROOT/locality-reproduction"
```

Release invokes the original gates for every stage before creating `local/candidate-1/dslx`. These check exact source bindings, positive propositions and deliberately false controls. Unsupported source shapes fail closed. The final inventory includes the original RAM modules, actor wrapper and placement metadata; substituting raw XLS output for the backend RTL is not an equivalent reproduction.

The propositions quantify the typed component domains recorded in each plan. They include actual owner widths, private-payload noninterference and extracted coordinator/barrier init/step relations. Owner transition composition additionally relies on source/callsite review. Source extraction, XLS and Yosys remain trusted; these are not whole-network progress or native-netlist equivalence proofs. A released component candidate still needs whole-decoder full/reset witnesses and physical qualification before a new performance claim. Generation or proof release never starts a physical run.

## Retained evidence

The reference manifest retains all nine historical file digests, a location-independent projection-layout digest, and the external evidence inventory. The original backend RTL passed a 128-round, 1,125-correction witness with every event byte, including cycle numbers, equal to its parent. A separate reset-at-cycle-600 witness retained RAM, reset with eight outstanding operations, produced a fresh 128 rounds and 1,125 corrections, and stalled each output for 1,000 cycles. These are finite witnesses, not arbitrary-history theorems.

The original default Vivado 2024.2 XCZU7EV-2 out-of-context measurement used 173,704 LUTs, 102,075 FFs and 48 BRAM36s, with no BRAM18s. Its 6.409 ns period proxy and 274.48818897637796 mean cycles give 1.7591948031496063 µs per step. The proxy is `5 ns − WNS`; negative WNS means the original 5 ns constraint was not met. Hold and pulse checks passed and all nets routed without routing errors. These historical numbers apply to the bound RTL, original options and toolchain, and are not a promise for another build or a new measurement of this PR.

Keep experiment outputs in the [artifact archive](artifacts.md). The repository carries lowering, checks, fixed inputs and compact identities; it does not carry generated RTL, routing checkpoints or large timing reports.
