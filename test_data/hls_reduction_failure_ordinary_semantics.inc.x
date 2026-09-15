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

#[test]
fn shared_machine_drains_before_latching_failure() {
  let opened = SharedMachine { phase: Phase::GATHERING, enter_pending: u1:0,
    reduction: failure_test_open(), ..initial_shared_machine() };
  let bad = shared_machine_dispatch(opened, failure_test_frame(u32:0), u1:1);
  assert_eq(bad.directive, Directive::CONSUME);
  assert_eq(bad.machine.failure, hls_failure::NONE);
  assert_eq(bad.machine.reduction.remaining, ReductionRemaining:2);
  let roundtrip = machine_from_bits(bits_from_machine(bad.machine));
  let second = shared_machine_dispatch(roundtrip, failure_test_frame(u32:4), u1:1);
  assert_eq(second.directive, Directive::CONSUME);
  assert_eq(second.machine.failure, hls_failure::NONE);
  let last = shared_machine_dispatch(second.machine, failure_test_frame(u32:1), u1:1);
  assert_eq(last.machine.reduction.status, ReductionStatus::COMPLETE);
  let completed = shared_machine_complete(last.machine);
  assert_eq(completed.machine.failure, bad.machine.reduction.failure);
  assert_eq(completed.directive, Directive::FAIL);
  assert_eq(completed.machine.phase, Phase::GATHERING);
  assert_eq(completed.machine.data, opened.data);
}
