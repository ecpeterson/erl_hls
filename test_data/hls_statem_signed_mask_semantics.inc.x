// Signed masks must pass positivity and high-bit checks before truncation to capacity.
#[test]
fn signed_mask_bounds_test() {
  for (i, _): (u32, ()) in u32:0..u32:5 {
    let mask = [s8:0, s8:-1, s8:-64, s8:64, s8:127][i];
    let outcome = enter(Phase::IDLE, Phase::COLLECTING, Cell { key: u32:7, mask, value: u8:0 });
    assert_eq(hls_failure::failed(outcome.failure), u1:1);
    assert_eq(outcome.reduction.status, ReductionStatus::IDLE);
  }(());
  let outcome = enter(Phase::IDLE, Phase::COLLECTING,
    Cell { key: u32:7, mask: s8:33, value: u8:0 });
  assert_eq(outcome.failure, hls_failure::NONE);
  assert_eq(outcome.reduction.expected, ReductionMembers:33);
  assert_eq(outcome.reduction.remaining, ReductionRemaining:2);
}
