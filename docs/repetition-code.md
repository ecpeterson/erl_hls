# Periodic repetition code

`phi_repetition_topology:topology(N, NoiseRate)` builds a periodic line of N data qubits, N weight-two X-check syndromes and N phi cells. Neighbors lie along the line; there are no orthogonal sends or Z-check cells. Coordinates remain two-dimensional with a unit second dimension so ordinary topology routing applies.

The actors specialize the phi/noise protocols and typed messages. Noise seeds, initial state and callback semantics are shared between CPU and generated hardware. `phi_repetition_topology:profile/1` selects dedicated actors; `xls_topology_dslx` generates the communicating `Top` proc.

Use `phi_repetition_topology` CPU helpers for complete rounds and closeout. The example is a compiler and protocol workload; fit and clock frequency require synthesis for the chosen FPGA.
