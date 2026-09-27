# Periodic repetition-code capacity probe

The [line workload](../../../docs/repetition-code.md) runs actual data-Z and measurement noise, weight-two X checks and phi updates. N counts data/check sites separately: N=8 has sixteen physical qubits and twenty-four actors. Each family shares one RAM executor; phi uses source-fragment reductions. There are no orthogonal channels or contributions.

Native XLS uses two stages, requested II=1 and the **unit scheduling model** for this portable functional/capacity baseline. This run does not measure calibrated stage delay or routed clock frequency. The mapped shell retains control ingress and measurement egress; it excludes board links, the debug gateway and physical I/O. [Receipts](repetition-code-2026-09-26.json) record sources, generated RTL, tools, mapping inputs and witness hashes.

## Measurements

| N | Physical qubits | LUTs | FFs | DSPs | RAMB18 / RAMB36 | Mean cycles/round | With output stalls |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 4 | — | — | — | — | 93.250 | 93.500 |
| 3 | 6 | 24,468 | 16,390 | 0 | 37 / 6 | 123.417 | 123.875 |
| 8 | 16 | 34,396 | 20,229 | 0 | 37 / 6 | 250.208 | 253.458 |

Every actor's corrections/status sequence through round 32 matches BEAM, with 85, 121 and 333 events respectively. Means cover whole-line completion from rounds 8 to 32. The stalled sink refuses seven of every seventeen cycles. These are single deterministic trajectories and single unrenamed mappings; they do not estimate noise-seed or mapping-seed sensitivity.

N=3 and N=8 use approximately 31% and 44% of the Z-7030's 78,600 physical LUTs, making them capacity candidates rather than qualified board images. Sustaining a mean 1 MHz round rate with these cycle counts would require approximately 123.4 and 250.2 MHz respectively, before deployment overhead. No such clock is established here. Shared execution keeps resources bounded as N grows but does not preserve the round rate.

For scale, the earlier [2×1, two-plane replay reference](architecture-2026-09-26.md#measurements) used 33,171 LUTs, 22,008 FFs and 56 DSPs at 79.25 cycles/round. Its geometry, syndrome source, executor population and scheduling model differ. The new line results are not an optimization delta against that workload.

## Removing the general tie selector

Inspection of the first mapping identified all four DSPs in the shared phi executor's multiply-high tie ranking. For a line the valid winner masks are only 0, east, west and both. A unique winner is immediate; a tie selects east or west from random bit 30, exactly matching the old low-31-bit multiply-high rule.

Prediction before the change: eliminate four DSPs while preserving event traces and cycle counts. Both predictions hold. A separate BEAM check compares the two selectors across all four masks and 1,024 PRNG seeds.

| N | General → line selector LUTs | FFs | DSPs | Mean cycles/round |
| --- | ---: | ---: | ---: | ---: |
| 3 | 24,154 → 24,468 | 16,401 → 16,390 | 4 → 0 | 123.417 → 123.417 |
| 8 | 34,522 → 34,396 | 20,240 → 20,229 | 4 → 0 | 250.208 → 250.208 |

The LUT changes have opposite signs (+1.3%, −0.4%); this is a simpler two-edge selector and a DSP saving, not a consistent LUT improvement. Routing was not repeated, so there is no clock-improvement claim.

## Reproduction and boundaries

From the repository root, with the intended XLS and Yosys executables:

```sh
python3 tools/run_repetition_profile.py _build/repetition/n3 --cells 3 --xls /path/to/xls --yosys /path/to/yosys
python3 tools/run_repetition_profile.py _build/repetition/n8 --cells 8 --xls /path/to/xls --yosys /path/to/yosys
```

The topology, seed schedule and threshold are explicit in `phi_repetition_topology`. Independent tests check fault incidence, measurement-fault temporal boundaries, two-member barriers, periodic correction coordinates and normalized/saturating field arithmetic. DSLX/JIT checks compare the recurrence with a widened oracle. Existing grid actors generate the same DSLX operations after source-location and variable-name normalization; the full suite passes 1,181 EUnit tests. Source contracts, Dialyzer and locally regenerated DSLX goldens pass. CI adds N=3 and retains D3.

This witness observes corrections without applying them. An experiment driver must still close the correction/measurement loop, and decoder quality needs separate study of the two-layer field, twelve-update schedule and convergence. Board selection additionally needs complete-shell routing and step-time measurements.
