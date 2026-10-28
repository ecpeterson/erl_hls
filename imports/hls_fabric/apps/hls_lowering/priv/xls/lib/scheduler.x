// Shared actor scheduling policy, independent of actor records and callbacks.

import arbitration;
import std;

// Release a transferred value while retaining any replacement captured at the
// same edge. `pending` already includes that capture. The payload owner decides
// whether a replacement is valid work or a retained protocol-failure value.
pub fn release_pending<COUNT: u32>(pending: u1[COUNT], issued: bool, slot: u32,
    captured: bool, captured_slot: u32) -> u1[COUNT] {
  if issued { update(pending, slot, captured && captured_slot == slot) }
  else { pending }
}

// Capture/transfer on one row must preserve the new value and other rows.
#[test]
fn release_keeps_simultaneous_replacement_test() {
  assert_eq(release_pending([true, true], true, u32:0, true, u32:0), [true, true]);
  assert_eq(release_pending([true, true], true, u32:0, true, u32:1), [false, true]);
  assert_eq(release_pending([true, false], true, u32:0, false, u32:0), [false, false]);
  assert_eq(release_pending([true, false], false, u32:0, false, u32:0), [true, false]);
}

// Advance only after acceptance; blocked/stalled work retains the old cursor.
// COUNT is positive, INDEX_BITS represents every actor, and selected < COUNT
// when accepted. BOOT passes its current cursor; RUN passes the arbiter's index.
pub fn advance_cursor<COUNT: u32, INDEX_BITS: u32>(
    cursor: uN[INDEX_BITS], accepted: bool, selected: u32) -> uN[INDEX_BITS] {
  if accepted { arbitration::successor<COUNT>(selected as uN[INDEX_BITS]) }
  else { cursor }
}

// Per-actor ready flags for entry, mailbox, egress and private reduction work.
pub struct Candidates<COUNT: u32> {
  entry: u1[COUNT],
  mail: u1[COUNT],
  egress: u1[COUNT],
  internal: u1[COUNT],
  aggregate: u1[COUNT],
}

// Reserve a whole effect batch before issue: an actor is unavailable while
// executing or while its previous batch occupies its independent outbox.
// A callback that produces no effects releases its reservation at retirement.
pub fn exclude_reserved<COUNT: u32>(
    in_flight: u1[COUNT], outbox_busy: u1[COUNT]) -> u1[COUNT] {
  unroll_for! (slot, result): (u32, u1[COUNT]) in u32:0..COUNT {
    update(result, slot, in_flight[slot] || outbox_busy[slot])
  }(zero!<u1[COUNT]>())
}

// Private reduction work can run while egress is busy. Within each actor,
// entry/egress work suppresses mailbox dispatch; in-flight actors stay excluded.
// The round-robin choice is across eligible actors, not across work categories.
// Return (valid, actor), with (false, 0) when none can run. COUNT must be positive;
// the caller advances cursor only after accepting the selected activation.
pub fn select<COUNT: u32>(
    candidates: Candidates<COUNT>, egress_busy: u1,
    in_flight: u1[COUNT], cursor: u32) -> (u1, u32) {
  let eligible = unroll_for! (slot, result):
      (u32, u1[COUNT]) in u32:0..COUNT {
    let private_active = candidates.internal[slot] || candidates.aggregate[slot];
    let entry_active = private_active || candidates.entry[slot] || candidates.egress[slot];
    let ready = private_active || (!private_active && (
      candidates.entry[slot] ||
      (candidates.mail[slot] && !entry_active) ||
      (candidates.egress[slot] && !egress_busy)));
    let selectable = ready && !in_flight[slot]; // Paired with ready for profiling.
    update(result, slot, selectable)
  }(zero!<u1[COUNT]>());
  arbitration::select(eligible, cursor)
}

// An actor awaiting egress credit cannot overtake its effect with mailbox work.
#[test]
fn egress_waiters_suppress_mail_until_credit_returns_test() {
  let candidates = Candidates<u32:3> {
    mail: [true, true, true],
    egress: [true, false, true],
    ..zero!<Candidates<u32:3>>()
  };
  assert_eq(select(candidates, true, [false, false, false], u32:0), (true, u32:1));
  assert_eq(select(candidates, false, [false, false, false], u32:0), (true, u32:0));
  assert_eq(select(candidates, true, [false, true, false], u32:0), (false, u32:0));
}

// Private work bypasses global egress pressure while preserving actor exclusion.
#[test]
fn reduction_work_bypasses_busy_egress_but_not_in_flight_test() {
  let candidates = Candidates<u32:3> {
    internal: [true, false, false],
    aggregate: [false, true, false],
    egress: [true, true, true],
    ..zero!<Candidates<u32:3>>()
  };
  assert_eq(select(candidates, true, [false, false, false], u32:0), (true, u32:0));
  assert_eq(select(candidates, true, [true, false, false], u32:0), (true, u32:1));
  assert_eq(select(candidates, true, [true, true, false], u32:0), (false, u32:0));
}

// Work category cannot grant an actor priority over the round-robin cursor.
#[test]
fn actor_fairness_spans_entry_mail_and_reduction_work_test() {
  let candidates = Candidates<u32:4> {
    entry: [true, false, false, false],
    mail: [false, true, false, false],
    internal: [false, false, true, false],
    aggregate: [false, false, false, true],
    ..zero!<Candidates<u32:4>>()
  };
  for (cursor, _): (u32, ()) in u32:0..u32:4 {
    assert_eq(select(candidates, true, zero!<u1[4]>(), cursor), (true, cursor));
  }(());
  assert_eq(select(candidates, true, [false, false, false, true], u32:3), (true, u32:0));
  assert_eq(select(zero!<Candidates<u32:1>>(), false, [false], u32:0), (false, u32:0));
}

// Arbitrarily long pressure at one actor cannot remove another ready actor.
#[test]
fn reserved_outbox_excludes_only_its_owner_test() {
  let work = Candidates<u32:3> { mail: [true, true, true],
    ..zero!<Candidates<u32:3>>() };
  let blocked = exclude_reserved([false, false, true], [true, false, false]);
  for (cursor, _): (u32, ()) in u32:0..u32:3 {
    assert_eq(select(work, false, blocked, cursor), (true, u32:1));
  }(());
}

// Frozen wide update is the prior BOOT/RUN successor, evaluated only on acceptance.
fn reference_cursor<COUNT: u32>(cursor: u32, accepted: bool, selected: u32) -> u32 {
  if accepted {
    if selected + u32:1 == COUNT { u32:0 } else { selected + u32:1 }
  } else { cursor }
}

// Compare all reachable cursor/selection pairs and both acceptance outcomes;
// two full BOOT walks cover singleton, power-of-two and non-power-of-two wrap.
fn check_bounded_cursor<COUNT: u32,
    WIDTH: u32 = {std::max(u32:1, std::clog2(COUNT))}>() {
  for (cursor, _): (u32, ()) in u32:0..COUNT {
    for (selected, _): (u32, ()) in u32:0..COUNT {
      for (accepted, _): (u32, ()) in u32:0..u32:2 {
        let actual = advance_cursor<COUNT>(cursor as uN[WIDTH], accepted != u32:0, selected);
        assert_eq(actual as u32, reference_cursor<COUNT>(cursor, accepted != u32:0, selected));
      }(());
    }(());
    // An unaccepted selection is irrelevant, even if its address is invalid.
    assert_eq(advance_cursor<COUNT>(cursor as uN[WIDTH], false, u32:0xffffffff) as u32, cursor);
  }(());
  let walked = for (_, state): (u32, (u32, uN[WIDTH])) in u32:0..(COUNT * u32:2) {
    let (wide, narrow) = state;
    let expected = reference_cursor<COUNT>(wide, true, wide);
    let actual = advance_cursor<COUNT>(narrow, true, narrow as u32);
    assert_eq(actual as u32, expected);
    (expected, actual)
  }((u32:0, uN[WIDTH]:0));
  assert_eq(walked, (u32:0, uN[WIDTH]:0));
}

// Accepted advancement and blocked holds preserve the old sequence for these populations.
#[test]
fn bounded_cursor_wrap_and_hold_test() {
  check_bounded_cursor<u32:1>();
  check_bounded_cursor<u32:2>();
  check_bounded_cursor<u32:4>();
  check_bounded_cursor<u32:6>();
}
