// Appended to the generated fixture by tools/test_reduction_dslx.sh so these
// tests can inspect its private canonical-machine helpers without making them
// part of the generated public API.

fn reduction_test_count(key: u32, value: u32) -> axis::Frame {
  axis::pack(
    Tag::COUNT_VALUE as u8,
    bits_from_countvalue(Countvalue { key, value }))
}

fn reduction_test_member(
    key: u32, member: u32, value: u32) -> axis::Frame {
  axis::pack(
    Tag::MEMBER_VALUE as u8,
    bits_from_membervalue(Membervalue { key, member, value }))
}



#[test]
fn reduction_direct_machine_test() {
  let idle = zero!<axis::Frame>();
  let entered = machine_step(
    initial_machine(), idle, u1:0, u1:1).machine;
  assert_eq(entered.data.entries, u8:1);
  assert_eq(entered.reduction.status, ReductionStatus::OPEN);
  assert_eq(entered.reduction.remaining, ReductionRemaining:2);

  // A contribution for another key waits in the ordinary mailbox.
  let mismatched = machine_step(
    entered, reduction_test_count(u32:1, u32:99), u1:1, u1:1).machine;
  assert_eq(hls_failure::failed(mismatched.failure), u1:0);
  assert_eq(mismatched.occupied, u8:1);
  assert_eq(mismatched.slots[0].postponed, u1:1);
  assert_eq(mismatched.reduction.remaining, ReductionRemaining:2);

  let first = machine_step(
    entered, reduction_test_count(u32:0, u32:11), u1:1, u1:1).machine;
  assert_eq(first.reduction.accumulator,
    Sum { value: u32:11, contributions: u8:1 });
  let credited = machine_step(first, idle, u1:0, u1:1).machine;
  let complete = machine_step(
    credited, reduction_test_count(u32:0, u32:13), u1:1, u1:1).machine;
  assert_eq(complete.reduction.status, ReductionStatus::COMPLETE);
  assert_eq(complete.reduction.accumulator,
    Sum { value: u32:24, contributions: u8:2 });

  let transitioned = machine_step(
    complete, idle, u1:0, u1:1).machine;
  assert_eq(transitioned.phase, Phase::COLLECTING_MEMBERS);
  assert_eq(transitioned.data.value, u32:24);
  let member_entry = machine_step(
    transitioned, idle, u1:0, u1:1).machine;
  let one_member = machine_step(
    member_entry,
    reduction_test_member(u32:0, u32:7, u32:5),
    u1:1,
    u1:1).machine;
  let member_credit = machine_step(
    one_member, idle, u1:0, u1:1).machine;
  let duplicate = machine_step(
    member_credit,
    reduction_test_member(u32:0, u32:7, u32:8),
    u1:1,
    u1:1).machine;
  assert_eq(hls_failure::failed(duplicate.failure), u1:1);
}
