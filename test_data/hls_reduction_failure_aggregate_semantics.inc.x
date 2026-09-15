#[test]
fn aggregate_bottom_counts_every_contribution() {
  let first = reduction_aggregate_push(zero!<ReductionAggregate>(), failure_test_frame(u32:1));
  let second = reduction_aggregate_push(first, failure_test_frame(u32:0));
  assert_eq(second.count, ReductionRemaining:2);
  assert_eq(second.accumulator.value, u32:1);
  assert_eq(hls_failure::kind(second.failure), hls_failure::Kind::BADARITH);
  // An incomplete aggregate cannot release even an error value to the actor.
  assert_eq(reduction_apply_complete_aggregate(failure_test_open(), second).outcome,
    ReductionOutcome::MISMATCH);
  let full = reduction_aggregate_push(second, failure_test_frame(u32:4));
  assert_eq(full.count, ReductionRemaining:3);
  assert_eq(full.failure, second.failure);
  assert_eq(full.accumulator, second.accumulator);
  let applied = reduction_apply_complete_aggregate(failure_test_open(), full);
  assert_eq(applied.outcome, ReductionOutcome::COMPLETE);
  assert_eq(applied.state.failure, second.failure);
  let machine = SharedMachine { phase: Phase::GATHERING, enter_pending: u1:0,
    reduction: failure_test_open(), ..initial_shared_machine() };
  let request = ReductionAggregateRequest { slot: u32:1, aggregate: full };
  let completed = shared_machine_aggregate(machine, request, u32:1);
  assert_eq(completed.machine.failure, second.failure);
  assert_eq(completed.machine.phase, Phase::GATHERING);
  assert_eq(completed.machine.data, machine.data);
  assert_eq(completed.directive, Directive::FAIL);
  // A foreign aggregate cannot attribute its source error to this actor.
  let wrong = shared_machine_aggregate(machine, request, u32:0);
  assert_eq(wrong.machine.failure, hls_failure::REDUCTION_PROTOCOL);
  let sticky = shared_machine_aggregate(
    SharedMachine { failure: hls_failure::INVALID_MESSAGE, ..machine }, request, u32:1);
  assert_eq(sticky.machine.failure, hls_failure::INVALID_MESSAGE);
}
