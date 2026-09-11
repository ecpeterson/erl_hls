// Appended to an actor module; exercise its private direct and shared entry
// helpers without enlarging the generated public API.
struct EntryObservation {
  failed: bool,
  pending: bool,
  data: u32,
  count: u8,
  ports: u8[3],
  tags: u8[3],
  lengths: u8[3],
  values: u64[3],
}

fn observe_effect(
    observed: EntryObservation, effect: Egress, valid: bool) -> EntryObservation {
  if valid {
    EntryObservation {
      count: observed.count + u8:1,
      ports: update(observed.ports, observed.count as u32, effect.port as u8),
      tags: update(observed.tags, observed.count as u32, effect.frame.header.op),
      lengths: update(observed.lengths, observed.count as u32, effect.frame.header.payload_words),
      values: update(observed.values, observed.count as u32,
        effect.frame.payload[0:64]),
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

fn observation_bits(observed: EntryObservation) -> bits[306] {
  (observed.failed as u1) ++ (observed.pending as u1) ++ observed.data ++
  observed.count ++ observed.ports[u32:0] ++ observed.ports[u32:1] ++
  observed.ports[u32:2] ++
  observed.tags[u32:0] ++ observed.tags[u32:1] ++ observed.tags[u32:2] ++
  observed.lengths[u32:0] ++ observed.lengths[u32:1] ++ observed.lengths[u32:2] ++
  observed.values[u32:0] ++
  observed.values[u32:1] ++ observed.values[u32:2]
}

pub fn entry_probe(shared: bool, phase: u8, value: u32, ready: u16) -> bits[306] {
  observation_bits(if shared {
    observe_shared(phase as Phase, value, ready)
  } else {
    observe_direct(phase as Phase, value, ready)
  })
}

// RTL checks one transition at a time, so the synthesized test circuit does
// not contain sixteen cascaded copies of the complete entry implementation.
pub fn entry_cycle_probe(shared: bool, phase: u8, value: u32,
    pending: bool, failed: bool, index: u8, ready: bool) -> bits[314] {
  let machine = Machine {
    phase: phase as Phase, entered_from: phase as Phase, data: Cell { value },
    enter_pending: pending, failed, entry_effect_index: index, ..initial_machine()
  };
  let (next, observed) = if shared {
    let result = shared_execute(SharedExecutorRequest {
      machine: bits_from_machine(shared_machine(machine)), egress_ready: ready,
      ..zero!<SharedExecutorRequest>()
    });
    let observed = for (i, observed): (u32, EntryObservation)
        in u32:0..ENTRY_EFFECT_CAPACITY {
      observe_effect(observed, entry_effect(result.effects, i as u8),
        result.effects_valid && i < entry_effect_count(result.effects) as u32
        && result.effects.valid[i])
    }(zero!<EntryObservation>());
    let next = machine_from_bits(result.machine);
    (Machine { data: next.data, enter_pending: next.enter_pending,
      failed: next.failed, ..machine }, observed)
  } else {
    let result = machine_step(machine, zero!<axis::Frame>(), false, ready);
    (result.machine, observe_effect(zero!<EntryObservation>(),
      result.egress, result.egress_valid))
  };
  next.entry_effect_index ++ observation_bits(EntryObservation {
    failed: next.failed, pending: next.enter_pending, data: next.data.value, ..observed
  })
}
