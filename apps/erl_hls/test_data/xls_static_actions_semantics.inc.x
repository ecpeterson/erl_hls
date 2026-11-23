// Finite observation of one direct actor entry, including independent egress stalls.
struct StaticEntryObservation {
  failed: bool,
  pending: bool,
  data: u32,
  count: u8,
  ports: u8[2],
  values: u32[2],
}

// Append one accepted effect without projecting any unaccepted payload.
fn static_observe_effect(
    observed: StaticEntryObservation, effect: Egress, valid: bool) -> StaticEntryObservation {
  if valid {
    StaticEntryObservation {
      count: observed.count + u8:1,
      ports: update(observed.ports, observed.count as u32, effect.port as u8),
      values: update(observed.values, observed.count as u32, effect.frame.payload[0:32]),
      ..observed
    }
  } else { observed }
}

// Start at an explicit entry state and inspect sixteen clocks; this is a finite witness.
fn static_observe_entry(phase: Phase, value: u32, ready: u16) -> StaticEntryObservation {
  let machine = Machine {
    phase, entered_from: phase, data: Cell { value }, ..initial_machine()
  };
  let (machine, observed) = for (cycle, state):
      (u32, (Machine, StaticEntryObservation)) in u32:0..u32:16 {
    let (machine, observed) = state;
    let stepped = machine_step(machine, zero!<axis::Frame>(), false,
      (ready >> cycle) as bool);
    (stepped.machine,
      static_observe_effect(observed, stepped.egress, stepped.egress_valid))
  }((machine, zero!<StaticEntryObservation>()));
  StaticEntryObservation {
    failed: hls_failure::failed(machine.failure),
    pending: machine.enter_pending,
    data: machine.data.value,
    ..observed
  }
}

// The BEAM oracle uses the same explicit scalar field ordering.
pub fn static_entry_probe(phase: u8, value: u32, ready: u16) -> bits[122] {
  let observed = static_observe_entry(phase as Phase, value, ready);
  (observed.failed as u1) ++ (observed.pending as u1) ++ observed.data ++
  observed.count ++ observed.ports[u32:0] ++ observed.ports[u32:1] ++
  observed.values[u32:0] ++ observed.values[u32:1]
}
