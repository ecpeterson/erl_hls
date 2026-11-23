// Committed observations select active collection metadata without reading ordered payloads.
#[test]
fn gather_and_scalar_observation_test() {
  let data = Cell { key: u32:7, mask: u8:10, value: u32:0 };
  let opened = enter(Phase::IDLE, Phase::COLLECTING, data).gather;
  let contribution = GatherContribution { valid: true, site: GatherSite::COLLECTING,
      key: u32:7, member: u32:3, value: u8:4 };
  let gather = gather_apply(opened, contribution).state;
  let machine = Machine { phase: Phase::COLLECTING, gather, ..initial_machine() };
  let observed = actor_observation(machine);
  assert_eq(observed[25:27], u2:1);
  assert_eq(observed[27:28], u1:1);
  assert_eq(observed[28:60], u32:7);
  assert_eq(observed[60:63], u3:1);
  assert_eq(observed[79:83], u4:10);
  assert_eq(observed[83:87], u4:8);
  assert_eq(actor_observation(Machine { gather: GatherState { values: GatherValues:0x11223344, ..gather }, ..machine }), observed);
  let reduction = enter(Phase::COPIED, Phase::REDUCING, data).reduction;
  let observed_scalar = actor_observation(Machine { gather: zero!<GatherState>(), reduction, ..machine });
  assert_eq(observed_scalar[25:27], u2:1);
  assert_eq(observed_scalar[27:28], u1:0);
  assert_eq(observed_scalar[28:60], u32:7);
  assert_eq(observed_scalar[60:63], u3:1);
}
