# Parallel reduction publication

The public source-fragment proof already closes the selected exchange over a family. Each member has the same proved source-port set, with one ordered contribution per port. The private planner obtains that set from the member's checked incoming lanes, then selects its outgoing lanes carrying only those ports. Ordinary lanes remain on the existing router; the public mailbox/executor implementation is unchanged.

Each actor retains one batch reservation. The generated drainer captures the batch, publishes its prefix, drains any ordinary tail, and retires the reservation. Each activation publishes a contiguous source-prefix segment ending before a destination repeats. D6's four destinations accept together when ready. For consecutive aliases `A,A,B,B`, the segments are `A`, `A,B`, `B`; pairing first occurrences `A,B` would wrongly allow blocked `B` to prevent the earlier second `A`. XLS's per-output completion bookkeeping prevents accepted destinations from receiving duplicates while a sibling stalls. The RTL regression checks this behavior directly.

A private typed `ReductionFrame` adapter discards the already-routed port after the observable Egress boundary. It uses the first PR's checked stateless scheduling helper and adds no register. The old router no longer owns those channels. Batch capture and credit retirement are explicit activations; this avoids making profiler attribution depend on a partially accepted input handshake. These costs must be included in the full matched measurement, not subtracted by assumption.

The profiler keys publications by channel and cycle. An observed publication ordinal is a label, not a source-order promise between distinct lanes. Per-lane payload order continues to identify contributions across packetization and collection. The latest-prerequisite overlay remains descriptive; simultaneous publications create no invented causal edges.

Validation covers independent and aliased destinations, stalled prefix lanes, stalled ordinary tails, empty and ordinary-only batches, held credits and coordinated reset. Complete D6 simulation and board synthesis measure net benefit. The existing two-device CI witnesses retain aliased geometry and reset coverage with real decoder modules.

The matched first PR leaves 338.4 ns/step of within-batch spacing unchanged. Before running the parallel tile, the net improvement forecast is 0.25–0.40 µs/step from its 2.0426 µs baseline. Capturing the batch adds one activation; removing the prefix's ordinary router offsets much of that initial cost. Credit retirement is explicit and may expose a new wait. The full capture, not this arithmetic, decides the gain.

| Source destination order | Publication segments |
|---|---|
| A, B, C, D | A+B+C+D |
| A, B, A, B | A+B; A+B |
| A, A, B, B | A; A+B; B |

The last case's stalled-B regression requires both A effects to be accepted. This rejects a schedule that creates a wait on a later blocked B before offering the earlier second A. It is a local ordering guarantee, not a general deadlock proof for arbitrary bounded application protocols.
