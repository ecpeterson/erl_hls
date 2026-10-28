// Executable ownership witnesses for the pure gather kernel; these finite tests
// do not establish a transport deadlock bound or a physical RAM implementation.
import indexed_collection_core as core;
import indexed_collection_model as gather;
import indexed_collection_admission_reference as admission_reference;
import indexed_collection_opening_reference as opening_reference;

// A compact full-neighbor fixture exercises all six source-indexed slots.
type State = gather::State<u32:8, u32:6>;

// Return a checked fresh reservation without hiding opening or payload arrival.
fn reserved(key: u32, candidates: u6) -> (State, gather::Lease) {
  let (state, result) = gather::reserve(gather::init<u32:8, u32:6>(u32:10), key, candidates);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  (state, result.lease)
}

// All permutations preserve sparse source order, including a present zero value.
#[test]
fn reordered_sparse_values_test() {
  let orders = [u32[3]:[5, 0, 3], [0, 3, 5], [3, 5, 0], [3, 0, 5], [0, 5, 3], [5, 3, 0]];
  for (order, ()): (u32[3], ()) in orders {
    let (state, lease) = reserved(u32:7, u6:0b101001);
    let state = for (member, current): (u32, State) in order {
      let (next, result) = gather::offer(current, u32:7, member, (member * u32:10) as u8);
      assert_eq(result.outcome, gather::Outcome::ACCEPTED);
      next
    }(state);
    assert_eq(state.metadata.banks[u32:0].status, gather::Status::PROVISIONAL);
    let (waiting, wait) = gather::acquire(state, lease);
    assert_eq(wait.outcome, gather::Outcome::WAIT);
    assert_eq(waiting, state);
    let (state, opened) = gather::open(state, lease, u6:0b101001);
    assert_eq(opened.outcome, gather::Outcome::ACCEPTED);
    assert_eq(state.metadata.banks[u32:0].status, gather::Status::SEALED);
    let (state, borrowed) = gather::acquire(state, lease);
    assert_eq(borrowed.outcome, gather::Outcome::ACCEPTED);
    let (same, view, read) = gather::read(state, lease);
    assert_eq(same, state);
    assert_eq(read.outcome, gather::Outcome::ACCEPTED);
    assert_eq(view.members, u6:0b101001);
    assert_eq(view.values, u8[6]:[0, 0, 0, 30, 0, 50]);
  }(())
}

// Empty membership seals without inventing a payload identity or waiting for mail.
#[test]
fn empty_membership_test() {
  let (state, lease) = reserved(u32:77, u6:0);
  let (state, result) = gather::open(state, lease, u6:0);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  assert_eq(state.metadata.banks[u32:0].status, gather::Status::SEALED);
  let (state, result) = gather::acquire(state, lease);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  let (state, view, result) = gather::read(state, lease);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  assert_eq(view.members, u6:0);
  assert_eq(view.values, zero!<u8[6]>());
  let (state, result) = gather::release(state, lease);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  assert_eq(state.metadata.banks[u32:0].status, gather::Status::FREE);
  assert_eq(state.metadata.banks[u32:0].generation, u32:1);
}

// Five peers can supply both keys before the sixth current member. A borrowed
// current view survives a fully arrived successor, and a third reservation waits.
#[test]
fn skew_and_full_successor_test() {
  let (state, current) = reserved(u32:900, u6:63);
  let (state, future) = gather::reserve(state, u32:17, u6:63);
  assert_eq(future.outcome, gather::Outcome::ACCEPTED);
  let (state, result) = gather::open(state, current, u6:63);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  let state = for (member, state): (u32, State) in u32:0..u32:5 {
    let (state, current_offer) = gather::offer(state, u32:900, member, member as u8);
    let (state, future_offer) = gather::offer(state, u32:17, member, (member + u32:10) as u8);
    assert_eq(current_offer.outcome, gather::Outcome::ACCEPTED);
    assert_eq(future_offer.outcome, gather::Outcome::ACCEPTED);
    state
  }(state);
  assert_eq(state.metadata.banks[u32:0].seen, u6:31);
  assert_eq(state.metadata.banks[u32:1].seen, u6:31);
  let (same, result) = gather::acquire(state, current);
  assert_eq(result.outcome, gather::Outcome::WAIT);
  assert_eq(same, state);
  let (state, _) = gather::offer(state, u32:900, u32:5, u8:5);
  let (state, _) = gather::acquire(state, current);
  let (state, _) = gather::offer(state, u32:17, u32:5, u8:15);
  let (state, _) = gather::open(state, future.lease, u6:63);
  assert_eq(state.metadata.banks[u32:0].status, gather::Status::BORROWED);
  assert_eq(state.metadata.banks[u32:1].status, gather::Status::SEALED);
  let (same, result) = gather::reserve(state, u32:2, u6:1);
  assert_eq(result.outcome, gather::Outcome::WAIT);
  assert_eq(same, state);
  let (state, view, result) = gather::read(state, current);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  assert_eq(view.values, u8[6]:[0, 1, 2, 3, 4, 5]);
  let (state, _) = gather::acquire(state, future.lease);
  let (state, view, _) = gather::read(state, future.lease);
  assert_eq(view.values, u8[6]:[10, 11, 12, 13, 14, 15]);
  let (state, result) = gather::release(state, current);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  let (state, third) = gather::reserve(state, u32:2, u6:1);
  assert_eq(third.outcome, gather::Outcome::ACCEPTED);
  assert_eq(third.lease.bank, current.bank);
  assert_eq(third.lease.generation, current.generation + u32:1);
  let (failed, result) = gather::release(state, current);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::STALE_GENERATION);
  assert_eq(failed.metadata.banks, state.metadata.banks);
}

// Repeated acquisition attempts cannot turn a missing selected member into zero.
#[test]
fn missing_member_waits_test() {
  let (state, lease) = reserved(u32:1, u6:3);
  let (state, _) = gather::open(state, lease, u6:3);
  let (state, _) = gather::offer(state, u32:1, u32:0, u8:42);
  let after = for (_, current): (u32, State) in u32:0..u32:16 {
    let (next, result) = gather::acquire(current, lease);
    assert_eq(result.outcome, gather::Outcome::WAIT);
    next
  }(state);
  assert_eq(after, state);
  assert_eq(after.metadata.banks[u32:0].seen, u6:1);
  assert_eq(after.metadata.failure.code, gather::Fault::NONE);
}

// Duplicate current inputs fail immediately without overwriting or awaiting peers.
#[test]
fn duplicate_open_member_test() {
  let (state, lease) = reserved(u32:8, u6:3);
  let (state, _) = gather::open(state, lease, u6:3);
  let (state, _) = gather::offer(state, u32:8, u32:0, u8:4);
  let (failed, result) = gather::offer(state, u32:8, u32:0, u8:9);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure, gather::Error { code: gather::Fault::DUPLICATE_MEMBER,
    key: u32:8, member: u32:0 });
  assert_eq(failed.metadata.banks, state.metadata.banks);
  let (same, result) = gather::offer(failed, u32:8, u32:1, u8:12);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(same, failed);
}

// A provisional duplicate becomes eligible only on open, despite missing members.
#[test]
fn deferred_duplicate_test() {
  let (state, lease) = reserved(u32:8, u6:3);
  let (state, _) = gather::offer(state, u32:8, u32:0, u8:4);
  let (state, result) = gather::offer(state, u32:8, u32:0, u8:9);
  assert_eq(result.outcome, gather::Outcome::DEFERRED);
  assert_eq(state.metadata.failure.code, gather::Fault::NONE);
  assert_eq(state.metadata.banks[u32:0].deferred.code, gather::Fault::DUPLICATE_MEMBER);
  assert_eq(state.payloads[u32:0][u32:0], u8:4);
  let (same, result) = gather::offer(state, u32:8, u32:1, u8:12);
  assert_eq(result.outcome, gather::Outcome::WAIT);
  assert_eq(same, state);
  let (failed, result) = gather::open(state, lease, u6:3);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::DUPLICATE_MEMBER);
  assert_eq(failed.metadata.banks[u32:0].seen, u6:1);
}

// Final membership validates all earlier values before a later deferred fault.
#[test]
fn membership_capture_test() {
  let (state, lease) = reserved(u32:2, u6:7);
  let (state, _) = gather::offer(state, u32:2, u32:2, u8:22);
  let (state, _) = gather::offer(state, u32:2, u32:1, u8:11);
  let (state, _) = gather::offer(state, u32:2, u32:1, u8:99);
  let (failed, result) = gather::open(state, lease, u6:2);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure, gather::Error { code: gather::Fault::FOREIGN_MEMBER,
    key: u32:2, member: u32:2 });
  assert_eq(failed.metadata.banks, state.metadata.banks);
  let (state, lease) = reserved(u32:2, u6:1);
  let (failed, result) = gather::open(state, lease, u6:3);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::INVALID_MEMBERSHIP);
}

// Foreign and out-of-capacity members cannot clamp into or overwrite a valid slot.
#[test]
fn foreign_and_range_test() {
  let (state, lease) = reserved(u32:2, u6:1);
  let (early, result) = gather::offer(state, u32:2, u32:1, u8:99);
  assert_eq(result.outcome, gather::Outcome::DEFERRED);
  assert_eq(early.metadata.banks[u32:0].seen, u6:0);
  let (failed, _) = gather::open(early, lease, u6:1);
  assert_eq(failed.metadata.failure.code, gather::Fault::FOREIGN_MEMBER);
  let (opened, _) = gather::open(state, lease, u6:1);
  let (failed, result) = gather::offer(opened, u32:2, u32:1, u8:99);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::FOREIGN_MEMBER);
  for (member, ()): (u32, ()) in u32[2]:[6, 0xffffffff] {
    let (early, result) = gather::offer(state, u32:2, member, u8:99);
    assert_eq(result.outcome, gather::Outcome::DEFERRED);
    assert_eq(early.payloads[u32:0], zero!<u8[6]>());
    let (failed, _) = gather::open(early, lease, u6:1);
    assert_eq(failed.metadata.failure.code, gather::Fault::MEMBER_RANGE);
  }(())
}

// A wrong eventual opening fails instead of relabeling retained early values.
#[test]
fn wrong_open_key_test() {
  let (state, lease) = reserved(u32:123, u6:1);
  let (state, _) = gather::offer(state, u32:123, u32:0, u8:42);
  let wrong = gather::Lease { key: u32:124, ..lease };
  let (failed, result) = gather::open(state, wrong, u6:1);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::KEY_MISMATCH);
  assert_eq(failed.metadata.banks, state.metadata.banks);
}

// Branch resolution can withdraw an unused reservation but cannot discard input.
#[test]
fn provisional_invalidation_test() {
  let (state, lease) = reserved(u32:123, u6:1);
  let (empty, result) = gather::invalidate(state, lease);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  assert_eq(empty.metadata.banks[u32:0].status, gather::Status::FREE);
  let (early, _) = gather::offer(state, u32:123, u32:0, u8:42);
  let (failed, result) = gather::invalidate(early, lease);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::KEY_MISMATCH);
  assert_eq(failed.metadata.banks, early.metadata.banks);
  let (early, _) = gather::offer(state, u32:123, u32:6, u8:42);
  let (failed, _) = gather::invalidate(early, lease);
  assert_eq(failed.metadata.failure.code, gather::Fault::KEY_MISMATCH);
}

// Completion alone cannot release a bank; a borrowed view supports repeated reads.
#[test]
fn retirement_and_duplicate_completion_test() {
  let (state, lease) = reserved(u32:2, u6:1);
  let (state, _) = gather::open(state, lease, u6:1);
  let (state, _) = gather::offer(state, u32:2, u32:0, u8:9);
  let (failed, result) = gather::release(state, lease);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::WRONG_STATUS);
  let (failed, result) = gather::offer(state, u32:2, u32:0, u8:10);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::DUPLICATE_MEMBER);
  let (borrowed, _) = gather::acquire(state, lease);
  let (same, first, _) = gather::read(borrowed, lease);
  let (same, second, _) = gather::read(same, lease);
  assert_eq(first, second);
  assert_eq(same, borrowed);
  let (failed, _) = gather::acquire(borrowed, lease);
  assert_eq(failed.metadata.failure.code, gather::Fault::WRONG_STATUS);
  let (released, _) = gather::release(borrowed, lease);
  let (failed, result) = gather::release(released, lease);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::WRONG_STATUS);
}

// Keys compare by equality even across rollover; only explicit reservation allows input.
#[test]
fn rollover_and_unreserved_key_test() {
  let (state, old) = reserved(u32:0xffffffff, u6:1);
  let (state, new) = gather::reserve(state, u32:0, u6:1);
  assert_eq(new.outcome, gather::Outcome::ACCEPTED);
  let (state, _) = gather::open(state, old, u6:1);
  let (state, _) = gather::offer(state, u32:0, u32:0, u8:20);
  let (state, _) = gather::offer(state, u32:0xffffffff, u32:0, u8:10);
  assert_eq(state.payloads[u32:0][u32:0], u8:10);
  assert_eq(state.payloads[u32:1][u32:0], u8:20);
  let (failed, result) = gather::offer(state, u32:1, u32:0, u8:30);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::UNRESERVED_KEY);
  let (failed, result) = gather::reserve(state, u32:0, u6:1);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::DUPLICATE_RESERVATION);
}

// Reset invalidates a borrowed lease even when its key and bank generation recur.
#[test]
fn occupied_reset_test() {
  let (state, old) = reserved(u32:7, u6:1);
  let (state, _) = gather::open(state, old, u6:1);
  let (state, _) = gather::offer(state, u32:7, u32:0, u8:42);
  let (state, _) = gather::acquire(state, old);
  let (state, _) = gather::reserve(state, u32:8, u6:1);
  let (state, _) = gather::offer(state, u32:8, u32:0, u8:43);
  let (reset, result) = gather::reset(state, u32:11);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  assert_eq(reset.metadata, gather::init<u32:8, u32:6>(u32:11).metadata);
  assert_eq(reset.payloads, state.payloads);
  let (new, result) = gather::reserve(reset, u32:7, u6:1);
  assert_eq(result.lease.generation, old.generation);
  assert_eq(result.lease.bank, old.bank);
  let (failed, result) = gather::release(new, old);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::STALE_GENERATION);
  assert_eq(failed.metadata.banks, new.metadata.banks);
  let (failed, result) = gather::reset(reset, u32:11);
  assert_eq(result.outcome, gather::Outcome::FAILED);
  assert_eq(failed.metadata.failure.code, gather::Fault::RESET_EPOCH_REUSED);
  let (cleared, result) = gather::reset(failed, u32:12);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  assert_eq(cleared.metadata.failure.code, gather::Fault::NONE);
}

// Generation wrapping does not stop service; the owner bounds stale ticket age.
#[test]
fn generation_wrap_test() {
  let state = gather::init<u32:8, u32:6>(u32:10);
  let exhausted = core::Bank<u32:6> { generation: u32:0xffffffff,
    ..state.metadata.banks[u32:0] };
  let state = State { metadata: core::State<u32:6> {
    banks: update(state.metadata.banks, u32:0, exhausted), ..state.metadata }, ..state };
  let (next, result) = gather::reserve(state, u32:7, u6:1);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  assert_eq(result.lease.generation, u32:0);
  assert_eq(next.metadata.banks[u32:0].generation, u32:0);
}

// Capacity and scalar width are independent parameters, including wide values.
#[test]
fn parameterized_payload_test() {
  let state = gather::init<u32:46, u32:3>(u32:1);
  let (state, reserved) = gather::reserve(state, u32:0, u3:4);
  let (state, _) = gather::open(state, reserved.lease, u3:4);
  let (state, _) = gather::offer(state, u32:0, u32:2, u46:0x123456789abc);
  let (state, _) = gather::acquire(state, reserved.lease);
  let (_, view, result) = gather::read(state, reserved.lease);
  assert_eq(result.outcome, gather::Outcome::ACCEPTED);
  assert_eq(view.members, u3:4);
  assert_eq(view.values, u46[3]:[0, 0, 0x123456789abc]);
}

// Physical adapters receive one payload-free write intent only for accepted input.
#[test]
fn metadata_intents_test() {
  let state = core::init<u32:3>(u32:1);
  let (state, reserved) = core::reserve(state, u32:7, u3:4);
  assert_eq(reserved.write.valid, false);
  let (state, accepted) = core::offer(state, u32:7, u32:2);
  assert_eq(accepted.write, core::WriteIntent { valid: true, bank: u1:0, member: u32:2 });
  let (state, _) = core::open(state, reserved.lease, u3:4);
  let (failed, intent, result) = core::read(state, reserved.lease);
  assert_eq(result.outcome, core::Outcome::FAILED);
  assert_eq(intent.valid, false);
  assert_eq(failed.failure.code, core::Fault::WRONG_STATUS);
  let (state, _) = core::acquire(state, reserved.lease);
  let (_, intent, result) = core::read(state, reserved.lease);
  assert_eq(result.write.valid, false);
  assert_eq(intent, core::ReadIntent<u32:3> { valid: true, lease: reserved.lease, members: u3:4 });
  let (_, result) = core::offer(state, u32:7, u32:2);
  assert_eq(result.outcome, core::Outcome::FAILED);
  assert_eq(result.write.valid, false);
}

// Reuse deliberately leaves old memory words, but a new sparse view hides them.
#[test]
fn reused_payload_is_not_presence_test() {
  let (state, old) = reserved(u32:7, u6:1);
  let (state, _) = gather::open(state, old, u6:1);
  let (state, _) = gather::offer(state, u32:7, u32:0, u8:99);
  let (state, _) = gather::acquire(state, old);
  let (state, _) = gather::release(state, old);
  let (state, new) = gather::reserve(state, u32:8, u6:2);
  let (state, _) = gather::open(state, new.lease, u6:2);
  let (state, _) = gather::offer(state, u32:8, u32:1, u8:0);
  let (state, _) = gather::acquire(state, new.lease);
  assert_eq(state.payloads[u32:0][u32:0], u8:99);
  let (_, view, _) = gather::read(state, new.lease);
  assert_eq(view.members, u6:2);
  assert_eq(view.values, zero!<u8[6]>());
}


// Compare full states and results against frozen bodies, including both factored standalone operations.
fn assert_admission_equivalence(state: core::State<u32:2>, candidates: u2, member: u32) {
  assert_eq(core::reserve(state, u32:7, candidates),
    admission_reference::reserve(state, u32:7, candidates));
  assert_eq(core::offer(state, u32:7, member),
    admission_reference::offer(state, u32:7, member));
  assert_eq(core::reserve_and_offer(state, u32:7, candidates, member),
    admission_reference::reserve_and_offer(state, u32:7, candidates, member));
}

// Nonzero dormant diagnostics expose accidental changes to otherwise unused metadata.
fn admission_grid_bank(status: core::Status, key: u32, generation: u32) -> core::Bank<u32:2> {
  core::Bank<u32:2> { status, key, generation, candidates:u2:1, members:u2:2, seen:u2:1,
    deferred:core::Error { code:core::Fault::NONE, key:key + u32:13, member:u32:19 } }
}

// Exhaust all 5x5 bank statuses, four key relations, sticky/clear failure and wrap/nonwrap
// generations, with four member classes: 1,600 comparisons per operation at capacity two.
#[test]
fn reserve_offer_topology_grid_test() {
  let statuses = [core::Status::FREE, core::Status::PROVISIONAL, core::Status::OPEN,
                  core::Status::SEALED, core::Status::BORROWED];
  for (i, ()): (u32, ()) in u32:0..u32:400 {
    let keys = (i / u32:25) % u32:4;
    let generation = if i >= u32:200 { u32:0xffffffff } else { u32:31 };
    let state = core::State<u32:2> {
      banks:[admission_grid_bank(statuses[i % u32:5],
               if (keys & u32:1) != u32:0 { u32:7 } else { u32:17 }, generation),
             admission_grid_bank(statuses[(i / u32:5) % u32:5],
               if (keys & u32:2) != u32:0 { u32:7 } else { u32:23 }, generation)],
      reset_epoch:u32:41,
      failure:core::Error { code:if ((i / u32:100) & u32:1) != u32:0 {
        core::Fault::WRONG_STATUS } else { core::Fault::NONE }, key:u32:0x12345678, member:u32:0x87654321 } };
    for (member, ()): (u32, ()) in u32[4]:[0, 1, 2, 0xffffffff] {
      assert_admission_equivalence(state, keys as u2, member)
    }(())
  }(())
}

// Exhaust 5 statuses, every two-bit candidate/member/seen mask, deferred/clear faults
// and four member classes: 2,560 comparisons per operation, including fault precedence.
#[test]
fn reserve_offer_membership_grid_test() {
  let statuses = [core::Status::FREE, core::Status::PROVISIONAL, core::Status::OPEN,
                  core::Status::SEALED, core::Status::BORROWED];
  let members = u32[4]:[0, 1, 2, 0xffffffff];
  for (i, ()): (u32, ()) in u32:0..u32:2560 {
    let selected = core::Bank<u32:2> { status:statuses[i % u32:5], key:u32:7, generation:u32:43,
      candidates:((i / u32:5) % u32:4) as u2,
      members:((i / u32:20) % u32:4) as u2,
      seen:((i / u32:80) % u32:4) as u2,
      deferred:core::Error { code:if ((i / u32:320) % u32:2) != u32:0 {
        core::Fault::DUPLICATE_MEMBER } else { core::Fault::NONE }, key:u32:47, member:u32:53 } };
    let state = core::State<u32:2> {
      banks:[selected, admission_grid_bank(core::Status::BORROWED, u32:29, u32:59)],
      reset_epoch:u32:61,
      failure:core::Error { code:core::Fault::NONE, key:u32:67, member:u32:71 } };
    assert_admission_equivalence(state, u2:2, members[i / u32:640])
  }(())
}


// Compare every field, including dormant diagnostics and ignored success-result fields.
fn assert_opening_equivalence(state: core::State<u32:2>, lease: core::Lease, members: u2) {
  assert_eq(core::open(state, lease, members), opening_reference::open(state, lease, members));
}

// 2,560 complete comparisons: both slots, all five statuses, every candidate/seen/final
// two-bit mask, deferred fault/clear and sticky fault/clear. Prior membership is dormant.
#[test]
fn scalar_open_membership_grid_test() {
  let statuses = [core::Status::FREE, core::Status::PROVISIONAL, core::Status::OPEN,
    core::Status::SEALED, core::Status::BORROWED];
  for (i, ()): (u32, ()) in u32:0..u32:2560 {
    let slot = i % u32:2;
    let bank = core::Bank<u32:2> { status:statuses[(i / u32:2) % u32:5], key:u32:7,
      generation:u32:43, candidates:((i / u32:10) % u32:4) as u2, members:u2:2,
      seen:((i / u32:40) % u32:4) as u2,
      deferred:core::Error { code:if ((i / u32:640) % u32:2) != u32:0 {
        core::Fault::DUPLICATE_MEMBER } else { core::Fault::NONE }, key:u32:47, member:u32:53 } };
    let other = admission_grid_bank(core::Status::BORROWED, u32:29, u32:59);
    let state = core::State<u32:2> { banks:update([other, other], slot, bank), reset_epoch:u32:61,
      failure:core::Error { code:if i >= u32:1280 { core::Fault::WRONG_STATUS }
        else { core::Fault::NONE }, key:u32:67, member:u32:71 } };
    let lease = core::Lease { bank:slot as u1, key:u32:7, generation:u32:43, reset_epoch:u32:61 };
    assert_opening_equivalence(state, lease, ((i / u32:160) % u32:4) as u2)
  }(())
}

// 320 complete comparisons: both slots/statuses, every combination of wrong key,
// generation and reset epoch, sticky/clear failure, and normal/max generation.
#[test]
fn scalar_open_lease_grid_test() {
  let statuses = [core::Status::FREE, core::Status::PROVISIONAL, core::Status::OPEN,
    core::Status::SEALED, core::Status::BORROWED];
  for (i, ()): (u32, ()) in u32:0..u32:320 {
    let slot = i % u32:2;
    let errors = (i / u32:10) % u32:8;
    let generation = if i >= u32:160 { !u32:0 } else { u32:43 };
    let bank = admission_grid_bank(statuses[(i / u32:2) % u32:5], u32:7, generation);
    let other = admission_grid_bank(core::Status::PROVISIONAL, u32:29, u32:59);
    let state = core::State<u32:2> { banks:update([other, other], slot, bank), reset_epoch:!u32:0,
      failure:core::Error { code:if ((i / u32:80) % u32:2) != u32:0 { core::Fault::FOREIGN_MEMBER }
        else { core::Fault::NONE }, key:u32:67, member:u32:71 } };
    let lease = core::Lease { bank:slot as u1,
      key:if (errors & u32:1) != u32:0 { u32:8 } else { u32:7 },
      generation:generation + if (errors & u32:2) != u32:0 { u32:1 } else { u32:0 },
      reset_epoch:if (errors & u32:4) != u32:0 { u32:0 } else { !u32:0 } };
    assert_opening_equivalence(state, lease, u2:3)
  }(())
}

// 1,600 complete comparisons: every pair of statuses, both/neither/one key match,
// sticky/clear failure, normal/wrapping generation and all four allow masks.
#[test]
fn reserve_open_topology_grid_test() {
  let statuses = [core::Status::FREE, core::Status::PROVISIONAL, core::Status::OPEN,
    core::Status::SEALED, core::Status::BORROWED];
  for (i, ()): (u32, ()) in u32:0..u32:1600 {
    let keys = (i / u32:25) % u32:4;
    let generation = if ((i / u32:200) % u32:2) != u32:0 { !u32:0 } else { u32:31 };
    let state = core::State<u32:2> {
      banks:[admission_grid_bank(statuses[i % u32:5],
        if (keys & u32:1) != u32:0 { u32:7 } else { u32:17 }, generation),
        admission_grid_bank(statuses[(i / u32:5) % u32:5],
        if (keys & u32:2) != u32:0 { u32:7 } else { u32:23 }, generation)],
      reset_epoch:u32:41, failure:core::Error { code:if ((i / u32:100) % u32:2) != u32:0 {
        core::Fault::WRONG_STATUS } else { core::Fault::NONE }, key:u32:67, member:u32:71 } };
    let flags = i / u32:400;
    let allow = [(flags & u32:1) != u32:0, (flags & u32:2) != u32:0];
    assert_eq(core::reserve_and_maybe_open(state, u32:7, keys as u2, u2:3, allow),
      opening_reference::reserve_and_maybe_open(state, u32:7, keys as u2, u2:3, allow))
  }(())
}

// 1,024 complete comparisons: both existing provisional banks, all candidate/seen/final
// masks, deferred/sticky error presence and opposite per-bank opening permissions.
#[test]
fn reserve_open_membership_grid_test() {
  for (i, ()): (u32, ()) in u32:0..u32:1024 {
    let slot = i % u32:2;
    let bank = core::Bank<u32:2> { status:core::Status::PROVISIONAL, key:u32:7, generation:u32:43,
      candidates:((i / u32:2) % u32:4) as u2, members:u2:2, seen:((i / u32:8) % u32:4) as u2,
      deferred:core::Error { code:if ((i / u32:128) % u32:2) != u32:0 {
        core::Fault::DUPLICATE_MEMBER } else { core::Fault::NONE }, key:u32:47, member:u32:53 } };
    let other = admission_grid_bank(core::Status::BORROWED, u32:29, u32:59);
    let state = core::State<u32:2> { banks:update([other, other], slot, bank), reset_epoch:u32:61,
      failure:core::Error { code:if ((i / u32:256) % u32:2) != u32:0 {
        core::Fault::WRONG_STATUS } else { core::Fault::NONE }, key:u32:67, member:u32:71 } };
    let enabled = i >= u32:512;
    let allow = update([!enabled, !enabled], slot, enabled);
    let members = ((i / u32:32) % u32:4) as u2;
    let actual = core::reserve_and_maybe_open(state, u32:7, u2:0, members, allow);
    assert_eq(actual, opening_reference::reserve_and_maybe_open(state, u32:7, u2:0, members, allow));
    assert_eq(actual.1.outcome, core::Outcome::ACCEPTED);
    assert_eq(actual.0.banks[u32:1 - slot], other)
  }(())
}

// Eight new reservations: either slot, normal/wrapped generation, enabled/disabled
// invalid-membership opening. ACCEPTED names reservation even when opening fails.
#[test]
fn reserve_open_keeps_failed_new_reservation_test() {
  for (i, ()): (u32, ()) in u32:0..u32:8 {
    let slot = i % u32:2;
    let generation = if ((i / u32:2) % u32:2) != u32:0 { !u32:0 } else { u32:31 };
    let bank = admission_grid_bank(core::Status::FREE, u32:7, generation);
    let other = admission_grid_bank(core::Status::SEALED, u32:29, u32:59);
    let state = core::State<u32:2> { banks:update([other, other], slot, bank), reset_epoch:u32:61,
      failure:core::Error { code:core::Fault::NONE, key:u32:67, member:u32:71 } };
    let enabled = i >= u32:4;
    let allow = update([!enabled, !enabled], slot, enabled);
    let actual = core::reserve_and_maybe_open(state, u32:9, u2:1, u2:3, allow);
    assert_eq(actual, opening_reference::reserve_and_maybe_open(state, u32:9, u2:1, u2:3, allow));
    assert_eq(actual.1.outcome, core::Outcome::ACCEPTED);
    assert_eq(actual.1.lease, core::Lease { bank:slot as u1, key:u32:9,
      generation:generation + u32:1, reset_epoch:u32:61 });
    assert_eq(actual.0.banks[slot], core::Bank<u32:2> { status:core::Status::PROVISIONAL,
      key:u32:9, generation:generation + u32:1, candidates:u2:1, ..zero!<core::Bank<u32:2>>() });
    assert_eq(actual.0.failure, if enabled {
      core::Error { code:core::Fault::INVALID_MEMBERSHIP, key:u32:9, member:u32:1 }
    } else { state.failure })
  }(())
}


// 176 complete comparisons at capacity two: both SEALED bank positions, every
// key/generation/reset mismatch combination and all eleven sticky fault codes.
// Explicit expected results check identity precedence even though both APIs share a transition.
#[test]
fn sealed_acquire_checked_equivalence_test() {
  let faults = [core::Fault::NONE, core::Fault::UNRESERVED_KEY, core::Fault::MEMBER_RANGE,
    core::Fault::FOREIGN_MEMBER, core::Fault::DUPLICATE_MEMBER, core::Fault::KEY_MISMATCH,
    core::Fault::STALE_GENERATION, core::Fault::WRONG_STATUS, core::Fault::DUPLICATE_RESERVATION,
    core::Fault::INVALID_MEMBERSHIP, core::Fault::RESET_EPOCH_REUSED];
  for (i, ()): (u32, ()) in u32:0..u32:176 {
    let slot = i % u32:2;
    let errors = (i / u32:2) % u32:8;
    let sticky = faults[i / u32:16];
    let generation = if slot == u32:0 { u32:0 } else { !u32:0 };
    let bank = core::Bank<u32:2> { members:u2:1,
      ..admission_grid_bank(core::Status::SEALED, u32:7, generation) };
    let other = admission_grid_bank(core::Status::BORROWED, u32:29, u32:59);
    let state = core::State<u32:2> { banks:update([other, other], slot, bank), reset_epoch:!u32:0,
      failure:core::Error { code:sticky, key:u32:67, member:u32:71 } };
    let lease = core::Lease { bank:slot as u1,
      key:if (errors & u32:1) != u32:0 { u32:8 } else { u32:7 },
      generation:generation + if (errors & u32:2) != u32:0 { u32:1 } else { u32:0 },
      reset_epoch:if (errors & u32:4) != u32:0 { u32:0 } else { !u32:0 } };
    let actual = core::acquire_sealed(state, lease);
    assert_eq(actual, core::acquire(state, lease));
    let accepted = sticky == core::Fault::NONE && errors == u32:0;
    let expected_failure = if sticky != core::Fault::NONE || errors == u32:0 { state.failure }
      else { core::Error {
        code:if (errors & u32:6) != u32:0 { core::Fault::STALE_GENERATION }
          else { core::Fault::KEY_MISMATCH }, key:lease.key, member:u32:0 } };
    let expected_state = core::State<u32:2> { failure:expected_failure,
      banks:if accepted { update(state.banks, slot,
        core::Bank<u32:2> { status:core::Status::BORROWED, ..bank }) } else { state.banks }, ..state };
    let expected_result = if accepted {
      core::Result { outcome:core::Outcome::ACCEPTED, lease, ..zero!<core::Result>() }
    } else { core::Result { outcome:core::Outcome::FAILED, ..zero!<core::Result>() } };
    assert_eq(actual, (expected_state, expected_result));
    ()
  }(())
}
