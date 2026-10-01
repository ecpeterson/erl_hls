#[test]
fn direct_machine_drains_before_latching_failure() {
  let idle = zero!<axis::Frame>();
  let opened = Machine { phase: Phase::GATHERING, enter_pending: u1:0,
    reduction: failure_test_open(), ..initial_machine() };
  let bad = machine_step(opened, failure_test_frame(u32:0), u1:1, u1:1).machine;
  assert_eq(bad.failure, hls_failure::NONE);
  assert_eq(bad.reduction.remaining, ReductionRemaining:2);
  let credited = machine_step(bad, idle, u1:0, u1:1).machine;
  let second = machine_step(credited, failure_test_frame(u32:4), u1:1, u1:1).machine;
  assert_eq(second.failure, hls_failure::NONE);
  assert_eq(second.reduction.remaining, ReductionRemaining:1);
  let stalled = for (_, state): (u32, Machine) in u32:0..u32:10 {
    machine_step(state, idle, u1:0, u1:0).machine
  }(second);
  assert_eq(stalled.failure, hls_failure::NONE);
  assert_eq(stalled.reduction, second.reduction);
  let last = machine_step(stalled, failure_test_frame(u32:1), u1:1, u1:1).machine;
  assert_eq(last.reduction.status, ReductionStatus::COMPLETE);
  let completed = machine_step(last, idle, u1:0, u1:1);
  assert_eq(completed.machine.failure, bad.reduction.failure);
  assert_eq(completed.machine.phase, Phase::GATHERING);
  assert_eq(completed.egress_valid, u1:0);
}
