#[test]
fn failed_entry_does_not_open_or_emit_test() {
  for (phase_index, ()): (u32, ()) in u32:0..u32:2 {
    let phase = (phase_index as u8) as Phase;
    for (value, ()): (u32, ()) in u32:0..u32:2 {
      for (ready, ()): (u32, ()) in u32:0..u32:2 {
        let machine = Machine {
          phase, entered_from: phase, data: Cell { value },
          ..initial_machine()
        };
        let failed = machine_step(machine, zero!<axis::Frame>(), false, ready as bool);
        assert_eq(hls_failure::failed(failed.machine.failure), true);
        assert_eq(failed.machine.enter_pending, false);
        assert_eq(failed.egress_valid, false);
        assert_eq(failed.admission_valid, false);
        assert_eq(failed.machine.data, machine.data);
        assert_eq(failed.machine.reduction, machine.reduction);
        let shared = shared_machine_enter(shared_machine(machine), ready as bool);
        assert_eq(hls_failure::failed(shared.machine.failure), true);
        assert_eq(shared.machine.enter_pending, false);
        assert_eq(shared.effects_valid, false);
        assert_eq(shared.egress_blocked, false);
        assert_eq(shared.machine.data, machine.data);
        assert_eq(shared.machine.reduction, machine.reduction);
      }(())
    }(())
  }(())
}

#[test]
fn reduction_and_data_commit_after_ordered_effects_test() {
  let machine = Machine { data: Cell { value: u32:2 }, ..initial_machine() };
  let first = machine_step(machine, zero!<axis::Frame>(), false, true);
  assert_eq(hls_failure::failed(first.machine.failure), false);
  assert_eq(first.egress_valid, true);
  assert_eq(first.egress.port, OutputPort::FIRST);
  assert_eq(first.egress.frame.payload[0:32], u32:11);
  assert_eq(first.machine.data, machine.data);
  assert_eq(first.machine.reduction.status, ReductionStatus::IDLE);
  assert_eq(first.machine.enter_pending, true);
  let stalled = machine_step(first.machine, zero!<axis::Frame>(), false, false);
  assert_eq(stalled.machine, first.machine);
  assert_eq(stalled.egress_valid, false);
  let last = machine_step(stalled.machine, zero!<axis::Frame>(), false, true);
  assert_eq(last.egress_valid, true);
  assert_eq(last.egress.port, OutputPort::SECOND);
  assert_eq(last.egress.frame.payload[0:32], u32:2);
  assert_eq(last.machine.data.value, u32:12);
  assert_eq(last.machine.enter_pending, false);
  assert_eq(last.machine.reduction.status, ReductionStatus::OPEN);
  assert_eq(last.machine.reduction.key, u32:2);
  assert_eq(last.machine.reduction.accumulator.value, u32:3);
  let shared_stall = shared_machine_enter(shared_machine(machine), false);
  assert_eq(shared_stall.machine, shared_machine(machine));
  assert_eq(shared_stall.effects_valid, false);
  assert_eq(shared_stall.egress_blocked, true);
  let shared = shared_machine_enter(shared_stall.machine, true);
  assert_eq(shared.effects_valid, true);
  assert_eq(shared.machine, shared_machine(last.machine));
  assert_eq(entry_effect(shared.effects, u8:0), first.egress);
  assert_eq(entry_effect(shared.effects, u8:1), last.egress);
}

#[test]
fn invalid_reopen_preserves_existing_reduction_test() {
  let machine = Machine {
    data: Cell { value: u32:2 },
    reduction: reduction_open_site(ReductionSite::GATHERING, u32:99,
      Sum { value: u32:17 }),
    ..initial_machine()
  };
  let direct = machine_step(machine, zero!<axis::Frame>(), false, true);
  assert_eq(direct.machine.failure, hls_failure::REDUCTION_PROTOCOL);
  assert_eq(direct.egress_valid, false);
  assert_eq(direct.machine.data, machine.data);
  assert_eq(direct.machine.reduction, machine.reduction);
  let shared = shared_machine_enter(shared_machine(machine), true);
  assert_eq(shared.machine.failure, hls_failure::REDUCTION_PROTOCOL);
  assert_eq(shared.effects_valid, false);
  assert_eq(shared.machine.data, machine.data);
  assert_eq(shared.machine.reduction, machine.reduction);
}

#[test]
fn optional_open_depends_on_the_selected_entry_branch_test() {
  let machine = Machine { phase: Phase::OPTIONAL, entered_from: Phase::OPTIONAL,
    data: Cell { value: u32:0 }, ..initial_machine() };
  let existing = reduction_open_site(ReductionSite::OPTIONAL, u32:9, Sum { value: u32:7 });
  let machine = Machine { reduction: existing, ..machine };
  let skipped = machine_step(machine, zero!<axis::Frame>(), false, false);
  assert_eq(hls_failure::failed(skipped.machine.failure), false);
  assert_eq(skipped.machine.enter_pending, false);
  assert_eq(skipped.machine.reduction, existing);
  assert_eq(skipped.machine.data.value, u32:10);
  assert_eq(skipped.egress_valid, false);
  let shared = shared_execute(SharedExecutorRequest {
    machine: bits_from_machine(shared_machine(machine)), egress_ready: false,
    ..zero!<SharedExecutorRequest>()
  });
  assert_eq(machine_from_bits(shared.machine), shared_machine(skipped.machine));
  assert_eq(shared.effects_valid, false);
  assert_eq(shared.egress_blocked, false);
  let opening = Machine { data: Cell { value: u32:1 }, ..machine };
  let rejected = machine_step(opening, zero!<axis::Frame>(), false, false);
  assert_eq(hls_failure::failed(rejected.machine.failure), true);
  assert_eq(rejected.machine.reduction, existing);
  assert_eq(rejected.egress_valid, false);
  let opening = Machine { reduction: zero!<ReductionState>(), ..opening };
  let blocked = machine_step(opening, zero!<axis::Frame>(), false, false);
  assert_eq(blocked.machine, opening);
  let accepted = machine_step(opening, zero!<axis::Frame>(), false, true);
  assert_eq(hls_failure::failed(accepted.machine.failure), false);
  assert_eq(accepted.machine.reduction.key, u32:1);
  assert_eq(accepted.machine.reduction.status, ReductionStatus::OPEN);
  assert_eq(accepted.egress_valid, true);
}

#[test]
fn selected_expression_failure_precedes_reduction_reopen_test() {
  let machine = Machine {
    data: Cell { value: u32:0 },
    reduction: reduction_open_site(ReductionSite::GATHERING, u32:99,
      Sum { value: u32:17 }),
    ..initial_machine()
  };
  let direct = machine_step(machine, zero!<axis::Frame>(), false, true);
  let shared = shared_machine_enter(shared_machine(machine), true);
  assert_eq(hls_failure::kind(direct.machine.failure), hls_failure::Kind::MATCH_FAILURE);
  assert_eq(direct.machine.failure > u16:15, true);
  assert_eq(shared.machine.failure, direct.machine.failure);
  assert_eq(direct.machine.reduction, machine.reduction);
  assert_eq(shared.machine.reduction, machine.reduction);
  assert_eq(direct.egress_valid, false);
  assert_eq(shared.effects_valid, false);
}
