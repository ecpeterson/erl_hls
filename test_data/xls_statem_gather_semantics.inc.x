// Every capacity-four subset retains member order and pads inactive physical lanes.
#[test]
fn ordered_subsets_and_stale_padding_test() {
  for (mask, _): (u8, ()) in u8:0..u8:16 {
    let data = Cell { key: u32:7, mask, value: u32:0 };
    let opened = enter(Phase::IDLE, Phase::COLLECTING, data);
    assert_eq(opened.failure, hls_failure::NONE);
    let completed = for (i, state): (u32, GatherState) in u32:0..u32:4 {
      let member = u32:3 - i;
      if (mask & (u8:1 << member)) == u8:0 { state } else {
        let input = GatherContribution { valid: true, site: GatherSite::COLLECTING,
          key: u32:7, member, value: (member + u32:1) as u8 };
        gather_apply(state, input).state
      }
    }(GatherState { values: GatherValues:0xffffffff, ..opened.gather });
    assert_eq(completed.progress.status, GatherStatus::COMPLETE);
    assert_eq(gather_progress_from_bits(bits_from_gather_progress(completed.progress)), completed.progress);
    assert_eq(gather_state_from_bits(bits_from_gather_state(completed)), completed);
    let result = gather_dispatch_completion(completed.progress, completed.values, Phase::COLLECTING, data);
    let expected = for (i, value): (u32, u32) in u32:0..u32:4 {
      value + if (mask & (u8:1 << i)) == u8:0 { u32:0 } else { [u32:1, u32:20, u32:300, u32:4000][i] }
    }(u32:0);
    assert_eq(result.data.value, expected);
    assert_eq(result.progress.status, GatherStatus::IDLE);
    assert_eq(result.phase, Phase::COPIED);
    assert_eq(result.next_event, u8:1);
    assert_eq(result.failure, hls_failure::NONE);
  }(())
}

// Rejected members and mismatching keys cannot mutate a partial collection.
#[test]
fn checked_member_updates_test() {
  let opened = enter(Phase::IDLE, Phase::COLLECTING, Cell { key: u32:7, mask: u8:10, value: u32:0 }).gather;
  let input = GatherContribution { valid: true, site: GatherSite::COLLECTING,
    key: u32:7, member: u32:3, value: u8:4 };
  let accepted = gather_apply(opened, input).state;
  assert_eq(accepted.values as u32, u32:0x04000000);
  let duplicate = gather_apply(accepted, input);
  assert_eq(duplicate.outcome, GatherOutcome::DUPLICATE_MEMBER);
  assert_eq(duplicate.state, accepted);
  let absent = gather_apply(accepted, GatherContribution { member: u32:0, ..input });
  assert_eq(absent.outcome, GatherOutcome::UNEXPECTED_MEMBER);
  assert_eq(absent.state, accepted);
  let outside = gather_apply(accepted, GatherContribution { member: u32:32, ..input });
  assert_eq(outside.outcome, GatherOutcome::UNEXPECTED_MEMBER);
  assert_eq(outside.state, accepted);
  let future = gather_apply(accepted, GatherContribution { key: u32:8, ..input });
  assert_eq(future.outcome, GatherOutcome::MISMATCH);
  assert_eq(future.state, accepted);
}

// The ordinary actor preserves completion, entry, continuation and scalar-fold order under stalls.
#[test]
fn direct_collection_continuations_test() {
  let idle = machine_step(initial_machine(), zero!<axis::Frame>(), false, true).machine;
  let start = axis::pack(Tag::BEGIN_SET as u8, bits_from_beginset(Beginset { key: u32:7, mask: u8:10 }));
  let entered = machine_step(machine_step(idle, start, true, true).machine, zero!<axis::Frame>(), false, true).machine;
  let last = axis::pack(Tag::PIECE as u8, bits_from_piece(Piece { key: u32:7, member: u32:3, value: u8:4 }));
  let first = axis::pack(Tag::PIECE as u8, bits_from_piece(Piece { key: u32:7, member: u32:1, value: u8:2 }));
  let complete = machine_step(machine_step(entered, last, true, true).machine, first, true, true).machine;
  let scalar = axis::pack(Tag::SCALAR as u8, bits_from_scalar(Scalar { key: u32:7, value: u8:5 }));
  let (machine, _, values, count) = for (cycle, state): (u32, (Machine, bool, u32[2], u32)) in u32:0..u32:32 {
    let (machine, sent, values, count) = state;
    let send = !sent && machine.phase == Phase::REDUCING && !machine.enter_pending;
    let step = machine_step(machine, scalar, send, cycle > u32:4 && cycle % u32:3 != u32:0);
    (step.machine, sent || send, if step.egress_valid { update(values, count, step.egress.frame.payload as u32) } else { values }, count + step.egress_valid as u32)
  }((complete, false, u32[2]:[0, 0], u32:0));
  assert_eq(values, u32[2]:[4020, 4025]);
  assert_eq(count, u32:2);
  assert_eq(machine.phase, Phase::DONE);
  assert_eq(machine.gather.progress.status, GatherStatus::IDLE);
  assert_eq(machine.reduction.status, ReductionStatus::IDLE);
  assert_eq(machine.next_event, u8:0);
  assert_eq(machine.failure, hls_failure::NONE);
}
