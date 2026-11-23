# Actor-local output reservations

The target is progress preservation relative to direct actors with stated finite capacities, not deadlock freedom for an arbitrary Erlang program. One grid-wide lookahead credit is a measurement reference, not a scalable execution policy.

The candidate reserves one complete batch before issue: an actor is excluded while either in flight or holding an undrained batch. No-effect retirement immediately releases the reservation; an effect-producing retirement transfers it into a per-actor outbox. A dedicated return producer releases that actor only. The scheduler polls all producers nonblockingly and consumes all registered returns independently of mailbox admission.

The shared dispatch stream contains only already-reserved batches. Its destination therefore has room even if another actor's output is blocked. Each outbox drains independently, preserving its actor's order; the same direct-placement router handles its effects. A completed callback cannot hold up shared retirement awaiting an unrelated destination. Fair executor selection, finite RAM latency and independent credit acceptance are still assumptions. The application or a full declared mailbox may still deadlock; transport head-of-line blocking must be checked separately.

A small witness holds three updates for one actor while the other repeatedly completes 24 three-effect updates, then reverses identities. Both placements must match BEAM state accumulation and ordering and recover from reset with unread output. Public mailbox observations must expose occupied outboxes. Full D3 retains ordinary reductions, correction application, closeout, both clock ratios and public debug probes.

Do not pass a partially owned channel-output array through another proc. In the native XLS composition, the unused outbox-wrapper outputs replaced the message producers with zero-valued sources. The corrected bank owns a separate credit array; scalar relays bind its credits to dedicated scheduler producer endpoints. This is a wiring boundary, not a second mailbox.

Compare the new complete-device mapping and paced intervals with both #12's coordinated shared-RAM result and the direct reference. Keep historical routed decoder-only timing separate. Use one matching mapping seed first; repeat only if results or naming sensitivity warrant it.
