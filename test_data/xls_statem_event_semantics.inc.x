// Exercise the same checked callbacks through both scheduling paths under output stalls.
#[test]
fn direct_internal_burst_test() {
  let frame = axis::pack(Tag::START as u8, u32:3);
  let entered = machine_step(initial_machine(), zero!<axis::Frame>(), false, true).machine;
  let started = machine_step(entered, frame, true, true).machine;
  let (machine, values, count) = for (cycle, state): (u32, (Machine, u32[3], u32)) in u32:0..u32:24 {
    let (machine, values, count) = state;
    let step = machine_step(machine, zero!<axis::Frame>(), false, cycle > u32:5 && (cycle % u32:3 != u32:0));
    (step.machine, if step.egress_valid { update(values, count, step.egress.frame.payload as u32) } else { values }, count + step.egress_valid as u32)
  }((started, u32[3]:[0, 0, 0], u32:0));
  assert_eq(values, u32[3]:[1, 2, 3]);
  assert_eq(count, u32:3);
  assert_eq(machine.next_event, u8:0);
  assert_eq(machine.data.remaining, u32:0);
  assert_eq(machine.failure, hls_failure::NONE);
}



// Retiring a step must leave a private-work candidate without a mailbox message.
