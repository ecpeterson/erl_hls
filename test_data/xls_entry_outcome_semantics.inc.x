// Appended to an actor module; exercise its private direct and shared entry
// helpers without enlarging the generated public API.
struct EntryObservation {
  failed: bool,
  pending: bool,
  data: u32,
  count: u8,
  ports: u8[3],
  values: u32[3],
}

fn observe_effect(
    observed: EntryObservation, effect: Egress, valid: bool) -> EntryObservation {
  if valid {
    EntryObservation {
      count: observed.count + u8:1,
      ports: update(observed.ports, observed.count as u32, effect.port as u8),
      values: update(observed.values, observed.count as u32,
        effect.frame.payload[0:32]),
      ..observed
    }
  } else { observed }
}

fn observe_direct(phase: Phase, value: u32, ready: u16) -> EntryObservation {
  let machine = Machine {
    phase, entered_from: phase, data: Cell { value },
    ..initial_machine()
  };
  let (machine, observed) = for (cycle, state):
      (u32, (Machine, EntryObservation)) in u32:0..u32:16 {
    let (machine, observed) = state;
    let stepped = machine_step(machine, zero!<axis::Frame>(), false,
      (ready >> cycle) as bool);
    (stepped.machine,
      observe_effect(observed, stepped.egress, stepped.egress_valid))
  }((machine, zero!<EntryObservation>()));
  EntryObservation {
    failed: machine.failed,
    pending: machine.enter_pending,
    data: machine.data.value,
    ..observed
  }
}

fn observe_shared(phase: Phase, value: u32, ready: u16) -> EntryObservation {
  let machine = SharedMachine {
    phase, entered_from: phase, data: Cell { value },
    ..initial_shared_machine()
  };
  let (machine, observed) = for (cycle, state):
      (u32, (SharedMachine, EntryObservation)) in u32:0..u32:16 {
    let (machine, observed) = state;
    let result = shared_execute(SharedExecutorRequest {
      machine: bits_from_machine(machine),
      egress_ready: (ready >> cycle) as bool,
      ..zero!<SharedExecutorRequest>()
    });
    // A shared executor publishes one batch; drain it in source order.
    let observed = for (index, observed): (u32, EntryObservation)
        in u32:0..ENTRY_EFFECT_CAPACITY {
      observe_effect(observed, entry_effect(result.effects, index as u8),
        result.effects_valid && index < entry_effect_count(result.effects) as u32
        && result.effects.valid[index])
    }(observed);
    (machine_from_bits(result.machine), observed)
  }((machine, zero!<EntryObservation>()));
  EntryObservation {
    failed: machine.failed,
    pending: machine.enter_pending,
    data: machine.data.value,
    ..observed
  }
}

fn observation_bits(observed: EntryObservation) -> bits[162] {
  (observed.failed as u1) ++ (observed.pending as u1) ++ observed.data ++
  observed.count ++ observed.ports[u32:0] ++ observed.ports[u32:1] ++
  observed.ports[u32:2] ++ observed.values[u32:0] ++
  observed.values[u32:1] ++ observed.values[u32:2]
}

pub fn entry_probe(shared: bool, phase: u8, value: u32, ready: u16) -> bits[162] {
  observation_bits(if shared {
    observe_shared(phase as Phase, value, ready)
  } else {
    observe_direct(phase as Phase, value, ready)
  })
}

#[test]
fn failing_entry_preserves_the_preceding_cast_transition_test() {
  let incoming = axis::pack(Tag::VALUE as u8, u32:0);
  let machine = Machine {
    data: Cell { value: u32:99 }, enter_pending: false,
    admission_pending: true, ..initial_machine()
  };
  let dispatched = machine_step(machine, incoming, true, true);
  assert_eq(dispatched.machine.phase, Phase::MESSAGE);
  assert_eq(dispatched.machine.data.value, u32:0);
  assert_eq(dispatched.machine.occupied, u8:0);
  assert_eq(dispatched.machine.failed, false);
  let failed = machine_step(dispatched.machine, zero!<axis::Frame>(), false, false);
  assert_eq(failed.machine.failed, true);
  assert_eq(failed.machine.phase, Phase::MESSAGE);
  assert_eq(failed.machine.data.value, u32:0);
  assert_eq(failed.egress_valid, false);
  let result = shared_execute(SharedExecutorRequest {
    machine: bits_from_machine(shared_machine(machine)),
    frame: incoming, received: true, egress_ready: false,
    ..zero!<SharedExecutorRequest>()
  });
  assert_eq(result.dispatched, true);
  assert_eq(result.directive, Directive::CONSUME);
  assert_eq(result.effects_valid, false);
  assert_eq(result.egress_blocked, false);
  assert_eq(machine_from_bits(result.machine), shared_machine(failed.machine));
}
