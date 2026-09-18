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

#[test]
fn shared_internal_burst_test() {
  let entered = shared_machine_enter(initial_shared_machine(), true).machine;
  let started = shared_execute(SharedExecutorRequest {
    machine: bits_from_machine(entered), received: true, egress_ready: false,
    frame: axis::pack(Tag::START as u8, u32:3), ..zero!<SharedExecutorRequest>()
  });
  let (machine, values, count) = for (cycle, state): (u32, (SharedMachine, u32[3], u32)) in u32:0..u32:24 {
    let (machine, values, count) = state;
    let step = shared_execute(SharedExecutorRequest {
      machine: bits_from_machine(machine), egress_ready: cycle > u32:5 && (cycle % u32:3 != u32:0),
      ..zero!<SharedExecutorRequest>()
    });
    let value = entry_effect(step.effects, u8:0).frame.payload as u32;
    (machine_from_bits(step.machine), if step.effects_valid { update(values, count, value) } else { values }, count + step.effects_valid as u32)
  }((machine_from_bits(started.machine), u32[3]:[0, 0, 0], u32:0));
  assert_eq(values, u32[3]:[1, 2, 3]);
  assert_eq(count, u32:3);
  assert_eq(machine.next_event, u8:0);
  assert_eq(machine.data.remaining, u32:0);
  assert_eq(machine.failure, hls_failure::NONE);
}

// Retiring a step must leave a private-work candidate without a mailbox message.
#[test]
fn pending_event_remains_schedulable_test() {
  let machine = SharedMachine { next_event: u8:1, enter_pending: false, ..initial_shared_machine() };
  let state = retire_actor(zero!<SharedState<u32:2, u32:1>>(), true, u32:1,
    SharedStep { machine, ..zero!<SharedStep>() }, false, u8:0, u8:0);
  assert_eq(ready_selection(state, u32:0, [false, false]), (true, u32:1));
  assert_eq(state.occupied, [u8:0, u8:0]);
}
