// A committed direct-actor sample exposes the exact sparse membership without accumulator bits.
#[test]
fn committed_membership_observation_test() {
  let opened = enter(Phase::IDLE, Phase::COLLECTING,
    Cell { key: u32:7, mask: u8:33, value: u8:0 }).reduction;
  let contribution = ReductionContribution { valid: u1:1, site: ReductionSite::COLLECTING,
    key: u32:7, member: u32:5, value: Parity { value: u8:32 } };
  let machine = Machine { reduction: reduction_apply(opened, contribution).state, ..initial_machine() };
  let observed = actor_observation(machine);
  assert_eq(observed[25:27], u2:1);
  assert_eq(observed[60:63], u3:1);
  assert_eq(observed[79:85], u6:33);
  assert_eq(observed[85:91], u6:32);
}
