# Independent actor outboxes

A shared executor must not wait for one actor's output while other actors have runnable work. Generated `SharedService` offers `PER_ACTOR_EGRESS=true` for compositions that reserve one complete output batch per actor. The default remains the topology generator's shared batch sequencer.

An actor reserves its outbox before its callback issues. Its in-flight flag protects that reservation during execution. Retirement commits the state and either fills the outbox or releases an unused reservation. The actor becomes eligible again after its batch drains; other actors retain their own eligibility. Effects from one actor remain in source order.

Use `xls_actor_outbox_dslx:emit(Module)` alongside the imported actor module to emit the corresponding outbox bank. Its proc name comes from `name/1`; its parameter is actor count. Connect the scheduler's batch output, one independent `Egress` output per actor and a separate credit-output array. Forward each credit through `mailbox::RequestRelay` to a dedicated scheduler producer; those producers must not carry mailbox requests. Do not pass a partly used producer array to another proc: every output endpoint must have exactly one writer. Keep generated channel outputs registered.

Each returned `ScheduledRequest` has `credit=true` and names the actor in `slot`. Return it exactly once, after the batch's last effect is accepted. Credits terminate at scheduler metadata, independently of destination mailbox admission. The outbox bank provides this protocol. A custom implementation must provide the same capacity and ordering guarantees; switching the parameter alone is insufficient.

The storage cost grows with actor count and maximum batch size. This isolates output pressure within a shared executor; it does not establish deadlock freedom for the application or its surrounding transport. A progress argument still needs explicit mailbox/output capacities, independent credit delivery, fair scheduling and eventual RAM responses. Downstream routing must not introduce additional blocking between unrelated actors. Compare with direct actors under those same assumptions, rather than with unbounded ERTS mailboxes.

`tools/test_actor_outboxes.sh "$XLS_ROOT"` compares direct and RAM-backed actors with BEAM at two pipeline depths. One actor retains blocked output while the other completes 24 three-effect updates, then the roles reverse. It checks effect order, state accumulation, public egress-wait observations and reset with unread output.
