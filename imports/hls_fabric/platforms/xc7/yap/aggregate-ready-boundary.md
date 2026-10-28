# Aggregate delivery boundary

Registered before implementation, on top of DSP integration `dbc9c90`. This executes candidate B from [timing-next-cones.md](timing-next-cones.md); it is one boundary in the larger pipeline campaign.

The unchanged 2×1 attribution fixture delivers 924 aggregates per channel in each normal/stalled-output run, with zero blocked producer cycles. Half the transfers are adjacent. Predict unchanged 79.25 normal and 79.833333 stalled cycles/step with a one-entry forward-bypassing buffer: when empty and consumed immediately, it stays empty and can transfer again next cycle. This does not predict unchanged timing for every workload. A full buffer cannot accept a replacement on the cycle it drains. Test prolonged stalls and reset separately; preserve per-channel order and accepted data.

Expect the combinational dependency from executor-result occupancy through scheduler readiness to reduction-plane readiness to disappear. Budget about 438 FFs and less than 3% additional LUTs; mapped optimization may trim constant payload bits. No whole-core MHz improvement is predicted while arithmetic/RAM chains survive. The earlier 1–3 ns affected-family estimate remains unmeasured until a covered physical timing flow is available.

## Ownership and commit

- The reduction plane owns a completed aggregate until its output transfer is accepted.
- The buffer then retains it until scheduler acceptance. Empty bypass combines these transfers; neither commits actor state.
- The scheduler's existing pending slot retains the aggregate until issue. Existing actor-in-flight and output reservations continue to govern execution and state retirement.
- Round-robin ownership and commit order are unchanged. Reset discards the buffer along with the existing resettable experiment state.

This uses the [visibility-control paper](https://arxiv.org/abs/2607.18765)'s separation of pending ownership, available value and commit. It introduces no speculative reads, forwarding across uncommitted state, or duplicate state owner. Later dispatch pipelining must reserve an actor and output capacity before registering a grant; a stale eligibility snapshot is insufficient.

The screen changes only two final aggregate FIFO module bodies using XLS's existing depth-one bypass configuration. All application proc RTL stays byte-identical. Aggregate-source mux inputs remain unbuffered. Promote the same channel declaration to the generator only after the behavioral and structural screens.
