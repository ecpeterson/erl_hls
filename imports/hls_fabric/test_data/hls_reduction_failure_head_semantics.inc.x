#[test]
fn missed_reducer_clause_is_absorbing() {
  let opened = reduction_open_site(ReductionSite::GATHERING, u32:0, zero!<Sum>());
  let contribution = ReductionContribution { valid: u1:1,
    site: ReductionSite::GATHERING, value: Sum { value: u32:1 },
    ..zero!<ReductionContribution>() };
  // The generated variant binds the same variable in both accumulator heads.
  let first = reduction_apply(opened, contribution);
  assert_eq(first.outcome, ReductionOutcome::PENDING);
  assert_eq(hls_failure::kind(first.state.failure), hls_failure::Kind::FUNCTION_CLAUSE);
  let second = reduction_apply(first.state, contribution);
  let last = reduction_apply(second.state, contribution);
  assert_eq(last.outcome, ReductionOutcome::COMPLETE);
  assert_eq(last.state.failure, first.state.failure);
  let completed = reduction_dispatch_completion(last.state, Phase::GATHERING, zero!<Cell>());
  assert_eq(completed.directive, Directive::FAIL);
  assert_eq(completed.failure, first.state.failure);
}
