// Retain pure decoding at exactly the edge which captures its raw request.
// While pending_valid is true neither representation may be overwritten.
fn collection_capture_inputs<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
    pending: ScheduledRequest[PRODUCER_COUNT], valid: bool[PRODUCER_COUNT])
    -> CollectionInput[PRODUCER_COUNT] {
  unroll_for! (producer, inputs): (u32, CollectionInput[PRODUCER_COUNT]) in u32:0..PRODUCER_COUNT {
    update(inputs, producer, if !state.pending_valid[producer] && valid[producer] {
      collection_decode(pending[producer].frame)
    } else { inputs[producer] })
  }(state.collection_inputs)
}

// A retiring callback observes previously committed protocol faults. Its new
// opening is validated by the collector only after its ownership command commits.
fn collection_resolve<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, slot: u32, step: SharedStep) -> SharedStep {
  let failure = hls_failure::first(step.machine.failure, state.collection_context[slot].failure);
  if !hls_failure::failed(failure) { step } else {
    SharedStep { machine: ActorState { failure, enter_pending: false, ..step.machine },
      effects_valid: false, dispatched: false, directive: Directive::FAIL,
      egress_blocked: false, phase_boundary: false, ..step }
  }
}

// Current callback results produce immutable commands. Only a command from the
// previous activation may change the collector's bank in this activation.
fn collection_retire<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, valid: bool,
    slot: u32, machine: ActorState) -> SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
  let target = state.collection_command.slot;
  let context = state.collection_context[target];
  let bank = CollectionBank { reduction: context.reduction,
    opened: state.collection_owners.opened[target], failure: context.failure };
  let controlled = if state.collection_command.valid {
    collection_control(bank, state.collection_command.control)
  } else { bank };
  let failure = hls_failure::first(controlled.failure,
    if state.collection_command.valid { state.collection_command.failure } else { hls_failure::NONE });
  let updated = CollectionContext { reduction: controlled.reduction, failure,
    phase: if state.collection_command.valid { state.collection_command.phase } else { context.phase },
    enter_pending: if state.collection_command.valid { state.collection_command.enter_pending } else { context.enter_pending } };
  let consumed = valid && state.collection_owners.consuming[slot];
  let opening = valid && (!state.collection_owners.actor_opened[slot] || consumed) &&
    machine.reduction.status == ReductionStatus::OPEN;
  let command = CollectionControl { release: consumed,
    release_key: state.collection_context[slot].reduction.key, open: opening,
    opening: machine.reduction };
  let candidates = if state.collection_command.valid {
    update(state.internal_candidates, target,
      !hls_failure::failed(state.collection_command.failure) &&
      (hls_failure::failed(failure) || (controlled.opened && controlled.reduction.status == ReductionStatus::COMPLETE)))
  } else { state.internal_candidates };
  SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
    collection_context: if state.collection_command.valid { update(state.collection_context, target, updated) }
      else { state.collection_context },
    collection_owners: CollectionOwners<ACTOR_COUNT> {
      initialized: if state.collection_command.valid { update(state.collection_owners.initialized,target,true) }
        else { state.collection_owners.initialized },
      opened: if state.collection_command.valid { update(state.collection_owners.opened,target,controlled.opened) }
        else { state.collection_owners.opened },
      actor_opened: if valid { update(state.collection_owners.actor_opened,slot,
        machine.reduction.status != ReductionStatus::IDLE) } else { state.collection_owners.actor_opened },
      consuming: if valid { update(state.collection_owners.consuming,slot,false) } else { state.collection_owners.consuming },
    },
    internal_candidates: if consumed { update(candidates,slot,false) } else { candidates },
    collection_command: CollectionCommand { valid, slot, control: command,
      phase: machine.phase, enter_pending: machine.enter_pending, failure: machine.failure },
    ..state
  }
}

// Ordinary admission alone depends on mailbox space. Contributions have a
// separate fair arbiter and may commit beside an ordinary admission.
fn collection_select_ordinary<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>) -> mailbox::Admission {
  let eligible = unroll_for! (producer, flags): (u32, bool[PRODUCER_COUNT]) in u32:0..PRODUCER_COUNT {
    update(flags, producer, state.pending_valid[producer] && !collection_reserved(state.pending[producer].frame))
  }(zero!<bool[PRODUCER_COUNT]>());
  mailbox::select_admission(state.occupied, state.used, state.admission_cursor,
    state.pending, eligible, false, u32:0, false, u32:0)
}

// Probe reserved producers fairly without reading actor banks during arbitration.
// A selected input can remain blocked; commit advances the cursor after that probe.
// Collector admission never selects a mailbox cell or reads its occupancy.
fn collection_grant<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>) -> mailbox::ProducerGrant<PRODUCER_COUNT> {
  let eligible = unroll_for! (producer, flags): (u32, bool[PRODUCER_COUNT]) in u32:0..PRODUCER_COUNT {
    let request = state.pending[producer];
    update(flags, producer, state.pending_valid[producer] && request.slot < ACTOR_COUNT &&
      !request.credit && collection_reserved(request.frame))
  }(zero!<bool[PRODUCER_COUNT]>());
  mailbox::producer_grant(eligible, state.collection_cursor)
}

// Carry the same committed grant to request selection and cursor bookkeeping.
fn collection_select<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>) -> mailbox::Admission {
  let grant = collection_grant(state);
  let request = mailbox::granted_request(grant, state.pending);
  let valid = grant.valid;
  mailbox::Admission { valid, producer: mailbox::granted_index(grant.mask),
    slot: if valid { request.slot } else { u32:0 }, physical: u8:0 }
}

// A selected frame folds only when the committed bank accepts it and control
// does not own its write. Blocked frames remain pending; accepted malformed frames
// fault here without ordinary fallback. Reducer poison still drains its members.
fn collection_admit<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    committed: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, intent: mailbox::Admission)
    -> (bool, ReductionState, hls_failure::Code) {
  // Fold and ownership control read the same committed bank snapshot. Control
  // wins a same-bank write conflict; retain that contribution for the next visit.
  // No-op callback metadata may still update beside a fold on the same actor.
  // intent must be collection_select(committed), from this same snapshot.
  let control_writes = committed.collection_command.valid &&
    (committed.collection_command.control.open || committed.collection_command.control.release ||
      hls_failure::failed(committed.collection_command.failure));
  let conflict = control_writes && committed.collection_command.slot == intent.slot;
  let grant = collection_grant(committed);
  let frame = mailbox::granted_request(grant, committed.pending).frame;
  let input = collection_selected_input(grant, committed.collection_inputs);
  let context = committed.collection_context[intent.slot];
  let bank = CollectionBank { reduction: context.reduction,
    opened: committed.collection_owners.opened[intent.slot], failure: context.failure };
  let accepted = intent.valid && collection_reserved(frame) && !conflict &&
    collection_accepts_input(bank, input);
  let folded = collection_fold_input(bank, input, accepted);
  (accepted, folded.reduction, folded.failure)
}

// Merge an accepted frame after registered control. Every cheap-valid probe moves
// the cursor, including acceptance/control stalls; only consumption clears pending.
// A continuously cheap-eligible producer is retried within PRODUCER_COUNT enabled steps.
fn collection_commit<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, intent: mailbox::Admission,
    collected: (bool, ReductionState, hls_failure::Code)) -> SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
  let updated = if !collected.0 { state } else {
    let slot = intent.slot;
    let context = CollectionContext { reduction: collected.1, failure: collected.2, ..state.collection_context[slot] };
    let new_failure = !hls_failure::failed(state.collection_context[slot].failure) && hls_failure::failed(collected.2);
    SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      collection_context: update(state.collection_context, slot, context),
      internal_candidates: update(state.internal_candidates, slot, new_failure ||
        (if hls_failure::failed(collected.2) { state.internal_candidates[slot] } else {
          state.collection_owners.opened[slot] && collected.1.status == ReductionStatus::COMPLETE })),
      ..state
    }
  };
  SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
    pending_valid: mailbox::clear_pending(state.pending_valid, intent.producer, collected.0),
    collection_cursor: if intent.valid {
      if intent.producer + u32:1 == PRODUCER_COUNT { u32:0 } else { intent.producer + u32:1 }
    } else { state.collection_cursor },
    ..updated
  }
}

// Only the completion in the issued snapshot owns release. Retirement cannot
// target this actor while it is eligible; later arrivals must not reclassify its
// ticket. Keep this decision independent of this cycle's collector updates.
fn collection_issue<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    committed: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
    updated: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, internal: bool, slot: u32)
    -> SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
  SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
    collection_owners: CollectionOwners<ACTOR_COUNT> {
      consuming: if internal { update(updated.collection_owners.consuming, slot,
        committed.collection_owners.opened[slot] && committed.collection_context[slot].reduction.status == ReductionStatus::COMPLETE) }
        else { updated.collection_owners.consuming }, ..updated.collection_owners }, ..updated
  }
}
