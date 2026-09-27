# Physical paths and feedback budget, 2026-09-27

Saved path evidence; no new placement or board-clock qualification. Groups describe observed structure. A top-path sample does not reveal the next limit after removing every represented family.

## Shared core, DSP arithmetic

vivado, routed; requested period 5 ns. 20 distinct reported paths; worst 15.846 ns.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| state RAM → DSP/carry arithmetic (phi_field.x:21) → register | 12 | 15.698–15.846 | 15.783 |
| state RAM → DSP/carry arithmetic (phi_field.x:15) → register | 4 | 15.706–15.783 | 15.846 |
| state RAM → DSP/carry arithmetic → register | 4 | 15.715–15.755 | 15.846 |

At 79.25 simulated cycles/step: 1.256 µs. Unchanged-cycle 1 MHz requires 12.618 ns.

| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |
|---:|---:|---:|
| 1 | 15.649 | 12.461 |
| 14 | 13.467 | 10.724 |
| 29 | 11.601 | 9.238 |

Worst path: 10.160 ns logic, 5.646 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

The XLS delays below exclude physical work outside each proc. Dependency edges establish dataflow, not the scheduler’s complete constraint system.

| Process | State reads | Estimated stage delays, ns | Multiply stages |
|---|---:|---|---|
| `__phi_halo_cell__SharedExecutor_0_next` | 0 | 0: 14.868, 1: 14.886 | umul.84636=0, umul.84635=0, smul.82239=0, smul.82261=0, smul.82295=0, smul.82338=0 |

## Shared core, LUT arithmetic

vivado, routed; requested period 5 ns. 20 distinct reported paths; worst 15.090 ns.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| state RAM → carry arithmetic → register | 20 | 14.614–15.090 | Unknown |

At 79.25 simulated cycles/step: 1.196 µs. Unchanged-cycle 1 MHz requires 12.618 ns.

| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |
|---:|---:|---:|
| 1 | 14.902 | 12.461 |
| 14 | 12.824 | 10.724 |
| 29 | 11.047 | 9.238 |

Worst path: 6.150 ns logic, 8.640 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

## Native shared-core control, seed 2

nextpnr, routed; requested period 40 ns. 1 distinct reported paths; worst 38.800 ns.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| register → service/reduction control → register | 1 | 38.800–38.800 | Unknown |

At 79.25 simulated cycles/step: 3.075 µs. Unchanged-cycle 1 MHz requires 12.618 ns.

| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |
|---:|---:|---:|
| 1 | 38.317 | 12.461 |
| 14 | 32.975 | 10.724 |
| 29 | 28.406 | 9.238 |

Worst path: 3.500 ns logic, 35.300 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

Native text values are rounded to 0.1 ns.
