// Tests run against the actual Erlang combiner and its source-located helpers.
fn failure_test_value(value: u32) -> ReductionContribution {
  ReductionContribution { valid: u1:1, site: ReductionSite::GATHERING,
    value: Sum { value }, ..zero!<ReductionContribution>() }
}

fn failure_test_frame(value: u32) -> axis::Frame {
  axis::pack(Tag::MESSAGE as u8, bits_from_message(Message { value }))
}

fn failure_test_open() -> ReductionState {
  reduction_open_site(ReductionSite::GATHERING, u32:0, zero!<Sum>())
}

#[test]
fn failed_fold_drains_and_suppresses_completion() {
  let first = reduction_apply(failure_test_open(), failure_test_value(u32:1));
  let second = reduction_apply(first.state, failure_test_value(u32:0));
  assert_eq(second.outcome, ReductionOutcome::PENDING);
  assert_eq(second.state.status, ReductionStatus::OPEN);
  assert_eq(second.state.remaining, ReductionRemaining:1);
  assert_eq(second.state.accumulator.value, u32:1);
  assert_eq(hls_failure::kind(second.state.failure), hls_failure::Kind::BADARITH);
  assert_eq(second.state.failure != hls_failure::BADARITH, true);
  assert_eq(reduction_state_from_bits(bits_from_reduction_state(second.state)), second.state);
  let pending = reduction_dispatch_completion(second.state, Phase::GATHERING, zero!<Cell>());
  assert_eq(pending.dispatched, u1:0);
  assert_eq(pending.failure, hls_failure::NONE);

  let wrong = reduction_apply(second.state,
    ReductionContribution { key: u32:7, ..failure_test_value(u32:1) });
  assert_eq(wrong.outcome, ReductionOutcome::MISMATCH);
  assert_eq(wrong.state, second.state);

  // This value would cause a different error if the reducer were evaluated.
  let last = reduction_apply(second.state, failure_test_value(u32:4));
  assert_eq(last.outcome, ReductionOutcome::COMPLETE);
  assert_eq(last.state.remaining, ReductionRemaining:0);
  assert_eq(last.state.failure, second.state.failure);
  assert_eq(last.state.accumulator.value, u32:1);
  let completed = reduction_dispatch_completion(last.state, Phase::GATHERING, zero!<Cell>());
  assert_eq(completed.directive, Directive::FAIL);
  assert_eq(completed.phase, Phase::GATHERING);
  assert_eq(completed.data, zero!<Cell>());
  assert_eq(completed.failure, second.state.failure);
}

#[test]
fn selected_combiner_failures_keep_their_reason() {
  let cases = [(u32:0, hls_failure::Kind::BADARITH),
    (u32:2, hls_failure::Kind::CASE_CLAUSE),
    (u32:3, hls_failure::Kind::MATCH_FAILURE),
    (u32:4, hls_failure::Kind::IF_CLAUSE)];
  for (test, ()): ((u32, hls_failure::Kind), ()) in cases {
    let applied = reduction_apply(failure_test_open(), failure_test_value(test.0));
    assert_eq(applied.outcome, ReductionOutcome::PENDING);
    assert_eq(applied.state.remaining, ReductionRemaining:2);
    assert_eq(hls_failure::kind(applied.state.failure), test.1);
  }(())
}
