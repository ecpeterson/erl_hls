// Distinct site types and capacities reuse one ordinary payload without sharing an accumulator type.
#[test]
fn different_site_types_test() {
  let narrow = enter(Phase::NARROW, Phase::NARROW, Cell { value: u32:0 }).gather;
  let one = GatherContribution { valid: true, site: GatherSite::NARROW, key: u32:7, member: u32:0, value: u16:1 };
  let first = gather_apply(gather_apply(narrow, one).state, GatherContribution { member: u32:1, value: u16:2, ..one }).state;
  let moved = gather_dispatch_completion(first.progress, first.values, Phase::NARROW, Cell { value: u32:0 });
  assert_eq(moved.phase, Phase::WIDE);
  assert_eq(moved.data.value, u32:3);
  assert_eq(moved.next_event, u8:0);
  let wide = enter(Phase::NARROW, Phase::WIDE, moved.data).gather;
  let wide = GatherState { values: GatherValues:0xffffffffffff, ..wide };
  let input = GatherContribution { site: GatherSite::WIDE, value: u16:100, ..one };
  let complete = gather_apply(gather_apply(wide, input).state, GatherContribution { member: u32:2, value: u16:300, ..input }).state;
  let result = gather_dispatch_completion(complete.progress, complete.values, Phase::WIDE, moved.data);
  assert_eq(result.data.value, u32:412);
  assert_eq(result.phase, Phase::DONE);
  assert_eq(result.failure, hls_failure::NONE);
  assert_eq(result.progress.status, GatherStatus::IDLE);
}
