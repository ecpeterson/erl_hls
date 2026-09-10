// Shared actor scheduling policy, independent of actor records and callbacks.

import arbitration;

pub struct Candidates<COUNT: u32> {
  entry: u1[COUNT],
  mail: u1[COUNT],
  egress: u1[COUNT],
  internal: u1[COUNT],
  aggregate: u1[COUNT],
}

// Private reduction work can run while egress is busy. Within each actor,
// entry/egress work suppresses mailbox dispatch; in-flight actors stay excluded.
// The round-robin choice is across eligible actors, not across work categories.
pub fn select<COUNT: u32>(
    candidates: Candidates<COUNT>, egress_busy: u1,
    in_flight: u1[COUNT], cursor: u32) -> (u1, u32) {
  let selectable = unroll_for! (slot, result):
      (u32, u1[COUNT]) in u32:0..COUNT {
    let private_active = candidates.internal[slot] || candidates.aggregate[slot];
    let entry_active = private_active || candidates.entry[slot] || candidates.egress[slot];
    let ready = private_active || (!private_active && (
      candidates.entry[slot] ||
      (candidates.mail[slot] && !entry_active) ||
      (candidates.egress[slot] && !egress_busy)));
    update(result, slot, ready && !in_flight[slot])
  }(zero!<u1[COUNT]>());
  arbitration::select(selectable, cursor)
}

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
