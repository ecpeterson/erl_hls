# Periodic repetition code

`phi_repetition_topology:topology(N, Threshold)` builds a phase-flip repetition code: **N data qubits, N weight-two X checks and N phi actors**. Data faults are Z errors. The line alternates `data[X] — syndrome[X] — data[X+1]`, with indices modulo N. Only east/west communication exists; there are no north/south ports, contributions or self-sends.

N must be 2–65,535 to fit the coordinate envelope. N=2 retains two distinct labelled edges to the same neighbor; N≥3 gives east and west distinct neighbors. These are periodic ends. An open chain needs explicit endpoint checks and decoder absorption rules.

## Noise, decoding and corrections

Each data actor draws one Bernoulli fault per measurement round and reports it to its two adjacent checks. Each check combines those reports with its current and previous measurement-fault bits to form a detection event. `Threshold` is an unsigned 32-bit integer: an error occurs when the PRNG word is smaller. `topology(N)` uses probability approximately one half to exercise the protocol; choose an explicit lower threshold for error-rate experiments.

The single phi family runs twelve diffusion updates per measurement round, followed by comparison and movement. Its two-layer Q15.16 field uses η=1/2 and a normalized two-neighbor recurrence:

```text
phi0' = round((4*phi0 + 2*phi1 + east0 + west0) / 8) + anyon
phi1' = round((  phi0 + 5*phi1 + east1 + west1) / 8)
```

Here `anyon` is zero or one in field units. Rounding ties go away from zero; results saturate to signed 32-bit scaled integers. A uniform field without an anyon remains uniform. The two-layer approximation and fixed update count are workload parameters, not an established decoding threshold or convergence guarantee.

`decoder_events` emits `phi_correction` and `phi_status`. `correction_update/2` maps an east move from check X to data `(X+1) rem N`, or a west move to data X, with a Z update. The `control_router` accepts addressed Pauli queries/updates and noise cutoff; measurements leave through `data_measurements`. Applying correction events, arranging a cooperative closeout and evaluating the logical result remain responsibilities of the experiment driver.

## Running and measuring

The line and grid actors share their callbacks, specialized at compile time. `phi_repetition_topology:profile(N)` places each of the three families behind one shared RAM scheduler and uses source-fragment reductions for phi. Changing N changes actor population without replicating executors. The existing two-dimensional examples retain four neighbors and their original recurrence.

With rebar3, OTP 28, Icarus and an XLS tool directory:

```sh
python3 tools/run_repetition_profile.py _build/repetition/n3 --cells 3 --xls /path/to/xls
```

The runner generates the complete physical-noise topology, executes BEAM and RTL through round 32, and requires identical per-actor corrections/status under both continuous and stalled output readiness. It measures whole-line progress over rounds 8–32. The testbench observes corrections; it does not feed them back or certify logical-memory performance.

Add `--yosys /path/to/yosys` for an XC7 area estimate. The generated shell retains control and measurement ports, so synthesis includes their hardware even though the throughput test leaves control idle. The estimate excludes board transport, debug gateway and physical I/O; it establishes neither routing feasibility nor clock frequency. Optional `--table /path/to/xc7_7030.tsv` selects the calibrated scheduling model with an XLS build that supports it. Sources, build receipts, simulation witnesses and results remain beneath the chosen build directory.

Start capacity exploration with N=3 and N=8. Choose a board population from mapped resources and routed step time, with room for the deployment shell; do not infer it by scaling the old two-plane 2×1 replay fixture.

The [initial capacity measurements](../experiments/07-openxc7/results/repetition-code-2026-09-26.md) cover N=2, 3 and 8.
