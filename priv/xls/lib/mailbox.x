// Shared-scheduler mailbox storage primitives.
//
// The scheduler owns queue metadata; these pure helpers select and update it.
// Frame payloads live in external RAM at stable, slot-major addresses.
// DEPTH is the actor mailbox capacity (1..255), matching u8 counts and indices.
// Actor and producer arrays are nonempty.

import axis;
import bram;

pub struct Slot {
  postponed: u1,
  frame: axis::Frame,
}

pub struct ScheduledRequest {
  slot: u32,
  frame: axis::Frame,
  credit: u1,
}

pub struct Admission {
  valid: u1,
  producer: u32,
  slot: u32,
  physical: u8,
}

pub type RamReadReq = bram::ReadReq;
pub type RamReadResp = bram::ReadResp<axis::FRAME_BITS>;
pub type RamWriteReq = bram::WriteReq<axis::FRAME_BITS>;
pub type RamWriteResp = bram::WriteResp;

pub fn address(slot: u32, index: u8, capacity: u32) -> u32 {
  slot * capacity + index as u32
}

pub fn read(slot: u32, index: u8, capacity: u32) -> RamReadReq {
  bram::read(address(slot, index, capacity))
}

pub fn write(
    slot: u32, index: u8, capacity: u32, frame: axis::Frame)
    -> RamWriteReq {
  bram::write(address(slot, index, capacity), axis::bits_from_frame(frame))
}

// Selectors return zero indices when no candidate exists; callers must use
// the valid flag (or establish spare capacity before calling free_index).
// All order entries are below DEPTH; occupied prefixes are also distinct.
fn free_index<DEPTH: u32>(order: u8[DEPTH], occupied: u8) -> u8 {
  let (_found, selected) = unroll_for! (candidate, acc):
      (u32, (u1, u8)) in
      u32:0..DEPTH {
    let used = unroll_for! (position, found):
        (u32, u1) in u32:0..DEPTH {
      found || (
        position < occupied as u32 &&
        order[position] == candidate as u8)
    }(u1:0);
    let take = !acc.0 && !used;
    (
      acc.0 || take,
      if take { candidate as u8 } else { acc.1 }
    )
  }((u1:0, u8:0));
  selected
}

// Return (valid, logical queue position, physical RAM index), skipping
// postponed messages without changing their order or releasing their slots.
pub fn select<DEPTH: u32>(
    order: u8[DEPTH], occupied: u8, postponed: u1[DEPTH]) -> (u1, u8, u8) {
  unroll_for! (position, acc):
      (u32, (u1, u8, u8)) in
      u32:0..DEPTH {
    let physical = order[position];
    let take = !acc.0 &&
      position < occupied as u32 &&
      !postponed[physical as u32];
    (
      acc.0 || take,
      if take { position as u8 } else { acc.1 },
      if take { physical } else { acc.2 }
    )
  }((u1:0, u8:0, u8:0))
}

// Remove one consumed logical position; the remaining physical indices keep
// their order. The caller decrements occupied and owns postponement resets.
pub fn compact_order<DEPTH: u32>(
    row: u8[DEPTH],
    selected: u8,
    occupied: u8) -> u8[DEPTH] {
  unroll_for! (position, result):
      (u32, u8[DEPTH]) in
      u32:0..DEPTH {
    let value = if position < selected as u32 {
      row[position]
    } else if position + u32:1 < occupied as u32 {
      row[position + u32:1]
    } else {
      u8:0
    };
    update(result, position, value)
  }(zero!<u8[DEPTH]>())
}

// Returned batch credits represent completed effect batches, so they
// update scheduler metadata without carrying another actor context.
pub fn collect_credit<PRODUCER_COUNT: u32>(
    pending: ScheduledRequest[PRODUCER_COUNT],
    pending_valid: u1[PRODUCER_COUNT],
    egress_busy: u1) -> (u1[PRODUCER_COUNT], u1) {
  let (credit_found, credit_producer) =
    unroll_for! (candidate, acc):
        (u32, (u1, u32)) in u32:0..PRODUCER_COUNT {
      let take = !acc.0 && pending_valid[candidate] &&
        pending[candidate].credit;
      (acc.0 || take, if take { candidate } else { acc.1 })
    }((u1:0, u32:0));
  let remaining = if credit_found {
    update(pending_valid, credit_producer, u1:0)
  } else {
    pending_valid
  };
  (remaining, egress_busy && !credit_found)
}

pub struct AdmissionResult<ACTOR_COUNT: u32, PRODUCER_COUNT: u32, DEPTH: u32> {
  pending_valid: u1[PRODUCER_COUNT],
  occupied: u8[ACTOR_COUNT],
  order: u8[DEPTH][ACTOR_COUNT],
  mail_candidates: u1[ACTOR_COUNT],
  admission: Admission,
  cursor: u32,
}

// Reserve at most one eligible producer, starting at cursor and wrapping.
// Inputs include any retired activation's updates. Exclude the actor being
// issued and a just-failed actor; other destinations can still be admitted.
// A rejected request stays pending and leaves metadata and cursor unchanged.
pub fn reserve_admission<ACTOR_COUNT: u32, PRODUCER_COUNT: u32, DEPTH: u32>(
    occupied: u8[ACTOR_COUNT],
    order: u8[DEPTH][ACTOR_COUNT],
    mail_candidates: u1[ACTOR_COUNT],
    cursor: u32,
    pending: ScheduledRequest[PRODUCER_COUNT],
    pending_valid: u1[PRODUCER_COUNT],
    excluded_valid: u1,
    excluded_slot: u32,
    failed_valid: u1,
    failed_slot: u32) ->
    AdmissionResult<ACTOR_COUNT, PRODUCER_COUNT, DEPTH> {
  let (after_found, after_producer, before_found, before_producer) =
      unroll_for! (candidate, acc):
          (u32, (u1, u32, u1, u32)) in u32:0..PRODUCER_COUNT {
    let request = pending[candidate];
    let slot = request.slot;
    // Boolean operators are eager in DSLX; guard the array access itself.
    let has_capacity = if slot < ACTOR_COUNT {
      occupied[slot] as u32 < DEPTH
    } else {
      false
    };
    let eligible = pending_valid[candidate] && !request.credit &&
      has_capacity &&
      (!excluded_valid || slot != excluded_slot) &&
      (!failed_valid || slot != failed_slot);
    let take_after = !acc.0 &&
      candidate >= cursor && eligible;
    let take_before = !acc.2 &&
      candidate < cursor && eligible;
    (
      acc.0 || take_after,
      if take_after { candidate } else { acc.1 },
      acc.2 || take_before,
      if take_before { candidate } else { acc.3 }
    )
  }((u1:0, u32:0, u1:0, u32:0));
  let found = after_found || before_found;
  let producer = if after_found {
    after_producer
  } else {
    before_producer
  };
  let request = pending[producer];
  let slot = if request.slot < ACTOR_COUNT {
    request.slot
  } else {
    u32:0
  };
  let physical = free_index(order[slot], occupied[slot]);
  let old_count = occupied[slot];
  let occupied = if found {
    update(occupied, slot, old_count + u8:1)
  } else {
    occupied
  };
  let order = if found {
    let row = update(order[slot], old_count as u32, physical);
    update(order, slot, row)
  } else {
    order
  };
  let mail_candidates = if found {
    update(mail_candidates, slot, u1:1)
  } else {
    mail_candidates
  };
  let remaining = if found {
    update(pending_valid, producer, u1:0)
  } else {
    pending_valid
  };
  let cursor = if found {
    if producer + u32:1 == PRODUCER_COUNT {
      u32:0
    } else {
      producer + u32:1
    }
  } else {
    cursor
  };
  AdmissionResult<ACTOR_COUNT, PRODUCER_COUNT, DEPTH> {
    pending_valid: remaining,
    occupied,
    order,
    mail_candidates,
    admission: Admission {
      valid: found,
      producer,
      slot,
      physical,
    },
    cursor,
  }
}

#[test]
fn rows_are_slot_major_and_hold_one_frame_test() {
  let frame = axis::pack(u8:13, u32:0x12345678);
  assert_eq(address(u32:3, u8:2, u32:5), u32:17);
  assert_eq(read(u32:3, u8:2, u32:5), bram::read(u32:17));
  assert_eq(
    write(u32:3, u8:2, u32:5, frame),
    bram::write(u32:17, axis::bits_from_frame(frame)));
}

#[test]
fn selection_preserves_queue_order_across_postponement_test() {
  let order = [u8:2, u8:0, u8:3, u8:1];
  assert_eq(select(order, u8:3, [false, false, false, false]),
            (true, u8:0, u8:2));
  assert_eq(select(order, u8:3, [false, false, true, false]),
            (true, u8:1, u8:0));
  assert_eq(select(order, u8:3, [true, false, true, false]),
            (true, u8:2, u8:3));
  // Physical slot one is unpostponed but outside the occupied prefix.
  assert_eq(select(order, u8:3, [true, false, true, true]),
            (false, u8:0, u8:0));
  assert_eq(select(order, u8:0, [false, false, false, false]),
            (false, u8:0, u8:0));
  // A phase boundary clears postponement and replays the oldest message.
  assert_eq(select(order, u8:3, zero!<bool[4]>()),
            (true, u8:0, u8:2));
}

#[test]
fn consumption_reuses_physical_storage_at_queue_tail_test() {
  let order = [u8:2, u8:0, u8:3, u8:1];
  assert_eq(compact_order(order, u8:0, u8:4), [u8:0, u8:3, u8:1, u8:0]);
  assert_eq(compact_order(order, u8:3, u8:4), [u8:2, u8:0, u8:3, u8:0]);
  let compacted = compact_order(order, u8:1, u8:4);
  assert_eq(compacted, [u8:2, u8:3, u8:1, u8:0]);
  let request = ScheduledRequest { slot: u32:0, ..zero!<ScheduledRequest>() };
  let admitted = reserve_admission(
    [u8:3], [compacted], [true], u32:0, [request], [true],
    false, u32:0, false, u32:0);
  assert_eq(admitted.admission,
            Admission { valid: true, producer: u32:0, slot: u32:0, physical: u8:0 });
  assert_eq(admitted.occupied, [u8:4]);
  assert_eq(admitted.order, [[u8:2, u8:3, u8:1, u8:0]]);
  assert_eq(admitted.pending_valid, [false]);
  assert_eq(admitted.cursor, u32:0);
}

#[test]
fn admission_skips_full_excluded_failed_invalid_and_credit_requests_test() {
  let message = zero!<ScheduledRequest>();
  let pending = [
    ScheduledRequest { slot: u32:0, ..message },
    ScheduledRequest { slot: u32:1, ..message },
    ScheduledRequest { slot: u32:2, ..message },
    ScheduledRequest { slot: u32:99, ..message },
    ScheduledRequest { slot: u32:3, credit: true, ..message },
    ScheduledRequest { slot: u32:3, ..message },
  ];
  let occupied = [u8:2, u8:1, u8:0, u8:0];
  let order = [[u8:1, u8:0], [u8:0, u8:0], [u8:0, u8:0], [u8:0, u8:0]];
  let candidates = [true, true, false, false];
  let admitted = reserve_admission(
    occupied, order, candidates, u32:1, pending, [true, true, true, true, true, true],
    true, u32:1, true, u32:2);
  assert_eq(admitted.admission,
            Admission { valid: true, producer: u32:5, slot: u32:3, physical: u8:0 });
  assert_eq(admitted.occupied, [u8:2, u8:1, u8:0, u8:1]);
  assert_eq(admitted.order, order);
  assert_eq(admitted.mail_candidates, [true, true, false, true]);
  assert_eq(admitted.pending_valid, [true, true, true, true, true, false]);
  assert_eq(admitted.cursor, u32:0);
  // With the only admissible producer absent, even invalid pending addresses
  // must leave every piece of queue metadata untouched.
  let rejected = reserve_admission(
    occupied, order, candidates, u32:1, pending, admitted.pending_valid,
    true, u32:1, true, u32:2);
  assert_eq(rejected.admission.valid, false);
  assert_eq(rejected.occupied, occupied);
  assert_eq(rejected.order, order);
  assert_eq(rejected.mail_candidates, candidates);
  assert_eq(rejected.pending_valid, admitted.pending_valid);
  assert_eq(rejected.cursor, u32:1);
}

#[test]
fn admission_round_robins_and_waits_for_single_slot_retirement_test() {
  let request = zero!<ScheduledRequest>();
  let pending = [request, request, request];
  let first = reserve_admission(
    [u8:0], [[u8:0]], [false], u32:2, pending, [true, true, true],
    false, u32:0, false, u32:0);
  assert_eq(first.admission.producer, u32:2);
  assert_eq(first.cursor, u32:0);
  assert_eq(first.occupied, [u8:1]);
  assert_eq(first.mail_candidates, [true]);
  let full = reserve_admission(
    first.occupied, first.order, first.mail_candidates, first.cursor,
    pending, first.pending_valid, false, u32:0, false, u32:0);
  assert_eq(full.admission.valid, false);
  assert_eq(full.pending_valid, [true, true, false]);
  assert_eq(full.occupied, first.occupied);
  assert_eq(full.order, first.order);
  assert_eq(full.mail_candidates, first.mail_candidates);
  assert_eq(full.cursor, first.cursor);
  let retired = compact_order(first.order[u32:0], u8:0, u8:1);
  let next = reserve_admission(
    [u8:0], [retired], [false], full.cursor, pending, full.pending_valid,
    false, u32:0, false, u32:0);
  assert_eq(next.admission.valid, true);
  assert_eq(next.admission.producer, u32:0);
  assert_eq(next.cursor, u32:1);
  assert_eq(next.pending_valid, [false, true, false]);
  // Search wraps as well as the cursor: only a producer before cursor is ready.
  let wrapped = reserve_admission(
    [u8:0], [[u8:0]], [false], u32:1, pending, [true, false, false],
    false, u32:0, false, u32:0);
  assert_eq(wrapped.admission.valid, true);
  assert_eq(wrapped.admission.producer, u32:0);
  assert_eq(wrapped.cursor, u32:1);
}

#[test]
fn credit_collection_releases_one_batch_without_consuming_messages_test() {
  let request = zero!<ScheduledRequest>();
  let credit = ScheduledRequest { credit: true, ..request };
  let pending = [credit, request, credit];
  assert_eq(collect_credit(pending, [false, true, false], true),
            ([false, true, false], true));
  let (remaining, busy) = collect_credit(pending, [true, true, true], true);
  assert_eq((remaining, busy), ([false, true, true], false));
  assert_eq(collect_credit(pending, remaining, busy),
            ([false, true, false], false));
}
