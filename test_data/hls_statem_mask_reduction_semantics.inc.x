// Exhaustive six-bit population witnesses for the ordinary generated actor helpers.
#[test]
fn every_six_bit_population_test() {
  for (mask, _): (u8, ()) in u8:1..u8:64 {
    let outcome = enter(Phase::IDLE, Phase::COLLECTING, Cell { key: u32:7, mask, value: u8:0 });
    assert_eq(outcome.failure, hls_failure::NONE);
    assert_eq(outcome.reduction.expected, mask as ReductionMembers);
    let complete = for (i, state): (u32, ReductionState) in u32:0..u32:6 {
      let member = u32:5 - i;
      let value = u8:1 << member;
      if (mask & value) == u8:0 { state } else {
        let contribution = ReductionContribution {
          valid: u1:1, site: ReductionSite::COLLECTING, key: u32:7,
          member, value: Parity { value },
        };
        reduction_apply(state, contribution).state
      }
    }(outcome.reduction);
    assert_eq(complete.status, ReductionStatus::COMPLETE);
    assert_eq(complete.accumulator.value, mask);
    assert_eq(reduction_state_from_bits(bits_from_reduction_state(complete)), complete);
  }(())
}

// Invalid opens fail transactionally without committing a reduction or any effects.
#[test]
fn invalid_open_masks_test() {
  for (i, _): (u32, ()) in u32:0..u32:3 {
    let mask = [u8:0, u8:64, u8:255][i];
    let outcome = enter(Phase::IDLE, Phase::COLLECTING, Cell { key: u32:7, mask, value: u8:0 });
    assert_eq(hls_failure::failed(outcome.failure), u1:1);
    assert_eq(outcome.reduction.status, ReductionStatus::IDLE);
    assert_eq(outcome.effects.layout, u8:0);
  }(())
}

// A missing or duplicate member cannot replace another selected member.
#[test]
fn rejected_members_do_not_advance_test() {
  let opened = enter(Phase::IDLE, Phase::COLLECTING,
    Cell { key: u32:7, mask: u8:33, value: u8:0 }).reduction;
  let absent = ReductionContribution { valid: u1:1, site: ReductionSite::COLLECTING,
    key: u32:7, member: u32:1, value: Parity { value: u8:2 } };
  let rejected = reduction_apply(opened, absent);
  assert_eq(rejected.outcome, ReductionOutcome::UNEXPECTED_MEMBER);
  assert_eq(rejected.state, opened);
  let first = ReductionContribution { member: u32:5, value: Parity { value: u8:32 }, ..absent };
  let accepted = reduction_apply(opened, first).state;
  let duplicate = reduction_apply(accepted, first);
  assert_eq(duplicate.outcome, ReductionOutcome::DUPLICATE_MEMBER);
  assert_eq(duplicate.state, accepted);
  let future = reduction_apply(accepted, ReductionContribution { key: u32:8, ..first });
  assert_eq(future.outcome, ReductionOutcome::MISMATCH);
  assert_eq(future.state, accepted);
}
