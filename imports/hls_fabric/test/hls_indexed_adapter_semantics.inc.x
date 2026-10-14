import indexed_collection_opening_reference as opening_reference;

// Command writes reproduce the pure full row and leave an unrelated actor intact.
fn assert_frame_command_commit(context: IndexedContext, admission: IndexedAdmission) {
  assert_eq(admission.representative_write && admission.deferred_write, false);
  let state = SharedState<u32:2,u32:1> { indexed_context:[context, context],
    pending_valid:[true], ..zero!<SharedState<u32:2,u32:1>>() };
  let intent = mailbox::Admission { valid:true, producer:u32:0, slot:u32:0, physical:u8:0 };
  let actual = indexed_commit(state, state, intent, admission);
  assert_eq(actual.indexed_context[u32:0], if admission.consumed { admission.context } else { context });
  assert_eq(actual.indexed_context[u32:1], context);
}

// Construct the same on-wire contribution decoded by the generated source lift.
fn frame(key: u32, member: u32, value: u8) -> axis::Frame {
  axis::pack(Tag::PIECE as u8, bits_from_piece(Piece { key, member, value }))
}

// A controlled committed boundary exercises source eligibility independently of proc scheduling.
fn machine(epoch: u32, future: bool, opened: bool) -> ActorState {
  ActorState {
    phase: if opened { Phase::COLLECTING } else { Phase::WAITING },
    data: Cell { epoch, future, current_mode: u8:0 },
    gather: GatherState { progress: GatherProgress {
      status: if opened { GatherStatus::OPEN } else { GatherStatus::IDLE },
      site: INDEXED_SITE, key: epoch, expected: u3:3, remaining: u8:2,
      ..zero!<GatherProgress>() }, values: u24:0 },
    ..zero!<ActorState>()
  }
}

// Early storage is validated before completion, and its row remains borrowed through retirement.
#[test]
fn source_open_and_completion_test() {
 let c=indexed_control(zero!<IndexedContext>(),machine(u32:7,true,false));
 let f=frame(u32:7,u32:0,u8:42);
 let a=indexed_push(c,f,indexed_decode(f),u32:5);
 assert_eq(a.consumed, true); assert_eq(a.write_valid, true); assert_eq(a.write.addr,u32:10);assert_eq(a.write.mask,u3:1);assert_eq(a.write.data as u8,u8:42);
 assert_eq(!indexed_ticket(a.context).valid, true);
 let c=indexed_control(a.context,machine(u32:7,true,true));
 let f=frame(u32:7,u32:1,u8:43);
 let a=indexed_push(c,f,indexed_decode(f),u32:5);
 assert_eq(indexed_ticket(a.context).valid, true);
 let s=SharedState<u32:1,u32:1>{indexed_context:[a.context],..zero!<SharedState<u32:1,u32:1>>()};
 let s=indexed_issue(s,s,zero!<mailbox::Admission>(),zero!<IndexedAdmission>(),true,u32:0);
 assert_eq(s.indexed_context[u32:0].consuming, true);
 assert_eq(!indexed_ticket(s.indexed_context[u32:0]).valid, true);
 let s=indexed_retire(s,true,u32:0,machine(u32:8,true,false));
 assert_eq(!s.indexed_context[u32:0].consuming, true);
 assert_eq(s.indexed_context[u32:0].banks.banks[u32:0].status,indexed_collection_core::Status::FREE);
}
// A new source context may revoke a previously authorized provisional key.
#[test]
fn provisional_invalidation_test() {
 let c=indexed_control(zero!<IndexedContext>(),machine(u32:7,true,false));
 let f=frame(u32:8,u32:0,u8:42);
 let a=indexed_push(c,f,indexed_decode(f),u32:0);
 let c=indexed_control(a.context,machine(u32:7,false,true));
 assert_eq(indexed_failure(c),dispatch(f, c.machine.phase, c.machine.data).4);
 assert_eq(hls_failure::failed(indexed_failure(c)), true);
 let s=SharedState<u32:1,u32:1>{indexed_context:[c],..zero!<SharedState<u32:1,u32:1>>()};
 let step=SharedStep{machine:machine(u32:7,false,true),effects_valid:true,..zero!<SharedStep>()};
 let failed=indexed_resolve(s,u32:0,step);
 assert_eq(!failed.effects_valid, true); assert_eq(failed.directive,Directive::FAIL);
}
// Entry and continuation boundaries delay revalidation without blocking publication traffic.
#[test]
fn blocked_entry_revalidation_test() {
 let c=indexed_control(zero!<IndexedContext>(),machine(u32:7,true,false));
 let f=frame(u32:8,u32:0,u8:42);
 let a=indexed_push(c,f,indexed_decode(f),u32:0);
 let c=indexed_control(a.context,ActorState{enter_pending:true,next_event:u8:1,..machine(u32:6,false,false)});
 assert_eq(indexed_failure(c),hls_failure::NONE);
 let f=frame(u32:8,u32:1,u8:43);
 let a=indexed_push(c,f,indexed_decode(f),u32:0);
 assert_eq(a.consumed, true); assert_eq(!indexed_ticket(a.context).valid, true);
 let c=indexed_control(a.context,machine(u32:8,false,true));
 assert_eq(indexed_failure(c),hls_failure::NONE); assert_eq(indexed_ticket(c).valid, true);
}
// A third unretained key is an explicit bound violation, reported at the next stable boundary.
#[test]
fn deferred_third_key_test() {
 let m=ActorState{enter_pending:true,..machine(u32:0,false,false)};
 let c=indexed_control(zero!<IndexedContext>(),m);
 let f=frame(u32:7,u32:0,u8:42);
 let a=indexed_push(c,f,indexed_decode(f),u32:0);
 let f=frame(u32:8,u32:0,u8:43);
 let a=indexed_push(a.context,f,indexed_decode(f),u32:0);
 let f=frame(u32:9,u32:0,u8:44);
 let a=indexed_push(a.context,f,indexed_decode(f),u32:0);
 assert_eq(a.consumed, true); assert_eq(!a.write_valid, true); assert_eq(indexed_failure(a.context),hls_failure::NONE);
 let c=indexed_control(a.context,machine(u32:7,true,false));
 assert_eq(indexed_failure(c),hls_failure::REDUCTION_PROTOCOL);
}
// Same-actor retirement wins metadata ownership; another activation may accept the held input.
#[test]
fn same_actor_control_conflict_test() {
 let c=indexed_control(zero!<IndexedContext>(),machine(u32:7,true,true));
 let f=frame(u32:7,u32:0,u8:42);
 let s=SharedState<u32:1,u32:1>{indexed_context:[c],pending:[ScheduledRequest{slot:u32:0,frame:f,credit:false}],pending_valid:[true],..zero!<SharedState<u32:1,u32:1>>()};
 let i=indexed_select(s);assert_eq(i.valid, true);
 assert_eq(indexed_ordinary_state(s).pending_valid, [false]);
 let a=indexed_admit(s,i,true,u32:0); assert_eq(!a.consumed, true);assert_eq(indexed_commit(s, s,i,a),s);
 assert_eq(a.representative_write || a.deferred_write, false);
 let a=indexed_admit(s,i,false,u32:0);assert_eq(a.write_valid, true);
 let next=indexed_commit(s, s,i,a); assert_eq(!next.pending_valid[u32:0], true);
}

// A partial message lift retains the raw failure until ordinary source dispatch is eligible.
#[test]
fn partial_lift_failure_test() {
  let c = indexed_control(zero!<IndexedContext>(), machine(u32:7, true, false));
  let f = frame(u32:7, u32:3, u8:42);
  assert_eq(indexed_decode(f).contribution.valid, false);
  let a = indexed_push(c, f, indexed_decode(f), u32:0);
  assert_eq(a.consumed, true);
  assert_eq(a.write_valid, false);
  assert_eq(indexed_failure(a.context), hls_failure::NONE);
  assert_eq(a.context.deferred_frame_valid, true);
  assert_eq(indexed_push(a.context, f, indexed_decode(f), u32:0).consumed, false);
  let c = indexed_control(a.context, machine(u32:7, false, true));
  assert_eq(indexed_failure(c), dispatch(f, c.machine.phase, c.machine.data).4);
  assert_eq(hls_failure::kind(indexed_failure(c)), hls_failure::Kind::EXPLICIT_FAIL);
}

// Frame length validation has the same ordinary-input failure reason and cannot write RAM.
#[test]
fn malformed_reserved_frame_test() {
  let c = indexed_control(zero!<IndexedContext>(), machine(u32:7, true, false));
  let good = frame(u32:7, u32:0, u8:42);
  let malformed = axis::Frame { header: axis::Header { payload_words: u8:1, ..good.header }, ..good };
  let input = indexed_decode(malformed);
  assert_eq(input.reserved, true);
  assert_eq(input.frame_valid, false);
  let a = indexed_push(c, malformed, input, u32:0);
  assert_eq(a.consumed, true);
  assert_eq(a.write_valid, false);
  assert_eq(indexed_failure(a.context), hls_failure::INVALID_MESSAGE);
  assert_eq(a.representative_write || a.deferred_write, false);
  assert_frame_command_commit(c, a);
  let entering = IndexedContext { machine:ActorState { enter_pending:true, ..c.machine }, ..c };
  let deferred = indexed_push(entering, malformed, input, u32:0);
  assert_eq(deferred.context.deferred_failure, hls_failure::INVALID_MESSAGE);
  assert_eq(deferred.representative_write || deferred.deferred_write, false);
  assert_frame_command_commit(entering, deferred);
  let state = SharedState<u32:1,u32:1> {
    indexed_context:[c], pending:[ScheduledRequest { slot:u32:0, frame:malformed, credit:false }],
    pending_valid:[true], ..zero!<SharedState<u32:1,u32:1>>() };
  assert_eq(indexed_ordinary_state(state).pending_valid, [false]);
  let intent = indexed_select(state);
  assert_eq(intent.valid, true);
  assert_eq(indexed_admit(state, intent, false, u32:0), a);

}

// An entry-opened empty set completes before a pending continuation, as the public actor does.
#[test]
fn empty_completion_precedes_continuation_test() {
  let base = machine(u32:7, true, true);
  let opened = ActorState { next_event: u8:1,
    gather: GatherState { progress: GatherProgress { status: GatherStatus::COMPLETE,
      expected: u3:0, remaining: u8:0, ..base.gather.progress }, ..base.gather }, ..base };
  let context = indexed_control(zero!<IndexedContext>(), opened);
  let selected = indexed_ticket(context);
  assert_eq(selected.valid, true);
  let completed = actor_gather_complete(ActorState {
    gather: GatherState { progress: selected.progress, values: u24:0 }, ..opened });
  assert_eq(completed.machine.phase, Phase::WAITING);
  assert_eq(completed.machine.next_event, u8:1);
  assert_eq(completed.machine.failure, hls_failure::NONE);
}

// A stored current key must face the opening phase's source guard before it can complete.
#[test]
fn opening_revalidates_source_failure_test() {
  let context = indexed_control(zero!<IndexedContext>(), machine(u32:7, true, false));
  let first = frame(u32:7, u32:0, u8:42);
  let context = indexed_push(context, first, indexed_decode(first), u32:0).context;
  let second = frame(u32:7, u32:1, u8:43);
  let context = indexed_push(context, second, indexed_decode(second), u32:0).context;
  let base = machine(u32:7, true, true);
  let rejected = ActorState { data: Cell { current_mode: u8:2, ..base.data }, ..base };
  let context = indexed_control(context, rejected);
  assert_eq(indexed_failure(context), dispatch(first, rejected.phase, rejected.data).4);
  assert_eq(hls_failure::failed(indexed_failure(context)), true);
  assert_eq(indexed_ticket(context).valid, false);
}

// A captured collection whose source still postpones retains its provisional row until eligibility changes.
#[test]
fn opening_waits_for_source_eligibility_test() {
  let context = indexed_control(zero!<IndexedContext>(), machine(u32:7, true, false));
  let first = frame(u32:7, u32:0, u8:42);
  let context = indexed_push(context, first, indexed_decode(first), u32:0).context;
  let second = frame(u32:7, u32:1, u8:43);
  let context = indexed_push(context, second, indexed_decode(second), u32:0).context;
  let base = machine(u32:7, true, true);
  let postponed = ActorState { data: Cell { current_mode: u8:1, ..base.data }, ..base };
  let context = indexed_control(context, postponed);
  assert_eq(indexed_failure(context), hls_failure::NONE);
  assert_eq(indexed_ticket(context).valid, false);
  assert_eq(context.banks.banks[u32:0].status, indexed_collection_core::Status::PROVISIONAL);
  let observed = indexed_observation_progress(context);
  assert_eq(observed.status, GatherStatus::OPEN);
  assert_eq(observed.key, u32:7);
  assert_eq(observed.expected, u3:3);
  assert_eq(observed.seen, u3:0);
  assert_eq(observed.remaining, u8:2);
  let context = indexed_control(context, base);
  assert_eq(indexed_ticket(context).valid, true);
  assert_eq(indexed_ticket(context).progress.expected, u3:3);
}

// A current-key source postponement cannot mutate an open bank or monopolize other producers.
#[test]
fn open_source_postponement_yields_test() {
  let base = machine(u32:7, true, true);
  let paused = ActorState { data: Cell { current_mode: u8:1, ..base.data }, ..base };
  let contexts = [indexed_control(zero!<IndexedContext>(), paused),
                  indexed_control(zero!<IndexedContext>(), base)];
  let f = frame(u32:7, u32:0, u8:42);
  let state = SharedState<u32:2,u32:2> {
    indexed_context: contexts,
    pending: [ScheduledRequest { slot: u32:0, frame:f, credit:false },
              ScheduledRequest { slot: u32:1, frame:f, credit:false }],
    pending_valid: [true, true], ..zero!<SharedState<u32:2,u32:2>>() };
  let first = indexed_select(state);
  assert_eq(first.producer, u32:0);
  let held = indexed_admit(state, first, false, u32:0);
  assert_eq(held.consumed, false);
  assert_eq(held.write_valid, false);
  assert_eq(held.context, contexts[u32:0]);
  let state = indexed_commit(state, state, first, held);
  assert_eq(state.pending_valid, [true, true]);
  let second = indexed_select(state);
  assert_eq(second.producer, u32:1);
  assert_eq(indexed_admit(state, second, false, u32:0).write_valid, true);
}

// Early nonempty views retain continuation precedence and validate the resulting source state.
#[test]
fn nonempty_open_waits_for_continuation_test() {
  let context = indexed_control(zero!<IndexedContext>(), machine(u32:7, true, false));
  let first = frame(u32:7, u32:0, u8:42);
  let context = indexed_push(context, first, indexed_decode(first), u32:0).context;
  let second = frame(u32:7, u32:1, u8:43);
  let context = indexed_push(context, second, indexed_decode(second), u32:0).context;
  let base = machine(u32:7, true, true);
  let context = indexed_control(context, ActorState { next_event: u8:1, ..base });
  assert_eq(indexed_ticket(context).valid, false);
  assert_eq(context.banks.banks[u32:0].status, indexed_collection_core::Status::PROVISIONAL);
  let context = indexed_control(context, ActorState { data: Cell { current_mode: u8:2, ..base.data }, ..base });
  assert_eq(hls_failure::failed(indexed_failure(context)), true);
  assert_eq(indexed_ticket(context).valid, false);
}

// Full retained banks defer one selected producer without starving another actor.
#[test]
fn retained_capacity_poll_yields_test() {
  let base = machine(u32:7, true, true);
  let context = indexed_control(zero!<IndexedContext>(), base);
  let f0 = frame(u32:7, u32:0, u8:42);
  let f1 = frame(u32:7, u32:1, u8:43);
  let context = indexed_push(context, f0, indexed_decode(f0), u32:0).context;
  let context = indexed_push(context, f1, indexed_decode(f1), u32:0).context;
  let future = frame(u32:8, u32:0, u8:44);
  let context = indexed_push(context, future, indexed_decode(future), u32:0).context;
  let blocked = frame(u32:9, u32:0, u8:45);
  assert_eq(indexed_can_accept(context, indexed_decode(blocked)), false);
  let state = SharedState<u32:2,u32:2> {
    indexed_context: [context, indexed_control(zero!<IndexedContext>(), base)],
    pending: [ScheduledRequest { slot:u32:0, frame:blocked, credit:false },
              ScheduledRequest { slot:u32:1, frame:f0, credit:false }],
    pending_valid:[true,true], ..zero!<SharedState<u32:2,u32:2>>() };
  let first = indexed_select(state);
  assert_eq(first.valid, true);
  assert_eq(first.producer, u32:0);
  let held = indexed_admit(state, first, false, u32:0);
  assert_eq(held.consumed, false);
  assert_eq(held.write_valid, false);
  let state = indexed_commit(state, state, first, held);
  assert_eq(state.pending_valid, [true,true]);
  let second = indexed_select(state);
  assert_eq(second.producer, u32:1);
  assert_eq(indexed_admit(state, second, false, u32:0).write_valid, true);
}

// Borrowing preserves simultaneous successor writes and makes same-bank faults visible.
#[test]
fn simultaneous_borrow_admission_candidates_test() {
  let context = indexed_control(zero!<IndexedContext>(), machine(u32:7, true, true));
  let f0 = frame(u32:7, u32:0, u8:42);
  let f1 = frame(u32:7, u32:1, u8:43);
  let context = indexed_push(context, f0, indexed_decode(f0), u32:0).context;
  let context = indexed_push(context, f1, indexed_decode(f1), u32:0).context;
  let committed = SharedState<u32:1,u32:1> {
    indexed_context:[context], indexed_candidates:[true], ..zero!<SharedState<u32:1,u32:1>>() };
  let future = frame(u32:8, u32:0, u8:44);
  let admission = indexed_push(context, future, indexed_decode(future), u32:0);
  let intent = mailbox::Admission { valid:true, slot:u32:0, producer:u32:0, physical:u8:0 };
  let updated = indexed_commit(committed, committed, intent, admission);
  let borrowed = indexed_issue(committed, updated, intent, admission, true, u32:0);
  let next = borrowed.indexed_context[u32:0];
  assert_eq(next.banks.banks[u32:0].status, indexed_collection_core::Status::BORROWED);
  assert_eq(next.banks.banks[u32:1].seen, u3:1);
  assert_eq(borrowed.indexed_candidates[u32:0], false);
  assert_eq(borrowed.indexed_candidates[u32:0], indexed_ready(next));
  let duplicate = indexed_push(context, f0, indexed_decode(f0), u32:0);
  assert_eq(duplicate.write_valid, false);
  let updated = indexed_commit(committed, committed, intent, duplicate);
  let faulted = indexed_issue(committed, updated, intent, duplicate, true, u32:0);
  assert_eq(faulted.indexed_context[u32:0].consuming, false);
  assert_eq(faulted.indexed_candidates[u32:0], true);
  assert_eq(faulted.indexed_candidates[u32:0], indexed_ready(faulted.indexed_context[u32:0]));
}

// Forward source-only faults without confusing them with bank ownership faults;
// metadata retired for another actor survives the selected row's borrow.
#[test]
fn borrow_forwards_source_failure_and_preserves_other_retirement_test() {
  let context = indexed_control(zero!<IndexedContext>(), machine(u32:7, true, true));
  let f0 = frame(u32:7, u32:0, u8:42);
  let f1 = frame(u32:7, u32:1, u8:43);
  let context = indexed_push(context, f0, indexed_decode(f0), u32:0).context;
  let context = indexed_push(context, f1, indexed_decode(f1), u32:0).context;
  let committed = SharedState<u32:2,u32:1> {
    indexed_context:[context, context], indexed_candidates:[true, true],
    ..zero!<SharedState<u32:2,u32:1>>() };
  let retired = indexed_retire(committed, true, u32:1, machine(u32:8, true, false));
  let admission = IndexedAdmission { consumed:true,
    context: indexed_input_fault(context, hls_failure::INVALID_MESSAGE),
    ..zero!<IndexedAdmission>() };
  assert_eq(admission.context.banks.failure.code, indexed_collection_core::Fault::NONE);
  let intent = mailbox::Admission { valid:true, slot:u32:0, producer:u32:0, physical:u8:0 };
  let updated = indexed_commit(committed, retired, intent, admission);
  let borrowed = indexed_issue(committed, updated, intent, admission, true, u32:0);
  assert_eq(borrowed.indexed_context[u32:0].consuming, true);
  assert_eq(indexed_failure(borrowed.indexed_context[u32:0]), hls_failure::INVALID_MESSAGE);
  assert_eq(borrowed.indexed_candidates[u32:0], true);
  assert_eq(borrowed.indexed_context[u32:1], retired.indexed_context[u32:1]);
  let unrelated = mailbox::Admission { slot:u32:1, ..intent };
  let borrowed = indexed_issue(committed, retired, unrelated,
    zero!<IndexedAdmission>(), true, u32:0);
  assert_eq(borrowed.indexed_context[u32:0].consuming, true);
  assert_eq(indexed_failure(borrowed.indexed_context[u32:0]), hls_failure::NONE);
  assert_eq(borrowed.indexed_context[u32:1], retired.indexed_context[u32:1]);
}

// Specialization must retain the source failure and postponement decisions for
// valid members, rejected partial lifts and both source phases/modes.
#[test]
fn reserved_dispatch_matches_source_test() {
  for (i, _): (u32, ()) in u32:0..u32:256 {
    let m = machine(u32:7, (i & u32:1) != u32:0, (i & u32:2) != u32:0);
    let data = Cell { current_mode: ((i >> u32:2) & u32:3) as u8, ..m.data };
    let f = frame(u32:6 + ((i >> u32:4) & u32:3), (i >> u32:6) & u32:3, u8:42);
    let ordinary = dispatch(f, m.phase, data);
    assert_eq(indexed_dispatch(f, m.phase, data), (ordinary.2, ordinary.4));
    ()
  }(())
}

// Distinct retained bytes expose accidental rewrites of fields owned by another path.
fn marked_sealed_context(epoch: u32) -> IndexedContext {
  let seed = IndexedContext {
    banks: indexed_collection_core::init<INDEXED_CAPACITY>(epoch + u32:100),
    ..zero!<IndexedContext>() };
  let context = indexed_control(seed, machine(epoch, true, true));
  let first = frame(epoch, u32:0, u8:41);
  let second = frame(epoch, u32:1, u8:42);
  let context = indexed_push(context, first, indexed_decode(first), u32:0).context;
  let context = indexed_push(context, second, indexed_decode(second), u32:0).context;
  IndexedContext {
    machine: ActorState { entered_from: Phase::COLLECTING,
      gather: GatherState { values: u24:0x123456, ..context.machine.gather }, ..context.machine },
    representatives: [first, frame(epoch + u32:1, u32:2, u8:83)],
    lease: IndexedLease { bank:u1:1, key:epoch + u32:99, generation:u32:37, reset_epoch:u32:71 },
    deferred_failure: hls_failure::INVALID_MESSAGE,
    deferred_frame: frame(epoch + u32:1, u32:2, u8:94), deferred_frame_valid:true,
    ..context }
}

// The former whole-row borrow preserves every field outside its explicit ownership patch.
fn whole_row_borrow(context: IndexedContext, ticket: IndexedTicket) -> IndexedContext {
  assert_eq(ticket.valid, true);
  let acquired = indexed_collection_core::acquire(context.banks, ticket.lease);
  assert_eq(acquired.1.outcome, indexed_collection_core::Outcome::ACCEPTED);
  let bank = ticket.lease.bank as u32;
  assert_eq(acquired.0, IndexedBanks {
    banks: update(context.banks.banks, bank, indexed_collection_core::Bank<INDEXED_CAPACITY> {
      status:indexed_collection_core::Status::BORROWED, ..context.banks.banks[bank] }),
    ..context.banks });
  IndexedContext { banks:acquired.0, consuming:true, lease:ticket.lease, ..context }
}

// Three independent row owners match whole-row updates and preserve a fourth untouched actor.
#[test]
fn field_local_distinct_actor_updates_test() {
  let first = marked_sealed_context(u32:7);
  let retiring = whole_row_borrow(first, indexed_ticket(first));
  let accepting = marked_sealed_context(u32:17);
  let issuing = marked_sealed_context(u32:27);
  let untouched = marked_sealed_context(u32:37);
  let incoming = frame(u32:18, u32:0, u8:109);
  let state = SharedState<u32:4,u32:2> {
    indexed_context:[retiring, accepting, issuing, untouched],
    indexed_candidates:[false, true, true, true], indexed_cursor:u32:1,
    pending:[ScheduledRequest { slot:u32:1, frame:incoming, credit:false },
             ScheduledRequest { slot:u32:3, frame:frame(u32:38,u32:1,u8:117), credit:false }],
    pending_valid:[true, false], ..zero!<SharedState<u32:4,u32:2>>() };
  let next_machine = ActorState { enter_pending:true, ..machine(u32:8, true, false) };
  let intent = indexed_select(state);
  assert_eq(intent.producer, u32:0);
  let admission = indexed_admit(state, intent, true, u32:0);
  assert_eq(admission.consumed, true);
  assert_eq(admission.write_valid, true);
  let retired = indexed_control(retiring, next_machine);
  let borrowed = whole_row_borrow(issuing, indexed_ticket(issuing));
  let expected = SharedState<u32:4,u32:2> {
    indexed_context:[retired, admission.context, borrowed, untouched],
    indexed_candidates:[indexed_ready(retired), indexed_ready(admission.context), false, true],
    indexed_cursor:u32:1, pending_valid:[false, false], ..state };
  let actual = indexed_retire(state, true, u32:0, next_machine);
  let actual = indexed_commit(state, actual, intent, admission);
  let actual = indexed_issue(state, actual, intent, admission, true, u32:2);
  assert_eq(actual, expected);
}

// Borrow sees the accepted successor row while retaining unrelated raw frames and actor state.
#[test]
fn field_local_same_actor_updates_test() {
  let context = marked_sealed_context(u32:7);
  let incoming = frame(u32:8, u32:0, u8:109);
  let state = SharedState<u32:1,u32:1> {
    indexed_context:[context], indexed_candidates:[true],
    pending:[ScheduledRequest { slot:u32:0, frame:incoming, credit:false }],
    pending_valid:[true], ..zero!<SharedState<u32:1,u32:1>>() };
  let intent = indexed_select(state);
  let admission = indexed_admit(state, intent, false, u32:0);
  assert_eq(admission.consumed, true);
  assert_eq(admission.write_valid, true);
  let expected_context = whole_row_borrow(admission.context, indexed_ticket(context));
  let expected = SharedState<u32:1,u32:1> {
    indexed_context:[expected_context], indexed_candidates:[false], pending_valid:[false], ..state };
  let actual = indexed_commit(state, state, intent, admission);
  assert_eq(indexed_issue(state, actual, intent, admission, true, u32:0), expected);
}

// Future transition changes must extend field-local writes whenever their mutation footprint grows.
#[test]
fn indexed_transition_field_ownership_test() {
  let context = marked_sealed_context(u32:7);
  let future = frame(u32:8, u32:0, u8:63);
  let context = indexed_push(context, future, indexed_decode(future), u32:0).context;
  let context = whole_row_borrow(context, indexed_ticket(context));
  let context = IndexedContext { deferred_failure:hls_failure::NONE,
    deferred_frame_valid:false, ..context };
  for (i, _): (u32, ()) in u32:0..u32:4 {
    let next_machine = ActorState { enter_pending:i == u32:3,
      next_event:if i == u32:2 { u8:1 } else { u8:0 },
      ..machine(u32:7 + (i >> u32:1), (i & u32:1) != u32:0, (i & u32:2) == u32:0) };
    let retired = indexed_control(context, next_machine);
    assert_eq(retired, IndexedContext {
      initialized:retired.initialized, machine:retired.machine, banks:retired.banks,
      representative_valid:retired.representative_valid, actor_opened:retired.actor_opened,
      consuming:retired.consuming, failure:retired.failure, ..context });
    let incoming = [frame(u32:7,u32:0,u8:71), frame(u32:8,u32:1,u8:72),
                    frame(u32:8,u32:3,u8:73), frame(u32:10,u32:0,u8:74)][i];
    let admitted = indexed_push(context, incoming, indexed_decode(incoming), u32:0).context;
    assert_eq(admitted, IndexedContext {
      banks:admitted.banks, representatives:admitted.representatives,
      representative_valid:admitted.representative_valid,
      deferred_failure:admitted.deferred_failure, deferred_frame:admitted.deferred_frame,
      deferred_frame_valid:admitted.deferred_frame_valid, failure:admitted.failure, ..context });
    ()
  }(())
}

// Borrowing changes only status/failure even for stale, blocked or failed tickets.
#[test]
fn acquire_bank_field_ownership_test() {
  let context = marked_sealed_context(u32:7);
  for (i, _): (u32, ()) in u32:0..u32:80 {
    let bank = i % u32:2;
    let status = [indexed_collection_core::Status::FREE,
      indexed_collection_core::Status::PROVISIONAL, indexed_collection_core::Status::OPEN,
      indexed_collection_core::Status::SEALED, indexed_collection_core::Status::BORROWED][(i / u32:2) % u32:5];
    let fault = (i / u32:10) % u32:4;
    let previous = IndexedBanks {
      banks: update(context.banks.banks, bank, indexed_collection_core::Bank<INDEXED_CAPACITY> {
        status, ..context.banks.banks[bank] }),
      failure: indexed_collection_core::Error {
        code: if i >= u32:40 { indexed_collection_core::Fault::WRONG_STATUS }
          else { indexed_collection_core::Fault::NONE }, key:u32:91, member:u32:13 },
      ..context.banks };
    let original = indexed_lease(previous, bank as u1);
    let lease = IndexedLease {
      key: original.key + if fault == u32:1 { u32:1 } else { u32:0 },
      generation: original.generation + if fault == u32:2 { u32:1 } else { u32:0 },
      reset_epoch: original.reset_epoch + if fault == u32:3 { u32:1 } else { u32:0 }, ..original };
    let acquired = indexed_collection_core::acquire(previous, lease).0;
    let projected = IndexedBanks {
      banks: [indexed_collection_core::Bank<INDEXED_CAPACITY> {
        status:acquired.banks[u32:0].status, ..previous.banks[u32:0] },
        indexed_collection_core::Bank<INDEXED_CAPACITY> {
        status:acquired.banks[u32:1].status, ..previous.banks[u32:1] }],
      failure:acquired.failure, ..previous };
    assert_eq(projected, acquired);
    ()
  }(())
}

// Each bank captures its first representative; later members retain its original bytes.
#[test]
fn representative_frame_commands_test() {
  for (bank, _): (u32, ()) in u32:0..u32:2 {
    let base = indexed_control(zero!<IndexedContext>(), machine(u32:7, true, false));
    let future = frame(u32:8, u32:0, u8:91);
    let context = if bank == u32:1 {
      indexed_push(base, future, indexed_decode(future), u32:0).context
    } else { base };
    let context = indexed_control(context, machine(u32:7, true, true));
    let first = frame(u32:7, u32:0, u8:42);
    let accepted = indexed_push(context, first, indexed_decode(first), u32:0);
    assert_eq(accepted.representative_write, true);
    assert_eq(accepted.representative_bank as u32, bank);
    assert_eq(accepted.deferred_write, false);
    assert_frame_command_commit(context, accepted);
    let second = frame(u32:7, u32:1, u8:43);
    let next = indexed_push(accepted.context, second, indexed_decode(second), u32:0);
    assert_eq(next.representative_write || next.deferred_write, false);
    assert_eq(next.context.representatives[bank], first);
    assert_frame_command_commit(accepted.context, next);
    ()
  }(())
}

// A first failed offer retains bank one's representative even with a zeroed RAM write intent.
#[test]
fn failed_offer_frame_command_test() {
  let base = indexed_control(zero!<IndexedContext>(), machine(u32:7, true, false));
  let future = frame(u32:8, u32:0, u8:91);
  let context = indexed_push(base, future, indexed_decode(future), u32:0).context;
  let duplicate = indexed_push(context, future, indexed_decode(future), u32:0);
  assert_eq(duplicate.consumed, true);
  assert_eq(duplicate.write_valid, false);
  assert_eq(duplicate.context.banks.banks[u32:0].deferred.code,
    indexed_collection_core::Fault::DUPLICATE_MEMBER);
  assert_eq(duplicate.representative_write || duplicate.deferred_write, false);
  assert_frame_command_commit(context, duplicate);
  let context = indexed_control(context, machine(u32:7, true, true));
  let foreign = frame(u32:7, u32:2, u8:92);
  let failed = indexed_push(context, foreign, indexed_decode(foreign), u32:0);
  assert_eq(failed.consumed, true);
  assert_eq(failed.write_valid, false);
  assert_eq(failed.context.banks.failure.code, indexed_collection_core::Fault::FOREIGN_MEMBER);
  assert_eq(failed.representative_write, true);
  assert_eq(failed.representative_bank, u1:1);
  assert_eq(failed.deferred_write, false);
  assert_eq(failed.context.representatives[u32:1], foreign);
  assert_frame_command_commit(context, failed);
}

// Partial lifts capture only the first deferred frame; prior faults and source rejection preserve it.
#[test]
fn deferred_frame_commands_test() {
  let base = indexed_control(zero!<IndexedContext>(), machine(u32:7, true, false));
  let context = IndexedContext { deferred_frame:frame(u32:99,u32:2,u8:93), ..base };
  let partial = frame(u32:7, u32:3, u8:94);
  let first = indexed_push(context, partial, indexed_decode(partial), u32:0);
  assert_eq(first.consumed, true);
  assert_eq(first.deferred_write, true);
  assert_eq(first.representative_write, false);
  assert_frame_command_commit(context, first);
  let held = indexed_push(first.context, partial, indexed_decode(partial), u32:0);
  assert_eq(held.consumed, false);
  assert_eq(held.representative_write || held.deferred_write, false);
  assert_frame_command_commit(first.context, held);
  let faulted = IndexedContext { deferred_failure:hls_failure::INVALID_MESSAGE, ..context };
  let ignored = indexed_push(faulted, partial, indexed_decode(partial), u32:0);
  assert_eq(ignored.consumed, true);
  assert_eq(ignored.representative_write || ignored.deferred_write, false);
  assert_frame_command_commit(faulted, ignored);
  let rejected = frame(u32:9, u32:0, u8:95);
  let failed = indexed_push(context, rejected, indexed_decode(rejected), u32:0);
  assert_eq(hls_failure::failed(indexed_failure(failed.context)), true);
  assert_eq(failed.representative_write || failed.deferred_write, false);
  assert_frame_command_commit(context, failed);
}

// Preserve the frozen context-shaped call boundary. The original classifier read
// only these two fields, now enforced by the production function's signature.
fn reference_indexed_classify(context: IndexedContext, frame: axis::Frame, input: IndexedInput)
    -> IndexedEligibility {
  indexed_classify(context.initialized, context.machine, frame, input)
}

// Frozen d54895d retirement bodies, from template SHA-256
// 43a55552c9ee2706765e6b141d0a29f383b078a4c80fc3908cf38c2bed433f97.
// Only helper names/cross-calls and classifier call names change. The adapter above
// preserves the original classifier inputs; the ownership kernel remains shared.
// Open the exact key selected by source entry, rechecking all stored member claims.
// An unmatchable third opening is an asserted-overlap fault, never bank replacement.
fn reference_indexed_open(context: IndexedContext, opening: GatherProgress) -> IndexedContext {
  let found = indexed_find(context.banks, opening.key);
  let reservation = if found.0 {
    (context.banks, indexed_collection_core::Result {
      outcome: indexed_collection_core::Outcome::ACCEPTED,
      lease: indexed_lease(context.banks, found.1), ..zero!<indexed_collection_core::Result>() })
  } else { indexed_collection_core::reserve(context.banks, opening.key, !GatherMembers:0) };
  if reservation.1.outcome != indexed_collection_core::Outcome::ACCEPTED || opening.site != INDEXED_SITE {
    IndexedContext { failure: hls_failure::first(context.failure, hls_failure::REDUCTION_PROTOCOL), ..context }
  } else {
    let reserved = IndexedContext { banks: reservation.0, ..context };
    let bank = reservation.1.lease.bank as u32;
    let frame = context.representatives[bank];
    let eligibility = reference_indexed_classify(context, frame, indexed_decode(frame));
    let empty = opening.status == GatherStatus::COMPLETE;
    // A physical reservation can outlive logical entry while source dispatch
    // still postpones. The actor progress retains the originally captured mask.
    if !empty && context.representative_valid[bank] && hls_failure::failed(eligibility.failure) {
      IndexedContext { failure: hls_failure::first(context.failure, eligibility.failure), ..reserved }
    } else if !empty && (!indexed_stable(context.machine) ||
        (context.representative_valid[bank] && !eligibility.current)) {
      reserved
    } else {
      let opened = indexed_collection_core::open(reservation.0, reservation.1.lease, opening.expected);
      IndexedContext { banks: opened.0, ..context }
    }
  }
}

// Recheck provisional keys only at a stable callback boundary. One representative
// relies on the declared key-uniform eligibility assumption; opening separately
// validates every stored member against the captured runtime membership mask.
fn reference_indexed_revalidate(context: IndexedContext) -> IndexedContext {
  if !indexed_stable(context.machine) { context } else {
    let deferred = if context.deferred_frame_valid {
      reference_indexed_classify(context, context.deferred_frame, indexed_decode(context.deferred_frame)).failure
    } else { context.deferred_failure };
    let context = IndexedContext { failure: hls_failure::first(context.failure, deferred), ..context };
    unroll_for! (bank, current): (u32, IndexedContext) in u32:0..u32:2 {
      let provisional = current.banks.banks[bank].status == indexed_collection_core::Status::PROVISIONAL &&
        current.representative_valid[bank];
      let frame = current.representatives[bank];
      let eligibility = reference_indexed_classify(current, frame, indexed_decode(frame));
      if provisional && hls_failure::failed(eligibility.failure) {
        IndexedContext { failure: hls_failure::first(current.failure, eligibility.failure), ..current }
      } else { current }
    }(context)
  }
}

// Retirement is the last-reader boundary for the transient gather-completion API.
// Reset of the enclosing scheduler flushes all tickets/RAM handoffs before reuse;
// ordinary release destroys its ticket before modulo generation can repeat.
fn reference_indexed_control(context: IndexedContext, machine: ActorState) -> IndexedContext {
  let released = if context.consuming {
    indexed_collection_core::release(context.banks, context.lease).0
  } else { context.banks };
  let next = IndexedContext { initialized: true, machine, banks: released, consuming: false,
    representative_valid: if context.consuming {
      update(context.representative_valid, context.lease.bank as u32, false)
    } else { context.representative_valid }, ..context };
  let active = machine.gather.progress.status != GatherStatus::IDLE;
  let found = indexed_find(next.banks, machine.gather.progress.key);
  let deferred_open = found.0 &&
    next.banks.banks[found.1 as u32].status == indexed_collection_core::Status::PROVISIONAL;
  let opening = active && (!context.actor_opened || context.consuming || deferred_open);
  let opened = if opening && !hls_failure::failed(machine.failure) {
    reference_indexed_open(next, machine.gather.progress)
  } else { next };
  reference_indexed_revalidate(IndexedContext { actor_opened: active, ..opened })
}

// Distinct metadata and frame bytes reveal unintended mutation in full-row comparisons.
fn retirement_context(bank: u32, status: indexed_collection_core::Status) -> IndexedContext {
  let selected = indexed_collection_core::Bank<INDEXED_CAPACITY> {
    status, key:u32:7, generation:!u32:0, candidates:u3:7, members:u3:3, seen:u3:1,
    deferred:indexed_collection_core::Error { key:u32:91, member:u32:2,
      ..zero!<indexed_collection_core::Error>() } };
  let other = indexed_collection_core::Bank<INDEXED_CAPACITY> {
    status:indexed_collection_core::Status::PROVISIONAL, key:u32:8,
    generation:u32:31, candidates:u3:7, seen:u3:1,
    ..zero!<indexed_collection_core::Bank<INDEXED_CAPACITY>>() };
  let banks = IndexedBanks { banks:update([other, other], bank, selected), reset_epoch:u32:73,
    failure:indexed_collection_core::Error { key:u32:93, member:u32:2,
      ..zero!<indexed_collection_core::Error>() } };
  IndexedContext { initialized:true, machine:machine(u32:6, false, false), banks,
    representatives:update([frame(u32:8,u32:1,u8:82), frame(u32:8,u32:1,u8:83)],
      bank, frame(u32:7,u32:0,u8:71)), representative_valid:[true, true],
    lease:indexed_lease(banks, bank as u1), deferred_frame:frame(u32:7,u32:3,u8:94),
    ..zero!<IndexedContext>() }
}

// Compare all fields, including diagnostic bytes and fields unaffected by retirement.
fn assert_retirement_reference(context: IndexedContext, returned: ActorState) {
  assert_eq(indexed_control(context, returned), reference_indexed_control(context, returned));
}

// 72 cases: both bank positions, three source modes, four callback boundaries,
// and idle/nonempty/empty progress. A retained partial lift competes with source faults.
#[test]
fn retirement_source_boundary_reference_test() {
  for (i, _): (u32, ()) in u32:0..u32:72 {
    let context = retirement_context(i % u32:2, indexed_collection_core::Status::PROVISIONAL);
    let context = IndexedContext { deferred_frame_valid:true, ..context };
    let mode = (i / u32:2) % u32:3;
    let boundary = (i / u32:6) % u32:4;
    let opening = i / u32:24;
    let base = machine(u32:7, true, opening != u32:0);
    let returned = ActorState { data:Cell { current_mode:mode as u8, ..base.data },
      enter_pending:boundary == u32:1, next_event:if boundary == u32:2 { u8:1 } else { u8:0 },
      failure:if boundary == u32:3 { hls_failure::INVALID_MESSAGE } else { hls_failure::NONE },
      gather:GatherState { progress:GatherProgress {
        status:if opening == u32:2 { GatherStatus::COMPLETE } else { base.gather.progress.status },
        expected:if opening == u32:2 { u3:0 } else { u3:3 },
        remaining:if opening == u32:2 { u8:0 } else { u8:2 }, ..base.gather.progress },
        ..base.gather }, ..base };
    assert_retirement_reference(context, returned);
    ()
  }(())
}

// 32 supplied contexts cross initialization, both validity bits and stable/entry/
// continuation/empty boundaries. Direct helpers must not force initialization.
#[test]
fn retirement_direct_helpers_reference_test() {
  for (i, _): (u32, ()) in u32:0..u32:32 {
    let context = retirement_context(u32:0, indexed_collection_core::Status::PROVISIONAL);
    let boundary = i / u32:8;
    let base = machine(u32:7, false, true);
    let good = context.representatives[u32:0];
    let malformed = axis::Frame { header:axis::Header { payload_words:u8:1, ..good.header }, ..good };
    let context = IndexedContext { initialized:(i & u32:1) != u32:0,
      representative_valid:[(i & u32:2) != u32:0, (i & u32:4) != u32:0],
      representatives:[malformed, frame(u32:8,u32:3,u8:85)],
      deferred_frame_valid:(i & u32:2) != u32:0, deferred_failure:hls_failure::REDUCTION_PROTOCOL,
      machine:ActorState { enter_pending:boundary == u32:1,
        next_event:if boundary == u32:2 { u8:1 } else { u8:0 }, ..base }, ..context };
    let opening = GatherProgress { status:if boundary == u32:3 { GatherStatus::COMPLETE }
        else { GatherStatus::OPEN }, expected:if boundary == u32:3 { u3:0 } else { u3:3 },
      ..base.gather.progress };
    let checks = indexed_saved_checks(context);
    assert_eq(indexed_open(context, opening, checks), reference_indexed_open(context, opening));
    assert_eq(indexed_revalidate(context, checks), reference_indexed_revalidate(context));
    ()
  }(())
}

// 40 cases cross bank positions/statuses with valid/key/generation/reset leases.
// Successful reuse wraps generation; failed release still clears the selected validity bit.
#[test]
fn retirement_release_reference_test() {
  for (i, _): (u32, ()) in u32:0..u32:40 {
    let status = [indexed_collection_core::Status::FREE, indexed_collection_core::Status::PROVISIONAL,
      indexed_collection_core::Status::OPEN, indexed_collection_core::Status::SEALED,
      indexed_collection_core::Status::BORROWED][(i / u32:2) % u32:5];
    let context = retirement_context(i % u32:2, status);
    let fault = i / u32:10;
    let context = IndexedContext { consuming:true, actor_opened:true,
      lease:IndexedLease {
        key:context.lease.key + if fault == u32:1 { u32:1 } else { u32:0 },
        generation:context.lease.generation + if fault == u32:2 { u32:1 } else { u32:0 },
        reset_epoch:context.lease.reset_epoch + if fault == u32:3 { u32:1 } else { u32:0 },
        ..context.lease }, ..context };
    assert_retirement_reference(context, machine(u32:7, true, true));
    ()
  }(())
}

// 16 cases retain existing/source/kernel/deferred failure precedence at either bank.
// Competing faults are intentionally constructed; this grid is not a legal-traffic proof.
#[test]
fn retirement_failure_priority_reference_test() {
  for (i, _): (u32, ()) in u32:0..u32:16 {
    let bank = i % u32:2;
    let kind = i / u32:2;
    let context = retirement_context(bank, indexed_collection_core::Status::PROVISIONAL);
    let selected = context.banks.banks[bank];
    let good = context.representatives[bank];
    let malformed = axis::Frame { header:axis::Header { payload_words:u8:1, ..good.header }, ..good };
    let selected = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      seen:if kind == u32:3 { u3:4 } else { selected.seen },
      deferred:indexed_collection_core::Error {
        code:if kind == u32:2 { indexed_collection_core::Fault::DUPLICATE_MEMBER }
          else { indexed_collection_core::Fault::NONE }, ..selected.deferred }, ..selected };
    let context = IndexedContext { banks:IndexedBanks {
        banks:update(context.banks.banks, bank, selected),
        failure:indexed_collection_core::Error {
          code:if kind == u32:1 { indexed_collection_core::Fault::WRONG_STATUS }
            else { indexed_collection_core::Fault::NONE }, ..context.banks.failure }, ..context.banks },
      representatives:update([frame(u32:9,u32:0,u8:97), frame(u32:9,u32:0,u8:98)], bank,
        if kind == u32:1 { malformed } else { good }),
      deferred_frame_valid:kind == u32:4 || kind == u32:5,
      deferred_frame:if kind == u32:4 { malformed } else { context.deferred_frame },
      deferred_failure:if kind >= u32:4 && kind <= u32:6 { hls_failure::INVALID_MESSAGE }
        else { hls_failure::NONE },
      failure:if kind == u32:0 { hls_failure::REDUCTION_PROTOCOL } else { hls_failure::NONE }, ..context };
    let returned = machine(u32:7, kind != u32:7, true);
    let returned = ActorState { data:Cell { current_mode:if kind == u32:0 { u8:2 } else { u8:0 },
      ..returned.data }, ..returned };
    assert_retirement_reference(context, returned);
    ()
  }(())
}

// Empty opening bypasses an invalid saved representative and seals before revalidation;
// neither entry nor a pending continuation changes that source-independent ownership step.
#[test]
fn retirement_empty_post_open_gate_reference_test() {
  for (i, _): (u32, ()) in u32:0..u32:6 {
    let bank = i % u32:2;
    let boundary = i / u32:2;
    let context = retirement_context(bank, indexed_collection_core::Status::PROVISIONAL);
    let selected = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      seen:u3:0, ..context.banks.banks[bank] };
    let good = context.representatives[bank];
    let malformed = axis::Frame { header:axis::Header { payload_words:u8:1, ..good.header }, ..good };
    let context = IndexedContext { banks:IndexedBanks {
      banks:update(zero!<indexed_collection_core::Bank<INDEXED_CAPACITY>[2]>(), bank, selected),
      ..context.banks }, representatives:update(context.representatives, bank, malformed), ..context };
    let base = machine(u32:7, false, true);
    let returned = ActorState { enter_pending:boundary == u32:1,
      next_event:if boundary == u32:2 { u8:1 } else { u8:0 },
      gather:GatherState { progress:GatherProgress { status:GatherStatus::COMPLETE,
        expected:u3:0, remaining:u8:0, ..base.gather.progress }, ..base.gather }, ..base };
    assert_retirement_reference(context, returned);
    let actual = indexed_control(context, returned);
    assert_eq(actual.failure, hls_failure::NONE);
    assert_eq(actual.banks.banks[bank].status, indexed_collection_core::Status::SEALED);
    ()
  }(())
}

// Both released slots, each with a malformed or source-rejected old frame, must
// reuse the row under its cleared post-release validity bit.
#[test]
fn retirement_reused_slot_ignores_stale_frame_test() {
  for (i, _): (u32, ()) in u32:0..u32:4 {
    let bank = i % u32:2;
    let other_bank = u32:1 - bank;
    let context = retirement_context(bank, indexed_collection_core::Status::BORROWED);
    let held = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      status:indexed_collection_core::Status::SEALED, members:u3:3, seen:u3:3,
      ..context.banks.banks[other_bank] };
    let good = context.representatives[bank];
    let stale = if i / u32:2 == u32:0 {
      axis::Frame { header:axis::Header { payload_words:u8:1, ..good.header }, ..good }
    } else { good };
    let context = IndexedContext { banks:IndexedBanks {
        banks:update(context.banks.banks, other_bank, held), ..context.banks },
      representatives:update(context.representatives, bank, stale),
      consuming:true, actor_opened:true, ..context };
    let returned = machine(u32:9, false, true);
    // Either frame would fault if the pre-release validity bit were consulted.
    let eligibility = indexed_classify(true, returned, stale, indexed_decode(stale));
    assert_eq(hls_failure::failed(eligibility.failure), true);
    let actual = indexed_control(context, returned);
    assert_eq(actual, reference_indexed_control(context, returned));
    assert_eq(actual.representative_valid, update(context.representative_valid, bank, false));
    assert_eq(actual.banks.banks[bank].key, u32:9);
    assert_eq(actual.banks.banks[bank].status, indexed_collection_core::Status::OPEN);
    assert_eq(indexed_failure(actual), hls_failure::NONE);
    assert_eq(actual.banks.banks[other_bank], held);
    ()
  }(())
}

// Frozen pre-change indexed_issue from committed-borrow-r1/indexed_collection.before.x.in
// (9a52f224); only the function name differs. This reference retains post-admission acquisition.
fn reference_committed_borrow_issue<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    committed: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, updated: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
    intent: mailbox::Admission, admission: IndexedAdmission,
    issuing: bool, slot: u32) -> SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
  let selected = indexed_ticket(committed.indexed_context[slot]);
  if !issuing || !selected.valid { updated } else {
    // Issue excludes the retiring actor. Only a consumed same-actor admission
    // can change this row before borrowing; forward that row explicitly.
    let context = if intent.valid && admission.consumed && intent.slot == slot {
      admission.context
    } else { committed.indexed_context[slot] };
    let acquired = indexed_collection_core::acquire(context.banks, selected.lease);
    // This actor cannot retire while its committed completion is being issued.
    // Admission can change another bank or latch a fault, but cannot unseal this
    // bank. An unexpected WAIT therefore violates the scheduler ownership contract.
    let failure = if acquired.1.outcome == indexed_collection_core::Outcome::WAIT {
      hls_failure::first(context.failure, hls_failure::REDUCTION_PROTOCOL)
    } else { context.failure };
    let next = IndexedContext { banks: acquired.0, failure,
      consuming: acquired.1.outcome == indexed_collection_core::Outcome::ACCEPTED,
      lease: selected.lease, ..context };
    // Success consumes the sole completion; only a sticky fault can still wake
    // this actor. Do not search the newly updated bank array again for readiness.
    let ready = next.initialized && !hls_failure::failed(next.machine.failure) &&
      hls_failure::failed(indexed_failure(next));
    // Borrowing cannot change source eligibility or representative/deferred
    // frames. Preserve their independently committed per-row register values.
    let contexts = unroll_for! (actor, rows): (u32, IndexedContext[ACTOR_COUNT]) in u32:0..ACTOR_COUNT {
      let previous = updated.indexed_context[actor];
      // Acquire changes bank status or sticky failure, never the row identity,
      // membership or previously accepted member claims.
      let bank_rows = unroll_for! (bank, rows): (u32, indexed_collection_core::Bank<INDEXED_CAPACITY>[2]) in u32:0..u32:2 {
        update(rows, bank, indexed_collection_core::Bank<INDEXED_CAPACITY> {
          status: next.banks.banks[bank].status, ..previous.banks.banks[bank] })
      }(previous.banks.banks);
      let banks = IndexedBanks { banks: bank_rows, failure: next.banks.failure, ..previous.banks };
      let changed = IndexedContext { banks, consuming: next.consuming,
        lease: next.lease, failure: next.failure, ..previous };
      update(rows, actor, if actor == slot { changed } else { previous })
    }(updated.indexed_context);
    SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      indexed_context: contexts,
      indexed_candidates: update(updated.indexed_candidates, slot, ready), ..updated }
  }
}

// Frozen baseline ticket and issue logic provide complete-output simulation witnesses.
// Only names and the issue reference call change; neither uses the new descriptor helper.
fn reference_fixed_descriptor_ticket(context: IndexedContext) -> IndexedTicket {
  let found = indexed_find(context.banks, context.machine.gather.progress.key);
  let bank = context.banks.banks[found.1 as u32];
  let failure = indexed_failure(context);
  let valid = context.initialized && context.actor_opened && !context.consuming &&
    !context.machine.enter_pending &&
    (context.machine.gather.progress.status == GatherStatus::COMPLETE || indexed_stable(context.machine)) &&
    !hls_failure::failed(context.machine.failure) &&
    !hls_failure::failed(failure) && found.0 && bank.status == indexed_collection_core::Status::SEALED;
  IndexedTicket { valid, failure, lease: indexed_lease(context.banks, found.1),
    progress: GatherProgress { status: GatherStatus::COMPLETE, site: INDEXED_SITE,
      key: bank.key, remaining: u8:0, expected: bank.members, seen: bank.seen, failure } }
}

// Preserve the full pre-draft issue poststate, including latest admission faults and other rows.
fn reference_fixed_descriptor_issue<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    committed: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, updated: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
    intent: mailbox::Admission, admission: IndexedAdmission,
    issuing: bool, slot: u32) -> SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
  let selected = reference_fixed_descriptor_ticket(committed.indexed_context[slot]);
  if !issuing || !selected.valid { updated } else {
    // Issue excludes the retiring actor. Only a consumed same-actor admission
    // can change this row before borrowing; forward that row explicitly.
    let context = if intent.valid && admission.consumed && intent.slot == slot {
      admission.context
    } else { committed.indexed_context[slot] };
    // Production admission cannot mutate the committed SEALED bank. Check that
    // bank before admission's other-bank updates; forward the latest kernel failure.
    let checked_banks = IndexedBanks { failure: context.banks.failure,
      ..committed.indexed_context[slot].banks };
    let acquired = indexed_collection_core::acquire(checked_banks, selected.lease);
    // This actor cannot retire while its committed completion is being issued.
    // Admission can change another bank or latch a fault, but cannot unseal this
    // bank. An unexpected WAIT therefore violates the scheduler ownership contract.
    let failure = if acquired.1.outcome == indexed_collection_core::Outcome::WAIT {
      hls_failure::first(context.failure, hls_failure::REDUCTION_PROTOCOL)
    } else { context.failure };
    let next = IndexedContext { banks: acquired.0, failure,
      consuming: acquired.1.outcome == indexed_collection_core::Outcome::ACCEPTED,
      lease: selected.lease, ..context };
    // Success consumes the sole completion; only a sticky fault can still wake
    // this actor. Do not search the newly updated bank array again for readiness.
    let ready = next.initialized && !hls_failure::failed(next.machine.failure) &&
      hls_failure::failed(indexed_failure(next));
    // Borrowing cannot change source eligibility or representative/deferred
    // frames. Preserve their independently committed per-row register values.
    let contexts = unroll_for! (actor, rows): (u32, IndexedContext[ACTOR_COUNT]) in u32:0..ACTOR_COUNT {
      let previous = updated.indexed_context[actor];
      // Acquire changes bank status or sticky failure, never the row identity,
      // membership or previously accepted member claims. Other-bank status must
      // retain any simultaneous reservation or last-member completion.
      let bank_rows = unroll_for! (bank, rows): (u32, indexed_collection_core::Bank<INDEXED_CAPACITY>[2]) in u32:0..u32:2 {
        update(rows, bank, indexed_collection_core::Bank<INDEXED_CAPACITY> {
          status: if bank == selected.lease.bank as u32 { next.banks.banks[bank].status }
            else { previous.banks.banks[bank].status }, ..previous.banks.banks[bank] })
      }(previous.banks.banks);
      let banks = IndexedBanks { banks: bank_rows, failure: next.banks.failure, ..previous.banks };
      let changed = IndexedContext { banks, consuming: next.consuming,
        lease: next.lease, failure: next.failure, ..previous };
      update(rows, actor, if actor == slot { changed } else { previous })
    }(updated.indexed_context);
    SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      indexed_context: contexts,
      indexed_candidates: update(updated.indexed_candidates, slot, ready), ..updated }
  }
}

// Seed either selected bank with a sealed view, retaining distinct diagnostic/frame bytes.
fn committed_borrow_context(bank: u32) -> IndexedContext {
  let base = marked_sealed_context(u32:7);
  let banks = if bank == u32:0 { base.banks.banks }
    else { [base.banks.banks[u32:1], base.banks.banks[u32:0]] };
  let representatives = if bank == u32:0 { base.representatives }
    else { [base.representatives[u32:1], base.representatives[u32:0]] };
  let representative_valid = if bank == u32:0 { base.representative_valid }
    else { [base.representative_valid[u32:1], base.representative_valid[u32:0]] };
  IndexedContext { banks:IndexedBanks { banks,
      failure:indexed_collection_core::Error { code:indexed_collection_core::Fault::NONE,
        key:u32:191, member:u32:192 }, ..base.banks },
    representatives, representative_valid, deferred_failure:hls_failure::NONE,
    deferred_frame_valid:false, ..base }
}

// Three distinguishable actors permit admission, unrelated retirement and issue together.
fn committed_borrow_state(context: IndexedContext, incoming: axis::Frame, admission_slot: u32)
    -> SharedState<u32:3,u32:2> {
  let other = marked_sealed_context(u32:17);
  let retiring = marked_sealed_context(u32:27);
  SharedState<u32:3,u32:2> {
    indexed_context:[context, other, retiring],
    indexed_candidates:[indexed_ready(context), indexed_ready(other), indexed_ready(retiring)],
    pending:[ScheduledRequest { slot:admission_slot, frame:incoming, credit:false },
      ScheduledRequest { slot:u32:2, frame:frame(u32:29,u32:2,u8:113), credit:false }],
    pending_valid:[true,false], indexed_cursor:u32:1, ..zero!<SharedState<u32:3,u32:2>>() }
}

// Compare complete post-states; inputs must come from production admission/commit,
// with retirement restricted to another actor as required by the scheduler.
fn assert_committed_borrow_reference(committed: SharedState<u32:3,u32:2>,
    updated: SharedState<u32:3,u32:2>, intent: mailbox::Admission,
    admission: IndexedAdmission, issuing: bool) -> SharedState<u32:3,u32:2> {
  let actual = indexed_issue(committed, updated, intent, admission, issuing, u32:0);
  assert_eq(actual,
    reference_fixed_descriptor_issue(committed, updated, intent, admission, issuing, u32:0));
  assert_eq(actual,
    reference_committed_borrow_issue(committed, updated, intent, admission, issuing, u32:0));
  actual
}

// Both selected positions retain successor reservation (including generation wrap),
// last-member sealing and deferred duplicate faults. The OPEN-other-bank case uses
// a controlled source epoch distinct from the captured completion key.
#[test]
fn committed_borrow_successor_reference_test() {
  for (i, _): (u32, ()) in u32:0..u32:8 {
    let bank = i % u32:2;
    let other = u32:1 - bank;
    let kind = i / u32:2;
    let context = committed_borrow_context(bank);
    let successor = if kind < u32:2 {
      indexed_collection_core::Bank<INDEXED_CAPACITY> {
        generation:if kind == u32:1 { !u32:0 } else { u32:23 },
        ..context.banks.banks[other] }
    } else {
      indexed_collection_core::Bank<INDEXED_CAPACITY> {
        status:if kind == u32:2 { indexed_collection_core::Status::OPEN }
          else { indexed_collection_core::Status::PROVISIONAL },
        key:u32:8, generation:u32:73, candidates:u3:7,
        members:if kind == u32:2 { u3:3 } else { u3:0 }, seen:u3:1,
        ..zero!<indexed_collection_core::Bank<INDEXED_CAPACITY>>() }
    };
    let context = IndexedContext { banks:IndexedBanks {
        banks:update(context.banks.banks, other, successor), ..context.banks },
      representatives:if kind >= u32:2 {
        update(context.representatives, other, frame(u32:8,u32:0,u8:83))
      } else { context.representatives },
      representative_valid:if kind >= u32:2 { update(context.representative_valid, other, true) }
        else { context.representative_valid },
      machine:ActorState { data:Cell { epoch:if kind == u32:2 { u32:8 } else { u32:7 },
        ..context.machine.data }, ..context.machine }, ..context };
    let incoming = frame(u32:8, if kind == u32:2 { u32:1 } else { u32:0 }, u8:91);
    let state = committed_borrow_state(context, incoming, u32:0);
    assert_eq(indexed_ticket(context).valid, true);
    let intent = indexed_select(state);
    let admission = indexed_admit(state, intent, false, u32:0);
    assert_eq(admission.consumed, true);
    assert_eq(admission.write_valid, kind != u32:3);
    let updated = indexed_commit(state, state, intent, admission);
    let actual = assert_committed_borrow_reference(state, updated, intent, admission, true);
    let next = actual.indexed_context[u32:0];
    assert_eq(next.banks.banks[bank].status, indexed_collection_core::Status::BORROWED);
    assert_eq(next.consuming, true);
    assert_eq(next.banks.banks[other], admission.context.banks.banks[other]);
    assert_eq(next.banks.banks[other].status,
      if kind == u32:2 { indexed_collection_core::Status::SEALED }
      else { indexed_collection_core::Status::PROVISIONAL });
    assert_eq(next.banks.banks[other].generation,
      if kind == u32:0 { u32:24 } else if kind == u32:1 { u32:0 } else { u32:73 });
    assert_eq(next.banks.banks[other].deferred.code,
      if kind == u32:3 { indexed_collection_core::Fault::DUPLICATE_MEMBER }
      else { indexed_collection_core::Fault::NONE });
    assert_eq(next.banks.failure, context.banks.failure);
    assert_eq(actual.indexed_candidates[u32:0], false);
    ()
  }(())
}

// Terminal kernel errors suppress borrowing; source-only errors still acquire.
// The fixture lift rejects member >=3, so its range case is a real source failure,
// not a fabricated decoded input claiming kernel MEMBER_RANGE coverage.
#[test]
fn committed_borrow_fault_reference_test() {
  for (i, _): (u32, ()) in u32:0..u32:12 {
    let bank = i % u32:2;
    let other = u32:1 - bank;
    let kind = i / u32:2;
    let context = committed_borrow_context(bank);
    let successor = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      status:indexed_collection_core::Status::OPEN, key:u32:8, generation:u32:73,
      candidates:u3:7, members:u3:3, seen:u3:1,
      ..zero!<indexed_collection_core::Bank<INDEXED_CAPACITY>>() };
    let context = IndexedContext { banks:IndexedBanks {
        banks:if kind == u32:5 { update(context.banks.banks, other, successor) }
          else { context.banks.banks }, ..context.banks },
      machine:ActorState { data:Cell { epoch:if kind == u32:5 { u32:8 } else { u32:7 },
        current_mode:if kind == u32:4 { u8:2 } else { u8:0 }, ..context.machine.data },
        ..context.machine }, ..context };
    let key = if kind == u32:5 { u32:8 } else { u32:7 };
    let member = if kind == u32:1 { u32:2 } else if kind == u32:2 { u32:3 } else { u32:0 };
    let good = frame(key, member, u8:95);
    let incoming = if kind == u32:3 {
      axis::Frame { header:axis::Header { payload_words:u8:1, ..good.header }, ..good }
    } else { good };
    let state = committed_borrow_state(context, incoming, u32:0);
    assert_eq(indexed_ticket(context).valid, true);
    let intent = indexed_select(state);
    let admission = indexed_admit(state, intent, false, u32:0);
    assert_eq(admission.consumed, true);
    assert_eq(admission.write_valid, false);
    let kernel_fault = kind < u32:2 || kind == u32:5;
    let expected_kernel = if kernel_fault {
      indexed_collection_core::Error {
        code:if kind == u32:1 { indexed_collection_core::Fault::FOREIGN_MEMBER }
          else { indexed_collection_core::Fault::DUPLICATE_MEMBER }, key, member }
    } else { context.banks.failure };
    let expected_source = if kernel_fault { hls_failure::NONE }
      else if kind == u32:3 { hls_failure::INVALID_MESSAGE }
      else { dispatch(incoming, context.machine.phase, context.machine.data).4 };
    assert_eq(admission.context.banks.failure, expected_kernel);
    assert_eq(admission.context.failure, expected_source);
    assert_eq(hls_failure::failed(expected_source), !kernel_fault);
    let updated = indexed_commit(state, state, intent, admission);
    let actual = assert_committed_borrow_reference(state, updated, intent, admission, true);
    let next = actual.indexed_context[u32:0];
    assert_eq(next.banks.failure, expected_kernel);
    assert_eq(next.failure, expected_source);
    assert_eq(next.consuming, !kernel_fault);
    assert_eq(next.banks.banks[bank].status,
      if kernel_fault { indexed_collection_core::Status::SEALED }
      else { indexed_collection_core::Status::BORROWED });
    assert_eq(next.lease, indexed_ticket(context).lease);
    assert_eq(actual.indexed_candidates[u32:0], true);
    ()
  }(())
}

// Empty completion can issue ahead of a continuation. Partial lifts and malformed
// frames remain deferred, including existing retained-frame/error precedence.
#[test]
fn committed_borrow_deferred_source_reference_test() {
  for (i, _): (u32, ()) in u32:0..u32:8 {
    let bank = i % u32:2;
    let kind = i / u32:2;
    let context = committed_borrow_context(bank);
    let selected = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      members:u3:0, seen:u3:0, ..context.banks.banks[bank] };
    let context = IndexedContext { banks:IndexedBanks {
        banks:update(context.banks.banks, bank, selected), ..context.banks },
      representative_valid:update(context.representative_valid, bank, false),
      deferred_frame_valid:kind == u32:2,
      deferred_failure:if kind == u32:3 { hls_failure::REDUCTION_PROTOCOL } else { hls_failure::NONE },
      machine:ActorState { next_event:u8:1,
        gather:GatherState { progress:GatherProgress { status:GatherStatus::COMPLETE,
          expected:u3:0, seen:u3:0, remaining:u8:0, ..context.machine.gather.progress },
          ..context.machine.gather }, ..context.machine }, ..context };
    let good = frame(u32:7, if kind % u32:2 == u32:0 { u32:3 } else { u32:0 }, u8:96);
    let incoming = if kind % u32:2 == u32:1 {
      axis::Frame { header:axis::Header { payload_words:u8:1, ..good.header }, ..good }
    } else { good };
    let state = committed_borrow_state(context, incoming, u32:0);
    assert_eq(indexed_ticket(context).valid, true);
    assert_eq(indexed_stable(context.machine), false);
    let intent = indexed_select(state);
    let admission = indexed_admit(state, intent, false, u32:0);
    assert_eq(admission.consumed, kind != u32:2);
    assert_eq(admission.write_valid, false);
    let updated = indexed_commit(state, state, intent, admission);
    let actual = assert_committed_borrow_reference(state, updated, intent, admission, true);
    let next = actual.indexed_context[u32:0];
    assert_eq(next.consuming, true);
    assert_eq(next.banks.banks[bank].status, indexed_collection_core::Status::BORROWED);
    assert_eq(indexed_failure(next), hls_failure::NONE);
    assert_eq(next.deferred_frame_valid, kind % u32:2 == u32:0);
    assert_eq(next.deferred_frame, if kind == u32:0 { incoming } else { context.deferred_frame });
    assert_eq(next.deferred_failure, if kind == u32:1 { hls_failure::INVALID_MESSAGE }
      else { context.deferred_failure });
    assert_eq(actual.pending_valid[u32:0], kind == u32:2);
    assert_eq(actual.indexed_candidates[u32:0], false);
    ()
  }(())
}

// Missing/withheld admission and other-actor writes cannot replace the issuing row;
// unrelated retirement is composed before commit exactly as in the scheduler.
#[test]
fn committed_borrow_admission_ownership_reference_test() {
  for (i, _): (u32, ()) in u32:0..u32:12 {
    let bank = i % u32:2;
    let other = u32:1 - bank;
    let kind = i / u32:2;
    let context = committed_borrow_context(bank);
    let successor = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      status:indexed_collection_core::Status::PROVISIONAL, key:u32:8,
      generation:u32:73, candidates:u3:7, seen:u3:1,
      ..zero!<indexed_collection_core::Bank<INDEXED_CAPACITY>>() };
    let context = IndexedContext { banks:IndexedBanks {
        banks:if kind == u32:1 { update(context.banks.banks, other, successor) }
          else { context.banks.banks }, ..context.banks },
      deferred_frame_valid:kind == u32:2, ..context };
    let admission_slot = if kind == u32:5 { u32:2 } else if kind >= u32:3 { u32:1 } else { u32:0 };
    let key = if kind == u32:1 { u32:9 } else if kind == u32:5 { u32:28 }
      else if kind >= u32:3 { u32:18 } else { u32:7 };
    let incoming = frame(key, if kind == u32:2 { u32:3 } else { u32:0 }, u8:97);
    let state = committed_borrow_state(context, incoming, admission_slot);
    let retiring = kind >= u32:4;
    let retired_context = if retiring {
      whole_row_borrow(state.indexed_context[u32:2], indexed_ticket(state.indexed_context[u32:2]))
    } else { state.indexed_context[u32:2] };
    let state = SharedState<u32:3,u32:2> {
      indexed_context:update(state.indexed_context, u32:2, retired_context),
      indexed_candidates:update(state.indexed_candidates, u32:2, indexed_ready(retired_context)),
      pending_valid:if kind == u32:0 { [false,false] } else { state.pending_valid }, ..state };
    let intent = indexed_select(state);
    let admission = indexed_admit(state, intent, retiring, u32:2);
    assert_eq(admission.consumed, kind == u32:3 || kind == u32:4);
    let retired = indexed_retire(state, retiring, u32:2, machine(u32:28, true, false));
    let updated = indexed_commit(state, retired, intent, admission);
    let actual = assert_committed_borrow_reference(state, updated, intent, admission, true);
    assert_eq(actual.indexed_context[u32:0].consuming, true);
    assert_eq(actual.indexed_context[u32:0].banks.banks[bank].status,
      indexed_collection_core::Status::BORROWED);
    assert_eq(actual.indexed_context[u32:1], updated.indexed_context[u32:1]);
    assert_eq(actual.indexed_context[u32:2], retired.indexed_context[u32:2]);
    assert_eq(actual.pending_valid, updated.pending_valid);
    assert_eq(actual.indexed_candidates[u32:0], false);
    ()
  }(())
}

// Invalid committed tickets cannot become borrowable from this activation's admission.
// Existing source/kernel/machine faults and each ownership/readiness gate return updated unchanged.
#[test]
fn committed_borrow_no_issue_reference_test() {
  for (i, _): (u32, ()) in u32:0..u32:20 {
    let bank = i % u32:2;
    let kind = i / u32:2;
    let context = committed_borrow_context(bank);
    let selected = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      status:if kind == u32:4 { indexed_collection_core::Status::OPEN }
        else if kind == u32:5 { indexed_collection_core::Status::BORROWED }
        else { context.banks.banks[bank].status },
      seen:if kind == u32:4 { u3:1 } else { context.banks.banks[bank].seen },
      ..context.banks.banks[bank] };
    let context = IndexedContext {
      initialized:kind != u32:6, actor_opened:kind != u32:8, consuming:kind == u32:5,
      lease:if kind == u32:5 { indexed_ticket(context).lease } else { context.lease },
      failure:if kind == u32:1 { hls_failure::INVALID_MESSAGE } else { hls_failure::NONE },
      banks:IndexedBanks { banks:update(context.banks.banks, bank, selected),
        failure:if kind == u32:2 {
          indexed_collection_core::Error { code:indexed_collection_core::Fault::MEMBER_RANGE,
            key:u32:99, member:u32:77 }
        } else { context.banks.failure }, ..context.banks },
      machine:ActorState { enter_pending:kind == u32:7,
        next_event:if kind == u32:9 { u8:1 } else { u8:0 },
        failure:if kind == u32:3 { hls_failure::INVALID_MESSAGE } else { hls_failure::NONE },
        ..context.machine }, ..context };
    let incoming = frame(if kind == u32:4 { u32:7 } else { u32:8 },
      if kind == u32:4 { u32:1 } else { u32:0 }, u8:98);
    let state = committed_borrow_state(context, incoming, u32:0);
    assert_eq(indexed_ticket(context).valid, kind == u32:0);
    let intent = indexed_select(state);
    let admission = indexed_admit(state, intent, false, u32:0);
    let updated = indexed_commit(state, state, intent, admission);
    let actual = assert_committed_borrow_reference(state, updated, intent, admission, kind != u32:0);
    assert_eq(actual, updated);
    if kind == u32:4 {
      assert_eq(admission.write_valid, true);
      assert_eq(actual.indexed_context[u32:0].banks.banks[bank].status,
        indexed_collection_core::Status::SEALED);
      assert_eq(actual.indexed_context[u32:0].consuming, false)
    } else { () };
    ()
  }(())
}

// Distinguish all six fixed rows and both physical banks, including defined malformed metadata.
fn fixed_descriptor_contexts(first: indexed_collection_core::Status,
    second: indexed_collection_core::Status, matches: u32) -> IndexedContext[6] {
  unroll_for! (actor, rows): (u32, IndexedContext[6]) in u32:0..u32:6 {
    let base = committed_borrow_context(actor % u32:2);
    let key = u32:7 + actor * u32:10;
    let banks = unroll_for! (bank, rows): (u32, indexed_collection_core::Bank<INDEXED_CAPACITY>[2]) in u32:0..u32:2 {
      update(rows, bank, indexed_collection_core::Bank<INDEXED_CAPACITY> {
        status:if bank == u32:0 { first } else { second },
        key:if ((matches >> bank) & u32:1) != u32:0 { key } else { key + u32:100 + bank },
        generation:if actor == u32:5 { !u32:0 } else { actor * u32:2 + bank + u32:23 },
        members:(actor + bank) as u3, seen:(actor + bank + u32:1) as u3,
        ..base.banks.banks[bank] })
    }(base.banks.banks);
    let context = IndexedContext {
      machine:ActorState { gather:GatherState { progress:GatherProgress { key,
        ..base.machine.gather.progress }, ..base.machine.gather }, ..base.machine },
      banks:IndexedBanks { banks, reset_epoch:key + u32:200, ..base.banks }, ..base };
    update(rows, actor, context)
  }(zero!<IndexedContext[6]>())
}

// Compare every ticket bit in 5x5 status pairs and four key-match patterns at six slots.
// In particular, the first matching occupied bank wins over a second SEALED bank.
#[test]
fn fixed_descriptor_ticket_matrix_test() {
  let statuses = [indexed_collection_core::Status::FREE, indexed_collection_core::Status::PROVISIONAL,
    indexed_collection_core::Status::OPEN, indexed_collection_core::Status::SEALED,
    indexed_collection_core::Status::BORROWED];
  for (i, _): (u32, ()) in u32:0..u32:100 {
    let contexts = fixed_descriptor_contexts(statuses[i % u32:5], statuses[(i / u32:5) % u32:5], i / u32:25);
    for (slot, _): (u32, ()) in u32:0..u32:6 {
      let expected = reference_fixed_descriptor_ticket(contexts[slot]);
      assert_eq(indexed_selected_ticket(contexts, slot), expected);
      assert_eq(indexed_ticket(contexts[slot]), expected);
      ()
    }(())
  }(())
}

// Isolate ownership, source/kernel/machine failures, and COMPLETE versus stable boundaries.
#[test]
fn fixed_descriptor_ticket_gates_test() {
  for (kind, _): (u32, ()) in u32:0..u32:12 {
    let contexts = fixed_descriptor_contexts(indexed_collection_core::Status::SEALED,
      indexed_collection_core::Status::SEALED, u32:3);
    let contexts = unroll_for! (actor, rows): (u32, IndexedContext[6]) in u32:0..u32:6 {
      let base = contexts[actor];
      let source_failure = kind == u32:6 || kind == u32:11;
      let kernel_failure = kind == u32:7 || kind == u32:11;
      let context = IndexedContext {
        initialized:kind != u32:1, actor_opened:kind != u32:2, consuming:kind == u32:3,
        failure:if source_failure { hls_failure::INVALID_MESSAGE } else { hls_failure::NONE },
        banks:IndexedBanks { failure:indexed_collection_core::Error {
          code:if kernel_failure { indexed_collection_core::Fault::MEMBER_RANGE }
            else { indexed_collection_core::Fault::NONE }, key:u32:81, member:u32:82 }, ..base.banks },
        machine:ActorState { enter_pending:kind == u32:4 || kind == u32:10,
          next_event:if kind >= u32:8 && kind <= u32:10 { u8:1 } else { u8:0 },
          failure:if kind == u32:5 { hls_failure::INVALID_MESSAGE } else { hls_failure::NONE },
          gather:GatherState { progress:GatherProgress {
            status:if kind == u32:9 || kind == u32:10 { GatherStatus::COMPLETE } else { GatherStatus::OPEN },
            ..base.machine.gather.progress }, ..base.machine.gather }, ..base.machine }, ..base };
      update(rows, actor, context)
    }(contexts);
    for (slot, _): (u32, ()) in u32:0..u32:6 {
      let actual = indexed_selected_ticket(contexts, slot);
      assert_eq(actual, reference_fixed_descriptor_ticket(contexts[slot]));
      assert_eq(actual.valid, kind == u32:0 || kind == u32:9);
      ()
    }(())
  }(())
}

// Compare complete issue state for every selected actor, both bank positions, and issue enable.
// An unrelated retirement supplies the updated view; selection must still use committed metadata.
#[test]
fn fixed_descriptor_six_row_issue_test() {
  for (i, _): (u32, ()) in u32:0..u32:24 {
    let slot = i % u32:6;
    let bank = (i / u32:6) % u32:2;
    let issuing = i < u32:12;
    let contexts = fixed_descriptor_contexts(indexed_collection_core::Status::SEALED,
      indexed_collection_core::Status::SEALED, u32:1 << bank);
    let committed = SharedState<u32:6,u32:2> { indexed_context:contexts,
      indexed_candidates:[true,true,true,true,true,true], ..zero!<SharedState<u32:6,u32:2>>() };
    let retiring_slot = (slot + u32:1) % u32:6;
    let updated = indexed_retire(committed, true, retiring_slot, machine(u32:91, true, false));
    let intent = zero!<mailbox::Admission>();
    let admission = zero!<IndexedAdmission>();
    let actual = indexed_issue(committed, updated, intent, admission, issuing, slot);
    assert_eq(actual, reference_fixed_descriptor_issue(committed, updated, intent, admission, issuing, slot));
    assert_eq(actual.indexed_context[retiring_slot], updated.indexed_context[retiring_slot]);
    if !issuing { assert_eq(actual, updated) } else {
      assert_eq(actual.indexed_context[slot].consuming, true);
      assert_eq(actual.indexed_context[slot].lease, reference_fixed_descriptor_ticket(contexts[slot]).lease)
    };
    ()
  }(())
}

// Frozen pre-specialization indexed_admit; only its name changes. This raw-frame
// reference checks production-selected traffic, not forged valid Admission values.
fn reference_selected_admit<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, intent: mailbox::Admission,
    retiring: bool, retiring_slot: u32) -> IndexedAdmission {
  let context = state.indexed_context[intent.slot];
  let frame = state.pending[intent.producer].frame;
  let input = indexed_decode(frame);
  if !intent.valid || (retiring && retiring_slot == intent.slot) ||
      !indexed_can_accept(context, input) {
    IndexedAdmission { context, ..zero!<IndexedAdmission>() }
  } else {
    indexed_push(context, frame, input, intent.slot)
  }
}

// Compare every valid selection and interpreter-defined invalid selection.
// The frozen helper eagerly indexes the row and casts the opcode to this fixture's
// Tag enum before testing intent.valid. Other rejected inputs are selection-only witnesses.
fn assert_selected_admit_reference(state: SharedState<u32:2,u32:2>,
    retiring: bool, retiring_slot: u32) {
  let intent = indexed_select(state);
  let incoming = state.pending[intent.producer].frame;
  let op = incoming.header.op;
  let known_tag = op == Tag::NONE as u8 || op == Tag::ERROR as u8 ||
    op == Tag::CELL as u8 || op == Tag::PIECE as u8 || op == Tag::ELEMENT as u8;
  let reference_defined = intent.slot < u32:2 && known_tag;
  assert_eq(intent.valid && !reference_defined, false);
  if intent.valid {
    assert_eq(indexed_selected_frame(incoming), incoming)
  } else { () };
  if reference_defined {
    let expected = reference_selected_admit(state, intent, retiring, retiring_slot);
    let actual = indexed_admit(state, intent, retiring, retiring_slot);
    assert_eq(actual, expected)
  } else { () }
}

// Every opcode passes through production arbitration before admission specialization.
#[test]
fn selected_tag_all_opcodes_reference_test() {
  let context = indexed_control(zero!<IndexedContext>(), machine(u32:7, true, false));
  let good = frame(u32:7, u32:0, u8:173);
  for (op, _): (u32, ()) in u32:0..u32:256 {
    let incoming = axis::Frame { header:axis::Header { op:op as u8,
      txid:(op as u8) ^ u8:85, flags:!(op as u8), ..good.header }, ..good };
    let state = SharedState<u32:2,u32:2> { indexed_context:[context, context],
      pending:[ScheduledRequest { slot:u32:0, frame:incoming, credit:false },
        ScheduledRequest { slot:u32:1, frame:good, credit:false }],
      pending_valid:[true, false], ..zero!<SharedState<u32:2,u32:2>>() };
    assert_eq(indexed_select(state).valid, op as u8 == Tag::PIECE as u8);
    assert_selected_admit_reference(state, false, u32:0);
    ()
  }(())
}

// Six independent bits cover pending validity, credit, out-of-range slot, bad
// length, partial lift and a second eligible producer; both retirement slots conflict.
#[test]
fn selected_tag_input_boundaries_reference_test() {
  let contexts = [indexed_control(zero!<IndexedContext>(), machine(u32:7, true, false)),
    indexed_control(zero!<IndexedContext>(), machine(u32:11, true, true))];
  for (kind, _): (u32, ()) in u32:0..u32:64 {
    let partial = (kind & u32:16) != u32:0;
    let good = frame(u32:7, if partial { u32:3 } else { u32:0 }, u8:181);
    let incoming = axis::Frame { header:axis::Header {
      payload_words:if (kind & u32:8) != u32:0 { u8:1 } else { good.header.payload_words },
      txid:u8:137, flags:u8:91, ..good.header }, ..good };
    let slot = if (kind & u32:4) == u32:0 { u32:0 }
      else if partial { u32:0xffff_ffff } else { u32:2 };
    let state = SharedState<u32:2,u32:2> { indexed_context:contexts,
      pending:[ScheduledRequest { slot, frame:incoming, credit:(kind & u32:2) != u32:0 },
        ScheduledRequest { slot:u32:1, frame:frame(u32:11, u32:0, u8:183), credit:false }],
      pending_valid:[(kind & u32:1) != u32:0, (kind & u32:32) != u32:0],
      indexed_cursor:(kind / u32:16) % u32:2, ..zero!<SharedState<u32:2,u32:2>>() };
    let intent = indexed_select(state);
    let first_eligible = (kind & u32:7) == u32:1;
    let second_eligible = (kind & u32:32) != u32:0;
    assert_eq(intent.valid, first_eligible || second_eligible);
    if intent.valid && slot >= u32:2 {
      assert_eq(intent.producer, u32:1)
    } else { () };
    assert_selected_admit_reference(state, false, u32:0);
    assert_selected_admit_reference(state, true, u32:0);
    assert_selected_admit_reference(state, true, u32:1);
    ()
  }(())
}

// Source waiting/current/failure and unstable actor boundaries retain identical
// partial-lift normalization for current, successor and rejected keys.
#[test]
fn selected_tag_source_boundaries_reference_test() {
  for (i, _): (u32, ()) in u32:0..u32:48 {
    let kind = i / u32:6;
    let m = machine(u32:7, true, kind == u32:1 || kind == u32:4);
    let context = indexed_control(zero!<IndexedContext>(), m);
    let context = IndexedContext { initialized:kind != u32:5,
      failure:if kind == u32:6 { hls_failure::INVALID_MESSAGE } else { hls_failure::NONE },
      machine:ActorState { enter_pending:kind == u32:2,
        next_event:if kind == u32:3 { u8:1 } else { u8:0 },
        failure:if kind == u32:7 { hls_failure::INVALID_MESSAGE } else { hls_failure::NONE },
        data:Cell { current_mode:if kind == u32:4 { u8:1 } else { u8:0 }, ..m.data },
        ..m }, ..context };
    let incoming = frame(u32:7 + (i % u32:6) / u32:2,
      if (i % u32:2) == u32:0 { u32:0 } else { u32:3 }, u8:191);
    let state = SharedState<u32:2,u32:2> { indexed_context:[context, context],
      pending:[ScheduledRequest { slot:u32:0, frame:incoming, credit:false },
        zero!<ScheduledRequest>()], pending_valid:[true, false],
      ..zero!<SharedState<u32:2,u32:2>>() };
    assert_selected_admit_reference(state, false, u32:0);
    ()
  }(())
}


// Frozen scalar-opening-r1 adapter bodies from template SHA-256
// f79a8416298a53a008e98d736fcfc4dfd6c4818fc98185bb9f90f2bb964f6c17. Only function/cross-call names and the independent frozen open change.
// Source decisions and post-release validity remain in their original order.
fn reference_scalar_open(context: IndexedContext, opening: GatherProgress, checks: IndexedChecks)
    -> IndexedContext {
  let found = indexed_find(context.banks, opening.key);
  let reservation = if found.0 {
    (context.banks, indexed_collection_core::Result {
      outcome: indexed_collection_core::Outcome::ACCEPTED,
      lease: indexed_lease(context.banks, found.1), ..zero!<indexed_collection_core::Result>() })
  } else { indexed_collection_core::reserve(context.banks, opening.key, !GatherMembers:0) };
  if reservation.1.outcome != indexed_collection_core::Outcome::ACCEPTED || opening.site != INDEXED_SITE {
    IndexedContext { failure: hls_failure::first(context.failure, hls_failure::REDUCTION_PROTOCOL), ..context }
  } else {
    let reserved = IndexedContext { banks: reservation.0, ..context };
    let bank = reservation.1.lease.bank as u32;
    let eligibility = checks.representatives[bank];
    let empty = opening.status == GatherStatus::COMPLETE;
    // A physical reservation can outlive logical entry while source dispatch
    // still postpones. The actor progress retains the originally captured mask.
    if !empty && context.representative_valid[bank] && hls_failure::failed(eligibility.failure) {
      IndexedContext { failure: hls_failure::first(context.failure, eligibility.failure), ..reserved }
    } else if !empty && (!indexed_stable(context.machine) ||
        (context.representative_valid[bank] && !eligibility.current)) {
      reserved
    } else {
      let opened = opening_reference::open(reservation.0, reservation.1.lease, opening.expected);
      IndexedContext { banks: opened.0, ..context }
    }
  }
}

// Frozen retirement composes the original opening with unchanged release/revalidation.
fn reference_scalar_control(context: IndexedContext, machine: ActorState) -> IndexedContext {
  let checks = indexed_saved_checks(IndexedContext { initialized: true, machine, ..context });
  let released = if context.consuming {
    indexed_collection_core::release(context.banks, context.lease).0
  } else { context.banks };
  let next = IndexedContext { initialized: true, machine, banks: released, consuming: false,
    representative_valid: if context.consuming {
      update(context.representative_valid, context.lease.bank as u32, false)
    } else { context.representative_valid }, ..context };
  let active = machine.gather.progress.status != GatherStatus::IDLE;
  let found = indexed_find(next.banks, machine.gather.progress.key);
  let deferred_open = found.0 &&
    next.banks.banks[found.1 as u32].status == indexed_collection_core::Status::PROVISIONAL;
  let opening = active && (!context.actor_opened || context.consuming || deferred_open);
  let opened = if opening && !hls_failure::failed(machine.failure) {
    reference_scalar_open(next, machine.gather.progress, checks)
  } else { next };
  indexed_revalidate(IndexedContext { actor_opened: active, ..opened }, checks)
}


// Compare complete contexts against the frozen adapter and independent frozen kernel open.
fn assert_scalar_open_reference(context: IndexedContext, opening: GatherProgress) -> IndexedContext {
  let checks = indexed_saved_checks(context);
  let actual = indexed_open(context, opening, checks);
  assert_eq(actual, reference_scalar_open(context, opening, checks));
  actual
}

// 200 contexts: both banks; current/future/rejected/malformed/partial frames;
// current/postpone/reject/entry/continuation boundaries; valid/stale representatives;
// and nonempty/empty openings. Classification is the production source classifier.
#[test]
fn scalar_open_source_gates_reference_test() {
  for (i, ()): (u32, ()) in u32:0..u32:200 {
    let slot = i % u32:2;
    let kind = (i / u32:2) % u32:5;
    let boundary = (i / u32:10) % u32:5;
    let valid = ((i / u32:50) % u32:2) != u32:0;
    let empty = i >= u32:100;
    let context = retirement_context(slot, indexed_collection_core::Status::PROVISIONAL);
    let good = frame(if kind == u32:1 { u32:8 } else if kind == u32:2 { u32:9 } else { u32:7 },
      if kind == u32:4 { u32:3 } else { u32:0 }, u8:79);
    let representative = if kind == u32:3 {
      axis::Frame { header:axis::Header { payload_words:u8:1, ..good.header }, ..good }
    } else { good };
    let base = machine(u32:7, true, true);
    let returned = ActorState { enter_pending:boundary == u32:3,
      next_event:if boundary == u32:4 { u8:1 } else { u8:0 },
      data:Cell { current_mode:if boundary <= u32:2 { boundary as u8 } else { u8:0 }, ..base.data }, ..base };
    let context = IndexedContext { machine:returned,
      representatives:update(context.representatives, slot, representative),
      representative_valid:update([true, true], slot, valid), ..context };
    let opening = GatherProgress { status:if empty { GatherStatus::COMPLETE } else { GatherStatus::OPEN },
      expected:if empty { u3:0 } else { u3:3 }, ..returned.gather.progress };
    let actual = assert_scalar_open_reference(context, opening);
    assert_eq(actual.banks.banks[u32:1 - slot], context.banks.banks[u32:1 - slot]);
    ()
  }(())
}

// 160 contexts cover either selected bank in every status, clear/kernel/source/both
// preexisting failures, correct/wrong site and nonempty/empty membership. Wrong-site
// rejection discards even a prepared reservation or a newly diagnosed opening fault.
#[test]
fn scalar_open_failure_discard_reference_test() {
  let statuses = [indexed_collection_core::Status::FREE, indexed_collection_core::Status::PROVISIONAL,
    indexed_collection_core::Status::OPEN, indexed_collection_core::Status::SEALED,
    indexed_collection_core::Status::BORROWED];
  for (i, ()): (u32, ()) in u32:0..u32:160 {
    let slot = i % u32:2;
    let kind = (i / u32:10) % u32:4;
    let wrong_site = ((i / u32:40) % u32:2) != u32:0;
    let empty = i >= u32:80;
    let context = retirement_context(slot, statuses[(i / u32:2) % u32:5]);
    let other = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      status:indexed_collection_core::Status::SEALED, ..context.banks.banks[u32:1 - slot] };
    let context = IndexedContext { machine:machine(u32:7, true, true),
      failure:if (kind & u32:2) != u32:0 { hls_failure::INVALID_MESSAGE } else { hls_failure::NONE },
      banks:IndexedBanks { banks:update(context.banks.banks, u32:1 - slot, other),
        failure:indexed_collection_core::Error { code:if (kind & u32:1) != u32:0 {
          indexed_collection_core::Fault::MEMBER_RANGE } else { indexed_collection_core::Fault::NONE },
          ..context.banks.failure }, ..context.banks }, ..context };
    let opening = GatherProgress { site:if wrong_site { GatherSite::WRONG_TEST_SITE } else { INDEXED_SITE },
      status:if empty { GatherStatus::COMPLETE } else { GatherStatus::OPEN },
      expected:if empty { u3:0 } else { u3:3 }, ..context.machine.gather.progress };
    let actual = assert_scalar_open_reference(context, opening);
    if wrong_site {
      assert_eq(actual, IndexedContext {
        failure:hls_failure::first(context.failure, hls_failure::REDUCTION_PROTOCOL), ..context })
    } else { () }
  }(())
}

// 64 retirement contexts: either borrowed bank, provisional/sealed other bank,
// good/malformed old representative, clear/sticky kernel error, same/new key and
// nonempty/empty opening. Checks are captured before release; validity is read after it.
#[test]
fn scalar_open_release_reuse_reference_test() {
  for (i, ()): (u32, ()) in u32:0..u32:64 {
    let slot = i % u32:2;
    let sealed_other = ((i / u32:2) % u32:2) != u32:0;
    let malformed = ((i / u32:4) % u32:2) != u32:0;
    let faulted = ((i / u32:8) % u32:2) != u32:0;
    let new_key = ((i / u32:16) % u32:2) != u32:0;
    let empty = i >= u32:32;
    let context = retirement_context(slot, indexed_collection_core::Status::BORROWED);
    let good = context.representatives[slot];
    let other = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      status:if sealed_other { indexed_collection_core::Status::SEALED }
        else { indexed_collection_core::Status::PROVISIONAL }, ..context.banks.banks[u32:1 - slot] };
    let context = IndexedContext { consuming:true, actor_opened:true,
      representatives:update(context.representatives, slot, if malformed {
        axis::Frame { header:axis::Header { payload_words:u8:1, ..good.header }, ..good }
      } else { good }),
      banks:IndexedBanks { banks:update(context.banks.banks, u32:1 - slot, other),
        failure:indexed_collection_core::Error { code:if faulted { indexed_collection_core::Fault::MEMBER_RANGE }
          else { indexed_collection_core::Fault::NONE }, ..context.banks.failure }, ..context.banks }, ..context };
    let base = machine(if new_key { u32:9 } else { u32:7 }, true, true);
    let returned = ActorState { gather:GatherState { progress:GatherProgress {
      status:if empty { GatherStatus::COMPLETE } else { GatherStatus::OPEN },
      expected:if empty { u3:0 } else { u3:3 }, ..base.gather.progress }, ..base.gather }, ..base };
    let actual = indexed_control(context, returned);
    assert_eq(actual, reference_scalar_control(context, returned));
    assert_eq(actual.representative_valid[slot], false);
    if !faulted && sealed_other {
      assert_eq(actual.failure, hls_failure::NONE);
      assert_eq(actual.banks.banks[slot].key, returned.gather.progress.key);
      assert_eq(actual.banks.banks[slot].generation, u32:0);
      assert_eq(actual.banks.banks[slot].status, if empty { indexed_collection_core::Status::SEALED }
        else { indexed_collection_core::Status::OPEN })
    } else { () }
  }(())
}

// Four direct openings distinguish exhausted capacity from duplicate stored keys.
// The duplicate case retains the original first-match rule despite the other frame's fault.
#[test]
fn scalar_open_capacity_and_first_match_reference_test() {
  for (i, ()): (u32, ()) in u32:0..u32:4 {
    let duplicate = (i & u32:1) != u32:0;
    let wrong_site = (i & u32:2) != u32:0;
    let context = retirement_context(u32:0, indexed_collection_core::Status::PROVISIONAL);
    let bad = frame(u32:9,u32:0,u8:99);
    let second = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      key:if duplicate { u32:7 } else { u32:8 }, ..context.banks.banks[u32:1] };
    let context = IndexedContext { machine:machine(u32:7, true, true),
      representatives:update(context.representatives, u32:1, bad),
      banks:IndexedBanks { banks:update(context.banks.banks, u32:1, second), ..context.banks }, ..context };
    let opening = GatherProgress { key:if duplicate { u32:7 } else { u32:9 },
      site:if wrong_site { GatherSite::WRONG_TEST_SITE } else { INDEXED_SITE }, ..context.machine.gather.progress };
    let actual = assert_scalar_open_reference(context, opening);
    if !duplicate || wrong_site {
      assert_eq(actual, IndexedContext { failure:hls_failure::REDUCTION_PROTOCOL, ..context })
    } else {
      assert_eq(actual.failure, hls_failure::NONE);
      assert_eq(actual.banks.banks[u32:0].status, indexed_collection_core::Status::OPEN);
      assert_eq(actual.banks.banks[u32:1], second)
    }
  }(())
}


// Frozen original indexed_commit from template SHA-256 1991baf496bdfbbecc782fd99d594ea820b7e61f35a886a4830184b5ec92db80;
// only its function name changes. It retains indexed_ready(after) as the oracle.
fn reference_admission_ready_commit<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>, intent: mailbox::Admission,
    admission: IndexedAdmission) -> SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
  let cursor = if !intent.valid { state.indexed_cursor }
    else if intent.producer + u32:1 == PRODUCER_COUNT { u32:0 } else { intent.producer + u32:1 };
  if !admission.consumed {
    SharedState<ACTOR_COUNT, PRODUCER_COUNT> { indexed_cursor: cursor, ..state }
  } else {
    // Admission owns only member metadata, representative frames and faults.
    let contexts = unroll_for! (actor, rows): (u32, IndexedContext[ACTOR_COUNT]) in u32:0..ACTOR_COUNT {
      let previous = state.indexed_context[actor];
      let selected = actor == intent.slot;
      let changed = IndexedContext { banks: admission.context.banks,
        representative_valid: admission.context.representative_valid,
        deferred_failure: admission.context.deferred_failure,
        deferred_frame_valid: admission.context.deferred_frame_valid,
        failure: admission.context.failure, ..previous };
      let metadata = if selected { changed } else { previous };
      // Static row/bank enables retain each register's own old frame directly.
      let representatives = unroll_for! (bank, frames): (u32, axis::Frame[2]) in u32:0..u32:2 {
        update(frames, bank, if selected && admission.representative_write &&
            bank == admission.representative_bank as u32 { admission.frame }
          else { previous.representatives[bank] })
      }(previous.representatives);
      let deferred_frame = if selected && admission.deferred_write { admission.frame }
        else { previous.deferred_frame };
      update(rows, actor, IndexedContext { representatives, deferred_frame, ..metadata })
    }(state.indexed_context);
    SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      indexed_context: contexts,
      indexed_candidates: update(state.indexed_candidates, intent.slot, indexed_ready(admission.context)),
      indexed_cursor: cursor,
      pending_valid: mailbox::clear_pending(state.pending_valid, intent.producer, true), ..state }
  }
}

// Use the actual checked push result; verify unchanged logical ownership and the
// complete production commit against the frozen version, including arbitrary old
// candidate bits. Direct push also covers defined states rejected by can_accept.
fn assert_fixed_bank_readiness(before: IndexedContext, incoming: axis::Frame) {
  let admission = indexed_push(before, incoming, indexed_decode(incoming), u32:0);
  assert_eq(indexed_admission_ready(before, admission.context), indexed_ready(admission.context));
  assert_eq((admission.context.initialized, admission.context.machine,
    admission.context.actor_opened, admission.context.consuming, admission.context.lease),
    (before.initialized, before.machine, before.actor_opened, before.consuming, before.lease));
  let state = SharedState<u32:2,u32:1> { indexed_context:[before,before],
    indexed_candidates:[true,false], pending_valid:[true],
    pending:[ScheduledRequest { slot:u32:0, frame:incoming, credit:false }],
    ..zero!<SharedState<u32:2,u32:1>>() };
  let intent = mailbox::Admission { valid:true, slot:u32:0, producer:u32:0, physical:u8:0 };
  assert_eq(indexed_commit(state, state,intent,admission),
    reference_admission_ready_commit(state,intent,admission));
}

// Two hundred defined states: all bank-status pairs, either active source key,
// and current/successor/foreign/partial-lift traffic. FREE metadata deliberately
// contains diagnostic bytes; status remains the authority for live key matching.
#[test]
fn admission_readiness_status_key_grid_test() {
  let statuses = [indexed_collection_core::Status::FREE,
    indexed_collection_core::Status::PROVISIONAL, indexed_collection_core::Status::OPEN,
    indexed_collection_core::Status::SEALED, indexed_collection_core::Status::BORROWED];
  for (i, _): (u32, ()) in u32:0..u32:200 {
    let a = statuses[i % u32:5];
    let b = statuses[(i / u32:5) % u32:5];
    let active = u32:7 + ((i / u32:25) % u32:2);
    let traffic = i / u32:50;
    let m = machine(u32:7,true,true);
    let m = ActorState { gather:GatherState { progress:GatherProgress {
      key:active, ..m.gather.progress }, ..m.gather }, ..m };
    let before = IndexedContext { initialized:true, actor_opened:true, machine:m,
      banks:IndexedBanks { reset_epoch:u32:101,
        banks:[indexed_collection_core::Bank<INDEXED_CAPACITY> {
          status:a, key:u32:7, generation:u32:31, candidates:u3:7, members:u3:3,
          seen:if a == indexed_collection_core::Status::SEALED || a == indexed_collection_core::Status::BORROWED { u3:3 } else { u3:1 },
          ..zero!<indexed_collection_core::Bank<INDEXED_CAPACITY>>() },
        indexed_collection_core::Bank<INDEXED_CAPACITY> {
          status:b, key:u32:8, generation:u32:47, candidates:u3:7, members:u3:3,
          seen:if b == indexed_collection_core::Status::SEALED || b == indexed_collection_core::Status::BORROWED { u3:3 } else { u3:1 },
          ..zero!<indexed_collection_core::Bank<INDEXED_CAPACITY>>() }],
        ..zero!<IndexedBanks>() }, ..zero!<IndexedContext>() };
    let incoming = frame(if traffic == u32:1 { u32:8 } else if traffic == u32:2 { u32:9 } else { u32:7 },
      if traffic == u32:3 { u32:3 } else { u32:1 }, u8:71);
    assert_fixed_bank_readiness(before,incoming);
  }(());
}

// One hundred twenty-eight logical gate combinations cover both progress states,
// initialization, machine failure, source opening, ownership, entry and continuation. An
// empty COMPLETE view can remain eligible ahead of a continuation; stable alone
// is therefore insufficient. Actual push gates remain authoritative in every case.
#[test]
fn admission_readiness_logical_gates_test() {
  for (i, _): (u32, ()) in u32:0..u32:128 {
    let seed = committed_borrow_context(u32:0);
    let m = ActorState {
      failure:if (i & u32:2) != u32:0 { hls_failure::INVALID_MESSAGE } else { hls_failure::NONE },
      enter_pending:(i & u32:16) != u32:0,
      next_event:if (i & u32:32) != u32:0 { u8:1 } else { u8:0 },
      gather:GatherState { progress:GatherProgress {
        status:if (i & u32:64) != u32:0 { GatherStatus::COMPLETE } else { GatherStatus::OPEN },
        ..seed.machine.gather.progress }, ..seed.machine.gather }, ..seed.machine };
    let before = IndexedContext { initialized:(i & u32:1) != u32:0,
      actor_opened:(i & u32:4) != u32:0, consuming:(i & u32:8) != u32:0, machine:m, ..seed };
    assert_fixed_bank_readiness(before,frame(u32:8,u32:0,u8:73));
  }(());
}

// Empty committed completions retain their explicit priority over a continuation.
#[test]
fn admission_readiness_empty_continuation_test() {
  for (bank, _): (u32, ()) in u32:0..u32:2 {
    let seed = committed_borrow_context(bank);
    let empty = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      members:u3:0, seen:u3:0, ..seed.banks.banks[bank] };
    let before = IndexedContext { banks:IndexedBanks {
        banks:update(seed.banks.banks,bank,empty), ..seed.banks },
      machine:ActorState { next_event:u8:1,
        gather:GatherState { progress:GatherProgress {
          status:GatherStatus::COMPLETE, expected:u3:0, seen:u3:0, remaining:u8:0,
          ..seed.machine.gather.progress }, ..seed.machine.gather }, ..seed.machine }, ..seed };
    assert_eq(indexed_ready(before),true);
    assert_fixed_bank_readiness(before,frame(u32:8,u32:0,u8:89));
  }(());
}

// Twenty-four cases distinguish source postponement/failure, immediate malformed
// frames, deferred lift/frame/kernel poison and already terminal errors. Both bank
// positions occur; a deferred error must not be treated as a terminal wakeup.
#[test]
fn admission_readiness_fault_and_postpone_test() {
  for (i, _): (u32, ()) in u32:0..u32:24 {
    let bank = i % u32:2;
    let kind = i / u32:2;
    let seed = committed_borrow_context(bank);
    let selected = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      status:if kind == u32:4 || kind == u32:5 { indexed_collection_core::Status::PROVISIONAL }
        else { indexed_collection_core::Status::OPEN }, seen:u3:1,
      deferred:indexed_collection_core::Error {
        code:if kind == u32:5 { indexed_collection_core::Fault::DUPLICATE_MEMBER }
          else { indexed_collection_core::Fault::NONE }, key:u32:7, member:u32:0 },
      ..seed.banks.banks[bank] };
    let before = IndexedContext { banks:IndexedBanks {
        banks:update(seed.banks.banks,bank,selected),
        failure:indexed_collection_core::Error {
          code:if kind == u32:7 { indexed_collection_core::Fault::MEMBER_RANGE }
            else { indexed_collection_core::Fault::NONE }, key:u32:77, member:u32:33 }, ..seed.banks },
      failure:if kind == u32:8 { hls_failure::INVALID_MESSAGE } else { hls_failure::NONE },
      deferred_failure:if kind == u32:6 || kind == u32:11 { hls_failure::INVALID_MESSAGE } else { hls_failure::NONE },
      deferred_frame_valid:kind == u32:10 || kind == u32:11,
      machine:ActorState { enter_pending:kind == u32:3 || kind == u32:6 || kind >= u32:9,
        data:Cell { current_mode:if kind == u32:0 { u8:1 } else if kind == u32:1 { u8:2 } else { u8:0 },
          ..seed.machine.data }, ..seed.machine }, ..seed };
    let good = frame(u32:7, if kind == u32:4 || kind == u32:5 { u32:0 }
      else if kind >= u32:9 { u32:3 } else { u32:1 }, u8:79);
    let incoming = if kind == u32:2 || kind == u32:3 {
      axis::Frame { header:axis::Header { payload_words:u8:1, ..good.header }, ..good }
    } else { good };
    assert_fixed_bank_readiness(before,incoming);
  }(());
}

// Preserve first-match behavior even for defined duplicate-key metadata that
// normal reservation cannot create: a later SEALED bank cannot hide the first.
#[test]
fn admission_readiness_first_match_priority_test() {
  let statuses = [indexed_collection_core::Status::FREE,
    indexed_collection_core::Status::PROVISIONAL, indexed_collection_core::Status::OPEN,
    indexed_collection_core::Status::SEALED, indexed_collection_core::Status::BORROWED];
  for (i, _): (u32, ()) in u32:0..u32:5 {
    let seed = committed_borrow_context(u32:1);
    let first = indexed_collection_core::Bank<INDEXED_CAPACITY> {
      status:statuses[i], key:u32:7, generation:u32:91, candidates:u3:7, members:u3:3, seen:u3:1,
      ..zero!<indexed_collection_core::Bank<INDEXED_CAPACITY>>() };
    let before = IndexedContext { banks:IndexedBanks {
      banks:update(seed.banks.banks,u32:0,first), ..seed.banks }, ..seed };
    assert_fixed_bank_readiness(before,frame(u32:7,u32:1,u8:83));
  }(());
}


// Admission reads the original row while disjoint retirement changes another
// actor's machine/bank/representative state. Full commit still matches the frozen
// helper; the explicit snapshot changes dependency placement, not its result.
#[test]
fn admission_readiness_disjoint_retirement_test() {
  let seed = committed_borrow_context(u32:0);
  let accepting = IndexedContext { banks:IndexedBanks {
    banks:update(seed.banks.banks,u32:0,indexed_collection_core::Bank<INDEXED_CAPACITY> {
      status:indexed_collection_core::Status::OPEN, seen:u3:1, ..seed.banks.banks[u32:0] }),
    ..seed.banks }, ..seed };
  let retiring = whole_row_borrow(seed,indexed_ticket(seed));
  let incoming = frame(u32:7,u32:1,u8:97);
  let state = SharedState<u32:2,u32:1> { indexed_context:[accepting,retiring],
    indexed_candidates:[false,false], pending_valid:[true],
    pending:[ScheduledRequest { slot:u32:0, frame:incoming, credit:false }],
    ..zero!<SharedState<u32:2,u32:1>>() };
  let intent = indexed_select(state);
  let admission = indexed_admit(state,intent,true,u32:1);
  assert_eq((admission.consumed,admission.write_valid),(true,true));
  let retired = indexed_retire(state,true,u32:1,machine(u32:8,true,false));
  assert_eq(retired.indexed_context[u32:1] == state.indexed_context[u32:1],false);
  let actual = indexed_commit(state,retired,intent,admission);
  assert_eq(actual,reference_admission_ready_commit(retired,intent,admission));
  assert_eq(actual.indexed_context,[admission.context,retired.indexed_context[u32:1]]);
  assert_eq(actual.indexed_candidates,[true,false]);
}

// Execute one owner clock using production helpers. Output stalls hold the whole
// atomic activation; channel exactly-once behavior is checked by RTL replay.
fn owned_tick(state: SharedState<u32:2, u32:3>, advance: bool)
    -> SharedState<u32:2, u32:3> {
  if !advance { state } else {
    let retiring = state.completed_valid && state.indexed_retirement_valid;
    let retired = indexed_retire_owned(state, retiring, state.completed.slot, machine(u32:7,true,true));
    let admission = indexed_check_owned(state.indexed_input);
    let next_input = indexed_capture_input(state, false, u32:0);
    let updated = indexed_commit(state, retired, state.indexed_input.intent, admission);
    let updated = indexed_refresh(state, updated, retiring, state.completed.slot, admission, false, u32:0);
    let snapshot = indexed_capture_retirement(state);
    SharedState<u32:2,u32:3> { indexed_input: next_input,
      indexed_retirement_valid: snapshot.0 || (state.indexed_retirement_valid && !retiring),
      indexed_retirement: snapshot.1,
      completed_valid: state.completed_valid && !retiring,
      indexed_cursor: if next_input.intent.valid {
        if next_input.intent.producer + u32:1 == u32:3 { u32:0 } else { next_input.intent.producer + u32:1 }
      } else { state.indexed_cursor }, ..updated }
  }
}

// Same-actor members cannot overwrite a selected snapshot, but a second actor
// proceeds concurrently. Check every stall placement over a twelve-clock horizon.
#[test]
fn owned_member_burst_and_stalls_test() {
  let context = indexed_control(zero!<IndexedContext>(), machine(u32:7,true,true));
  let initial = SharedState<u32:2,u32:3> {
    indexed_context: [context,context], pending_valid:[true,true,true],
    pending: [ScheduledRequest { slot:u32:0,frame:frame(u32:7,u32:0,u8:31),credit:false },
      ScheduledRequest { slot:u32:0,frame:frame(u32:7,u32:1,u8:32),credit:false },
      ScheduledRequest { slot:u32:1,frame:frame(u32:7,u32:0,u8:33),credit:false }],
    ..zero!<SharedState<u32:2,u32:3>>() };
  let first = indexed_push(context,initial.pending[u32:0].frame,indexed_decode(initial.pending[u32:0].frame),u32:0);
  let second = indexed_push(first.context,initial.pending[u32:1].frame,indexed_decode(initial.pending[u32:1].frame),u32:0);
  let other = indexed_push(context,initial.pending[u32:2].frame,indexed_decode(initial.pending[u32:2].frame),u32:1);
  for (stall, _): (u32, ()) in u32:0..u32:12 {
    let final = for (cycle, state): (u32, SharedState<u32:2,u32:3>) in u32:0..u32:12 {
      let next = owned_tick(state,cycle != stall);
      assert_eq(if cycle == stall { next == state } else { true },true);
      next
    }(initial);
    assert_eq(final.pending_valid,[false,false,false]);
    assert_eq(final.indexed_context,[second.context,other.context]);
    assert_eq(final.indexed_candidates,[true,false]);
  }(())
}

// A captured admission finishes before retirement snapshots that actor; a new
// same-actor grant cannot starve retirement or observe partially committed banks.
#[test]
fn owned_retirement_admission_hazard_test() {
  let context = indexed_control(zero!<IndexedContext>(), machine(u32:7,true,true));
  let initial = SharedState<u32:2,u32:3> { indexed_context:[context,context],
    pending_valid:[true,false,false],
    pending:[ScheduledRequest { slot:u32:0,frame:frame(u32:7,u32:0,u8:31),credit:false },
      zero!<ScheduledRequest>(),zero!<ScheduledRequest>()],
    ..zero!<SharedState<u32:2,u32:3>>() };
  let granted = owned_tick(initial,true);
  let completed = SharedState<u32:2,u32:3> { completed_valid:true,
    completed:ScheduledRequest { slot:u32:0,..zero!<ScheduledRequest>() },..granted };
  assert_eq(indexed_capture_retirement(completed).0,false);
  assert_eq(indexed_capture_input(completed,false,u32:0).intent.valid,false);
  let admitted = owned_tick(completed,true);
  assert_eq(admitted.indexed_retirement_valid,false);
  let selected = owned_tick(admitted,true);
  assert_eq(selected.indexed_retirement_valid,true);
  assert_eq(selected.indexed_retirement.machine,zero!<ActorState>());
  let committed = owned_tick(selected,true);
  let expected = indexed_retire(admitted,true,u32:0,machine(u32:7,true,true));
  assert_eq(committed.indexed_context,expected.indexed_context);
  assert_eq(committed.completed_valid,false);
  assert_eq(committed.indexed_candidates[u32:0],false);
}

// Stale ready bits and unsent writes cannot issue a read; reset drops every
// owned identity and command. The mask does not depend on output-ready.
#[test]
fn owned_visibility_and_reset_test() {
  let initial=zero!<SharedState<u32:2,u32:3>>();
  assert_eq(indexed_owned_mask(initial),[false,false]);
  let held=SharedState<u32:2,u32:3>{write_gather_valid:true,write_gather_slot:u32:1,
    indexed_dirty:[true,false],..initial};
  assert_eq(indexed_owned_mask(held),[true,true]);
  assert_eq(indexed_owned_mask(zero!<SharedState<u32:2,u32:3>>()),[false,false]);
}

// Malformed input commits the same exact source fault and never a payload write.
// A disabled owned command never inspects its deliberately invalid slot.
#[test]
fn owned_fault_and_disabled_test() {
  let context=indexed_control(zero!<IndexedContext>(),machine(u32:7,true,true));
  let good=frame(u32:7,u32:0,u8:31);
  let bad=axis::Frame { header:axis::Header { payload_words:u8:1,..good.header },..good };
  let owned=IndexedOwnedInput {intent:mailbox::Admission {valid:true,slot:u32:0,..zero!<mailbox::Admission>()},context,frame:bad};
  let checked=indexed_check_owned(owned);
  assert_eq(checked,indexed_push(context,bad,indexed_decode(bad),u32:0));
  assert_eq(checked.write_valid,false);
  assert_eq(indexed_failure(checked.context),hls_failure::INVALID_MESSAGE);
  let disabled=IndexedOwnedInput {intent:mailbox::Admission {slot:u32:999,..zero!<mailbox::Admission>()},..zero!<IndexedOwnedInput>()};
  assert_eq(indexed_check_owned(disabled),zero!<IndexedAdmission>());
}

// A result and its independent metadata arrive at one boundary. An existing
// same-actor admission instead forces a coherent post-commit retry.
#[test]
fn owned_result_capture_overlap_test() {
  let c=indexed_control(zero!<IndexedContext>(),machine(u32:7,true,true));
  let s=SharedState<u32:2,u32:3>{indexed_context:[c,c],..zero!<SharedState<u32:2,u32:3>>()};
  let captured=indexed_capture_result(s,true,u32:1);
  assert_eq(captured.0,true);
  assert_eq(captured.1,IndexedContext{machine:zero!<ActorState>(),..c});
  let held=SharedState<u32:2,u32:3>{indexed_input:IndexedOwnedInput{
    intent:mailbox::Admission{valid:true,slot:u32:1,..zero!<mailbox::Admission>()},..zero!<IndexedOwnedInput>()},..s};
  assert_eq(indexed_capture_result(held,true,u32:1).0,false);
  assert_eq(indexed_capture_result(held,true,u32:0).0,true);
  assert_eq(indexed_capture_result(held,false,u32:999).0,false);
}

// Expanded unmasked bits do not change the physical RAM's selected write lane.
#[test]
fn owned_masked_command_projection_test() {
  for (member, _): (u32, ()) in u32:0..INDEXED_CAPACITY {
    let value=bits[INDEXED_ELEMENT_BITS]:43;
    let reference=indexed_gather_ram::write_member<INDEXED_ELEMENT_BITS,INDEXED_CAPACITY>(u32:2,member,value);
    let expanded=indexed_write_data(value);
    let selected=(expanded >> (member * INDEXED_ELEMENT_BITS)) as bits[INDEXED_ELEMENT_BITS];
    assert_eq(selected,value);
    assert_eq(reference.mask,bits[INDEXED_CAPACITY]:1 << member);
  }(())
}

// Exercise production preparation controls with six actors and both native
// producer counts. Dirty/write hazards may prepare but never release a consumer.
fn check_prepared_overlap<PRODUCERS: u32>() {
  let initial = zero!<SharedState<u32:6, PRODUCERS>>();
  for (slot, _): (u32, ()) in u32:0..u32:6 {
    for (hazard, _): (u32, ()) in u32:0..u32:5 {
      let held = SharedState<u32:6, PRODUCERS> {
        indexed_prepared_valid: true, indexed_prepared_slot: slot,
        indexed_dirty: update(initial.indexed_dirty, slot, hazard == u32:0),
        write_machine_valid: hazard == u32:1, write_machine_slot: slot,
        write_mailbox_valid: hazard == u32:2, write_mailbox_slot: slot,
        write_gather_valid: hazard == u32:3, write_gather_slot: slot,
        indexed_input: IndexedOwnedInput { intent:mailbox::Admission {
          valid:hazard == u32:4,slot,..zero!<mailbox::Admission>() },..zero!<IndexedOwnedInput>() },
        ..initial };
      assert_eq(indexed_prepared_finish(held), false);
      let mask = indexed_prepare_mask(held);
      assert_eq(mask[slot], hazard == u32:4);
      let clean = SharedState<u32:6, PRODUCERS> {
        indexed_prepared_valid: true,indexed_prepared_slot:slot,
        in_flight:update(initial.in_flight,slot,true),..initial };
      assert_eq(indexed_prepared_finish(clean),true);
      assert_eq(indexed_prepare_mask(clean)[slot],true);
      let cancelled=indexed_prepared_in_flight(clean,clean.in_flight,true,false,false,u32:999);
      assert_eq(cancelled,initial.in_flight);
      assert_eq(indexed_prepared_in_flight(clean,clean.in_flight,true,true,false,u32:999),clean.in_flight);
      let other=(slot+u32:1)%u32:6;
      let replaced=indexed_prepared_in_flight(clean,clean.in_flight,true,false,true,other);
      assert_eq(replaced,update(initial.in_flight,other,true));
    }(())
  }(())
}

// Twelve port/identity populations, including cancellation and disabled indices.
#[test]
fn prepared_visibility_and_ownership_test() {
  check_prepared_overlap<u32:19>();
  check_prepared_overlap<u32:22>();
  let disabled=SharedState<u32:6,u32:19>{indexed_prepared_slot:u32:999,
    ..zero!<SharedState<u32:6,u32:19>>()};
  assert_eq(indexed_prepared_finish(disabled),false);
  assert_eq(indexed_prepared_ticket(zero!<IndexedContext[6]>(),false,u32:999),zero!<IndexedTicket>());
}

// Captures release their producer only on commit, not when a prepared actor
// temporarily masks them. All unrelated producers and current contexts survive.
fn check_prepared_capture<PRODUCERS: u32>() {
  let context=indexed_control(zero!<IndexedContext>(),machine(u32:7,true,true));
  let pending=unroll_for! (producer, rows): (u32,ScheduledRequest[PRODUCERS]) in u32:0..PRODUCERS {
    update(rows,producer,ScheduledRequest{slot:producer%u32:6,
      frame:frame(u32:7,u32:0,u8:31),credit:false})
  }(zero!<ScheduledRequest[PRODUCERS]>());
  let valid=unroll_for! (producer, flags): (u32,bool[PRODUCERS]) in u32:0..PRODUCERS {
    update(flags,producer,true)
  }(zero!<bool[PRODUCERS]>());
  let s=SharedState<u32:6,PRODUCERS>{indexed_context:[context,context,context,context,context,context],
    indexed_prepared_valid:true,indexed_prepared_slot:u32:2,pending,pending_valid:valid,
    ..zero!<SharedState<u32:6,PRODUCERS>>()};
  let source=indexed_preparation_source(s,true,u32:4);
  for (producer, _): (u32, ()) in u32:0..PRODUCERS {
    let actor=producer%u32:6;
    assert_eq(source.pending_valid[producer], actor != u32:2 && actor != u32:4);
  }(());
  assert_eq(source.pending,s.pending);
  assert_eq(source.indexed_context,s.indexed_context);
  for (cursor, _): (u32, ()) in u32:0..PRODUCERS {
    let selected=indexed_capture_input(SharedState<u32:6,PRODUCERS>{indexed_cursor:cursor,..s},true,u32:4);
    assert_eq(selected.intent.valid,true);
    assert_eq(selected.intent.slot == u32:2 || selected.intent.slot == u32:4,false);
  }(())
}

// Both native fan-ins keep held and newly prepared actors out of admission.
#[test]
fn prepared_input_capture_test() {
  check_prepared_capture<u32:19>();
  check_prepared_capture<u32:22>();
}

// Finalized gather mode alone supplies a live ticket and borrows its bank;
// ordinary mode leaves a simultaneously available completion untouched.
#[test]
fn prepared_mode_lease_coherence_test() {
  let c=indexed_control(zero!<IndexedContext>(),machine(u32:7,true,true));
  let first=indexed_push(c,frame(u32:7,u32:0,u8:31),indexed_decode(frame(u32:7,u32:0,u8:31)),u32:0);
  let second=indexed_push(first.context,frame(u32:7,u32:1,u8:32),indexed_decode(frame(u32:7,u32:1,u8:32)),u32:0);
  let contexts=[second.context,c];
  let selected=indexed_prepared_ticket(contexts,true,u32:0);
  assert_eq(selected.valid,true);
  assert_eq(selected,indexed_selected_ticket(contexts,u32:0));
  assert_eq(indexed_prepared_ticket(contexts,false,u32:0),zero!<IndexedTicket>());
  let s=SharedState<u32:2,u32:3>{indexed_context:contexts,..zero!<SharedState<u32:2,u32:3>>()};
  assert_eq(indexed_issue(s,s,zero!<mailbox::Admission>(),zero!<IndexedAdmission>(),false,u32:0),s);
  let issued=indexed_issue(s,s,zero!<mailbox::Admission>(),zero!<IndexedAdmission>(),true,u32:0);
  assert_eq(issued.indexed_context[u32:0].consuming,true);
  assert_eq(issued.indexed_context[u32:0].lease,selected.lease);
}
