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

// Both source site IDs use the shared capacity-three masks, with payload bits above progress.
#[test]
fn distinct_site_progress_codec_test() {
  for (site, _): (GatherSite, ()) in [GatherSite::NARROW, GatherSite::WIDE] {
    let progress = GatherProgress { status: GatherStatus::OPEN, site,
      key: u32:0x76543210, remaining: u8:2, expected: GatherMembers:0x5,
      seen: GatherMembers:0x1, failure: hls_failure::Code:0x13d7 };
    let expected = u16:0x13d7 ++ u3:0x1 ++ u3:0x5 ++ u8:2 ++ u32:0x76543210 ++ (site as u8) ++ u2:1;
    assert_eq(bits_from_gather_progress(progress), expected);
    assert_eq(gather_progress_from_bits(expected), progress);
    let state = GatherState { progress, values: GatherValues:0x0123456789ab };
    assert_eq(bits_from_gather_state(state), u48:0x0123456789ab ++ expected);
    assert_eq(gather_state_from_bits(bits_from_gather_state(state)), state);
  }(())
}
