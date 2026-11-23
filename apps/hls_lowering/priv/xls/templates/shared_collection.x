// Return the collector's state authority when an owned callback retires.
// No admission can mutate this slot while that callback is in flight.
fn collection_retire<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, valid: bool,
    slot: u32, machine: ActorState) -> SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
  SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
    collection_initialized: if valid { update(state.collection_initialized, slot, true) }
      else { state.collection_initialized },
    collection_context: if valid { update(state.collection_context, slot, machine) }
      else { state.collection_context },
    ..state
  }
}

// Use precisely the normal admission choice. An empty mailbox and no owned or
// newly issued work prevent overtaking a message, entry or completion event.
// Invalid members, wrong keys, early traffic and malformed frames fall back.
fn collection_admit<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, intent: mailbox::Admission,
    issuing: bool, issue_slot: u32) -> (bool, ReductionState) {
  let slot = intent.slot;
  let safe = intent.valid && state.occupied[slot] == u8:0 &&
    !state.in_flight[slot] && !(issuing && issue_slot == slot);
  let result = collection_try(state.collection_context[slot], state.pending[intent.producer].frame);
  (safe && result.0, result.1)
}

// Consume exactly one producer holding slot. Collection and retirement may
// affect different actors in the same step; update only the selected slot.
// The actor's ordinary completion still reserves executor/effect capacity.
fn collection_commit<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, intent: mailbox::Admission,
    collected: (bool, ReductionState)) -> SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
  if !collected.0 { state } else {
    let slot = intent.slot;
    let context = ActorState { reduction: collected.1, ..state.collection_context[slot] };
    SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      collection_context: update(state.collection_context, slot, context),
      internal_candidates: update(state.internal_candidates, slot,
        collected.1.status == ReductionStatus::COMPLETE),
      pending_valid: update(state.pending_valid, intent.producer, u1:0),
      admission_cursor: if intent.producer + u32:1 == PRODUCER_COUNT { u32:0 }
        else { intent.producer + u32:1 },
      ..state
    }
  }
}
