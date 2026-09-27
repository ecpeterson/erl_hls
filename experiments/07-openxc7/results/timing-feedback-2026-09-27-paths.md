# Timing feedback path evidence, 2026-09-27

Saved path evidence; no new placement or board-clock qualification. Groups describe observed structure. A top-path sample does not reveal the next limit after removing every represented family.

## reference / Default

vivado, routed; requested period 5 ns. 40 distinct reported paths; worst 15.846 ns.

| Queried endpoints/through-points | Paths | Worst period, ns | Logic / route, ns | Cell arcs |
|---|---:|---:|---:|---:|
| global | 20 | 15.846 | 10.160 / 5.646 | 26 |
| RAM sources | 20 | 15.846 | 10.160 / 5.646 | 26 |
| DSP through-points | 20 | 15.846 | 10.160 / 5.646 | 26 |
| FF controls | 20 | 15.683 | 1.647 / 13.632 | 27 |

Query sets can overlap; the family table below deduplicates identical paths.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| state RAM → DSP/carry arithmetic (phi_field.x:21) → register | 12 | 15.698–15.846 | 15.783 |
| state RAM → DSP/carry arithmetic (phi_field.x:15) → register | 4 | 15.706–15.783 | 15.846 |
| state RAM → DSP/carry arithmetic → register | 4 | 15.715–15.755 | 15.846 |
| register → service/reduction control → register | 20 | 15.634–15.683 | 15.846 |

At 79.25 simulated cycles/step: 1.256 µs. Unchanged-cycle 1 MHz requires 12.618 ns.

| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |
|---:|---:|---:|
| 1 | 15.649 | 12.461 |
| 14 | 13.467 | 10.724 |

Worst path: 10.160 ns logic, 5.646 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

The XLS delays below exclude physical work outside each proc. Dependency edges establish dataflow, not the scheduler’s complete constraint system.

| Process | State reads | Estimated stage delays, ns | Multiply stages |
|---|---:|---|---|
| `__phi_halo_cell__SharedExecutor_0_next` | 0 | 0: 14.868, 1: 14.886 | umul.84636=0, umul.84635=0, smul.82239=0, smul.82261=0, smul.82295=0, smul.82338=0 |

## retimed / Default

vivado, routed; requested period 5 ns. 60 distinct reported paths; worst 17.100 ns.

| Queried endpoints/through-points | Paths | Worst period, ns | Logic / route, ns | Cell arcs |
|---|---:|---:|---:|---:|
| global | 20 | 17.100 | 8.644 / 8.228 | 30 |
| RAM sources | 20 | 15.468 | 7.566 / 7.825 | 13 |
| DSP through-points | 20 | 17.100 | 8.644 / 8.228 | 30 |
| FF controls | 20 | 16.939 | 1.834 / 14.724 | 28 |

Query sets can overlap; the family table below deduplicates identical paths.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| register → DSP/carry arithmetic → register | 14 | 16.947–17.100 | 17.062 |
| register → DSP/carry arithmetic → mailbox RAM | 6 | 16.952–17.062 | 17.100 |
| register → service/reduction control → register | 20 | 16.863–16.939 | 17.100 |
| state RAM → DSP/carry arithmetic → register | 7 | 14.979–15.468 | 17.100 |
| state RAM → other logic → register | 13 | 14.857–15.188 | 17.100 |

At 79.25 simulated cycles/step: 1.355 µs. Unchanged-cycle 1 MHz requires 12.618 ns.

| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |
|---:|---:|---:|
| 1 | 16.887 | 12.461 |
| 14 | 14.533 | 10.724 |

Worst path: 8.644 ns logic, 8.228 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

The XLS delays below exclude physical work outside each proc. Dependency edges establish dataflow, not the scheduler’s complete constraint system.

| Process | State reads | Estimated stage delays, ns | Multiply stages |
|---|---:|---|---|
| `__phi_halo_cell__SharedExecutor_0_next` | 0 | 0: 7.559, 1: 11.054 | umul.84636=0, umul.84635=0, smul.82239=1, smul.82261=1, smul.82295=1, smul.82338=1 |

## retimed-fabric / Default

vivado, routed; requested period 5 ns. 60 distinct reported paths; worst 17.422 ns.

| Queried endpoints/through-points | Paths | Worst period, ns | Logic / route, ns | Cell arcs |
|---|---:|---:|---:|---:|
| global | 20 | 17.422 | 10.205 / 7.286 | 31 |
| RAM sources | 20 | 15.202 | 7.576 / 7.589 | 14 |
| DSP through-points | 20 | 17.422 | 10.205 / 7.286 | 31 |
| FF controls | 20 | 16.896 | 1.912 / 14.733 | 32 |

Query sets can overlap; the family table below deduplicates identical paths.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| register → DSP/carry arithmetic → register | 18 | 17.320–17.422 | 17.339 |
| register → DSP/carry arithmetic → mailbox RAM | 2 | 17.332–17.339 | 17.422 |
| register → other logic → register | 18 | 16.820–16.896 | 17.422 |
| register → service/reduction control → register | 2 | 16.841–16.841 | 17.422 |
| state RAM → DSP/carry arithmetic → register | 4 | 14.865–15.202 | 17.422 |
| state RAM → other logic → register | 16 | 14.858–15.041 | 17.422 |

At 79.25 simulated cycles/step: 1.381 µs. Unchanged-cycle 1 MHz requires 12.618 ns.

| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |
|---:|---:|---:|
| 1 | 17.205 | 12.461 |
| 14 | 14.806 | 10.724 |

Worst path: 10.205 ns logic, 7.286 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

The XLS delays below exclude physical work outside each proc. Dependency edges establish dataflow, not the scheduler’s complete constraint system.

| Process | State reads | Estimated stage delays, ns | Multiply stages |
|---|---:|---|---|
| `__phi_halo_cell__SharedExecutor_0_next` | 0 | 0: 7.559, 1: 11.054 | umul.84636=0, umul.84635=0, smul.82239=1, smul.82261=1, smul.82295=1, smul.82338=1 |

## cell-only-zero / Default

vivado, routed; requested period 5 ns. 56 distinct reported paths; worst 15.151 ns.

| Queried endpoints/through-points | Paths | Worst period, ns | Logic / route, ns | Cell arcs |
|---|---:|---:|---:|---:|
| global | 20 | 15.151 | 8.584 / 6.221 | 27 |
| RAM sources | 20 | 15.144 | 10.194 / 4.880 | 25 |
| DSP through-points | 20 | 15.151 | 8.584 / 6.221 | 27 |
| FF controls | 20 | 14.904 | 1.653 / 12.729 | 24 |

Query sets can overlap; the family table below deduplicates identical paths.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| register → DSP/carry arithmetic → mailbox RAM | 7 | 15.056–15.151 | 15.144 |
| state RAM → DSP/carry arithmetic (phi_field.x:15) → register | 20 | 14.827–15.144 | 15.151 |
| register → DSP/carry arithmetic → register | 9 | 15.055–15.133 | 15.151 |
| register → service/reduction control → register | 20 | 14.719–14.904 | 15.151 |

At 79.25 simulated cycles/step: 1.201 µs. Unchanged-cycle 1 MHz requires 12.618 ns.

| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |
|---:|---:|---:|
| 1 | 14.962 | 12.461 |
| 14 | 12.876 | 10.724 |

Worst path: 8.584 ns logic, 6.221 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

The XLS delays below exclude physical work outside each proc. Dependency edges establish dataflow, not the scheduler’s complete constraint system.

| Process | State reads | Estimated stage delays, ns | Multiply stages |
|---|---:|---|---|
| `__phi_halo_cell__SharedExecutor_0_next` | 0 | 0: 10.092, 1: 10.046 | umul.84636=0, umul.84635=0, smul.82239=0, smul.82261=0, smul.82295=1, smul.82338=1 |

## selector-flat / Default

vivado, routed; requested period 5 ns. 20 distinct reported paths; worst 24.481 ns.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| register → serial selector → register | 20 | 23.833–24.481 | Unknown |

Worst path: 9.523 ns logic, 15.051 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

## selector-tree / Default

vivado, routed; requested period 5 ns. 20 distinct reported paths; worst 4.530 ns.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| register → other logic → register | 20 | 4.130–4.530 | Unknown |

Worst path: 0.647 ns logic, 3.586 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

## reference / Explore

vivado, routed; requested period 5 ns. 40 distinct reported paths; worst 15.794 ns.

| Queried endpoints/through-points | Paths | Worst period, ns | Logic / route, ns | Cell arcs |
|---|---:|---:|---:|---:|
| global | 20 | 15.794 | 11.650 / 4.048 | 26 |
| RAM sources | 20 | 15.794 | 11.650 / 4.048 | 26 |
| DSP through-points | 20 | 15.794 | 11.650 / 4.048 | 26 |
| FF controls | 20 | 15.387 | 1.700 / 13.279 | 28 |

Query sets can overlap; the family table below deduplicates identical paths.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| state RAM → DSP/carry arithmetic → register | 13 | 15.664–15.794 | 15.744 |
| state RAM → DSP/carry arithmetic (phi_field.x:15) → register | 4 | 15.667–15.744 | 15.794 |
| state RAM → DSP/carry arithmetic (phi_field.x:21) → register | 3 | 15.666–15.725 | 15.794 |
| register → service/reduction control → register | 20 | 15.337–15.387 | 15.794 |

At 79.25 simulated cycles/step: 1.252 µs. Unchanged-cycle 1 MHz requires 12.618 ns.

| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |
|---:|---:|---:|
| 1 | 15.597 | 12.461 |
| 14 | 13.423 | 10.724 |

Worst path: 11.650 ns logic, 4.048 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

The XLS delays below exclude physical work outside each proc. Dependency edges establish dataflow, not the scheduler’s complete constraint system.

| Process | State reads | Estimated stage delays, ns | Multiply stages |
|---|---:|---|---|
| `__phi_halo_cell__SharedExecutor_0_next` | 0 | 0: 14.868, 1: 14.886 | umul.84636=0, umul.84635=0, smul.82239=0, smul.82261=0, smul.82295=0, smul.82338=0 |

## cell-only-zero / Explore

vivado, routed; requested period 5 ns. 55 distinct reported paths; worst 15.237 ns.

| Queried endpoints/through-points | Paths | Worst period, ns | Logic / route, ns | Cell arcs |
|---|---:|---:|---:|---:|
| global | 20 | 15.237 | 8.360 / 6.513 | 26 |
| RAM sources | 20 | 15.118 | 10.172 / 4.876 | 25 |
| DSP through-points | 20 | 15.237 | 8.360 / 6.513 | 26 |
| FF controls | 20 | 15.089 | 2.012 / 12.533 | 26 |

Query sets can overlap; the family table below deduplicates identical paths.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| register → DSP/carry arithmetic → mailbox RAM | 4 | 15.040–15.237 | 15.207 |
| register → DSP/carry arithmetic → register | 10 | 15.030–15.207 | 15.237 |
| state RAM → DSP/carry arithmetic (phi_field.x:15) → register | 20 | 14.893–15.118 | 15.237 |
| register → other logic → mailbox RAM | 1 | 15.107–15.107 | 15.237 |
| register → other logic → register | 2 | 15.089–15.089 | 15.237 |
| register → service/reduction control → register | 18 | 14.957–15.009 | 15.237 |

At 79.25 simulated cycles/step: 1.208 µs. Unchanged-cycle 1 MHz requires 12.618 ns.

| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |
|---:|---:|---:|
| 1 | 15.047 | 12.461 |
| 14 | 12.949 | 10.724 |

Worst path: 8.360 ns logic, 6.513 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

The XLS delays below exclude physical work outside each proc. Dependency edges establish dataflow, not the scheduler’s complete constraint system.

| Process | State reads | Estimated stage delays, ns | Multiply stages |
|---|---:|---|---|
| `__phi_halo_cell__SharedExecutor_0_next` | 0 | 0: 10.092, 1: 10.046 | umul.84636=0, umul.84635=0, smul.82239=0, smul.82261=0, smul.82295=1, smul.82338=1 |

## Native reference / seed 1

nextpnr, routed; requested period 5 ns. 1 distinct reported paths; worst 41.000 ns.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| register → service/reduction control → register | 1 | 41.000–41.000 | Unknown |

At 79.25 simulated cycles/step: 3.249 µs. Unchanged-cycle 1 MHz requires 12.618 ns.

| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |
|---:|---:|---:|
| 1 | 40.489 | 12.461 |
| 14 | 34.845 | 10.724 |

Worst path: 3.300 ns logic, 37.700 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

Native text values are rounded to 0.1 ns.

## Native retimed/fabric / seed 1

nextpnr, routed; requested period 5 ns. 1 distinct reported paths; worst 45.200 ns.

| Observed family | Paths | Period range, ns | Untouched sample floor, ns |
|---|---:|---:|---:|
| register → other logic → mailbox RAM | 1 | 45.200–45.200 | Unknown |

At 79.25 simulated cycles/step: 3.582 µs. Unchanged-cycle 1 MHz requires 12.618 ns.

| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |
|---:|---:|---:|
| 1 | 44.637 | 12.461 |
| 14 | 38.414 | 10.724 |

Worst path: 3.400 ns logic, 41.700 ns interconnect. Clock/setup adjustments are included in the period, not these two data-path components.

Native text values are rounded to 0.1 ns.
