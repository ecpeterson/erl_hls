// A narrow scheduler shape instantiates production ownership helpers without
// selecting a RAM implementation or duplicating the generated actor ABI.
type ScheduledRequest = mailbox::ScheduledRequest;

// Extra control data verifies that fault suppression preserves unrelated fields.
struct SharedStep {
  machine: ActorState, effects_valid: bool, dispatched: bool,
  directive: Directive, egress_blocked: bool, phase_boundary: bool, marker: u8,
}

// Only fields used by indexed helpers are included in this executable witness.
struct SharedState<ACTOR_COUNT: u32, PRODUCER_COUNT: u32> {
  indexed_context: IndexedContext[ACTOR_COUNT],
  indexed_candidates: bool[ACTOR_COUNT], indexed_cursor: u32,
  pending: ScheduledRequest[PRODUCER_COUNT], pending_valid: bool[PRODUCER_COUNT],
}
