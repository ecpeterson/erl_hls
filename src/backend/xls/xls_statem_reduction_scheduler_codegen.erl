%%%% xls_statem_reduction_scheduler_codegen
%%%%
%%%% Splices actor-local reduction semantics into the direct and shared
%%%% schedulers rendered by xls_statem_codegen.  Keeping these DSLX templates
%%%% separate makes the generic scheduler's control flow readable and keeps
%%%% reduction ordering/fencing policy in one place.

-module(xls_statem_reduction_scheduler_codegen).
-moduledoc false.

-export([
    direct_after_failed/2,
    direct_dispatch_bindings/1,
    direct_effective_binding/1,
    direct_entry_can_advance/1,
    direct_entry_egress_valid/1,
    direct_entry_failed_field/1,
    direct_entry_machine_selection/1,
    direct_entry_open_bindings/1,
    direct_entry_reduction_field/1,
    direct_failed_binding/1,
    direct_receive_gate/1,
    direct_reduction_update_field/1,
    shared_dispatch_dispatched_field/1,
    shared_dispatch_effective_binding/1,
    shared_dispatch_failed_binding/1,
    shared_blocked_probe_bindings/1,
    shared_entry_step/1,
    shared_executor_dispatch/1,
    shared_executor_internal_request_field/1,
    shared_executor_send_condition/1,
    shared_folded_state_fields/1,
    shared_in_flight_field/1,
    shared_issue_bindings/1,
    shared_local_fold_bindings/1,
    shared_machine_support/2,
    shared_ready_bindings/1,
    shared_ready_selection_call/1,
    shared_result_retirement_head/1,
    shared_service_helpers/1
]).

-type reductions() :: none | map().

-spec direct_after_failed(reductions(), pos_integer()) -> iodata().
direct_after_failed(none, _Capacity) ->
    "  } else if machine.enter_pending {\n";
direct_after_failed(_Reductions, Capacity) ->
    [
        "  } else if machine.reduction.status == ",
        "ReductionStatus::COMPLETE {\n",
        "    let completed = reduction_dispatch_completion(\n",
        "      machine.reduction, machine.phase, machine.data);\n",
        "    let invalid_repeat = completed.repeat_phase &&\n",
        "      (completed.directive != Directive::CONSUME ||\n",
        "       completed.phase != machine.phase);\n",
        "    let effective = completed.dispatched && !invalid_repeat;\n",
        "    let phase_boundary = effective &&\n",
        "      completed.directive != Directive::FAIL &&\n",
        "      (completed.phase != machine.phase ||\n",
        "       completed.repeat_phase);\n",
        "    let failed = !completed.dispatched || invalid_repeat ||\n",
        "      (effective && completed.directive == Directive::FAIL);\n",
        "    let reserve = !failed && !machine.admission_pending &&\n",
        "      machine.occupied < MAILBOX_CAPACITY;\n",
        "    let next_machine = Machine {\n",
        "      phase: if effective { completed.phase }\n",
        "        else { machine.phase },\n",
        "      entered_from: if phase_boundary { machine.phase }\n",
        "        else { machine.entered_from },\n",
        "      data: if effective { completed.data } else { machine.data },\n",
        "      reduction: completed.reduction,\n",
        "      slots: if phase_boundary { ",
        direct_unblocked_slots(Capacity, "machine.slots"),
        " } else { machine.slots },\n",
        "      enter_pending: phase_boundary && !failed,\n",
        "      admission_pending: machine.admission_pending || reserve,\n",
        "      failed,\n",
        "      ..machine\n",
        "    };\n",
        "    MachineStep {\n",
        "      machine: next_machine,\n",
        "      admission_valid: reserve,\n",
        "      ..zero!<MachineStep>()\n",
        "    }\n",
        "  } else if machine.enter_pending {\n"
    ].

direct_unblocked_slots(Capacity, Slots) ->
    [
        "[",
        join_with(", ", [
            [
                "MailboxSlot { postponed: u1:0, ..", Slots, "[",
                integer_to_list(Index), "] }"
            ]
            || Index <- lists:seq(0, Capacity - 1)
        ]),
        "]"
    ].

-spec direct_dispatch_bindings(reductions()) -> iodata().
direct_dispatch_bindings(none) ->
    [
        "      let (next_phase, next_data, directive, repeat_phase) =\n",
        "        if dispatchable {\n",
        "          dispatch(selected_frame, machine.phase, machine.data)\n",
        "        } else {\n",
        "          (machine.phase, machine.data, Directive::CONSUME, u1:0)\n",
        "        };\n"
    ];
direct_dispatch_bindings(_Reductions) ->
    [
        "      let contribution = reduction_contribution(\n",
        "        selected_frame, machine.phase, machine.data);\n",
        "      let reduction_applied = reduction_apply(\n",
        "        machine.reduction, contribution);\n",
        "      let reduction_candidate = dispatchable &&\n",
        "        reduction_applied.outcome != ReductionOutcome::NOT_CANDIDATE;\n",
        "      let reduction_mismatch = reduction_candidate &&\n",
        "        reduction_applied.outcome == ReductionOutcome::MISMATCH;\n",
        "      let reduction_accepted = reduction_candidate &&\n",
        "        (reduction_applied.outcome == ReductionOutcome::PENDING ||\n",
        "         reduction_applied.outcome == ReductionOutcome::COMPLETE);\n",
        "      let (next_phase, next_data, directive, repeat_phase) =\n",
        "        if !dispatchable {\n",
        "          (machine.phase, machine.data, Directive::CONSUME, u1:0)\n",
        "        } else if !reduction_candidate {\n",
        "          dispatch(selected_frame, machine.phase, machine.data)\n",
        "        } else if reduction_mismatch {\n",
        "          (machine.phase, machine.data, Directive::POSTPONE, u1:0)\n",
        "        } else if reduction_accepted {\n",
        "          (machine.phase, machine.data, Directive::CONSUME, u1:0)\n",
        "        } else {\n",
        "          (machine.phase, machine.data, Directive::FAIL, u1:0)\n",
        "        };\n",
        "      let next_reduction = if reduction_accepted {\n",
        "        reduction_applied.state\n",
        "      } else { machine.reduction };\n"
    ].

-spec direct_failed_binding(reductions()) -> iodata().
direct_failed_binding(none) ->
    [
        "      let failed = invalid_input || invalid_repeat ||\n",
        "        (effective && directive == Directive::FAIL);\n"
    ];
direct_failed_binding(_Reductions) ->
    [
        "      let failed = invalid_input || invalid_repeat ||\n",
        "        incomplete_boundary ||\n",
        "        (effective && directive == Directive::FAIL);\n"
    ].

-spec direct_effective_binding(reductions()) -> iodata().
direct_effective_binding(none) ->
    "      let effective = dispatchable && !invalid_repeat;\n";
direct_effective_binding(_Reductions) ->
    [
        "      let callback_effective = dispatchable && !invalid_repeat;\n",
        "      let requested_boundary = callback_effective &&\n",
        "        (next_phase != machine.phase || repeat_phase);\n",
        "      let incomplete_boundary = requested_boundary &&\n",
        "        directive != Directive::FAIL &&\n",
        "        machine.reduction.status == ReductionStatus::OPEN;\n",
        "      let effective = callback_effective &&\n",
        "        !incomplete_boundary;\n"
    ].

-spec direct_reduction_update_field(reductions()) -> iodata().
direct_reduction_update_field(none) -> [];
direct_reduction_update_field(_Reductions) ->
    "        reduction: next_reduction,\n".

-spec direct_entry_open_bindings(reductions()) -> iodata().
direct_entry_open_bindings(none) -> [];
direct_entry_open_bindings(_Reductions) ->
    [
        "    let opens_reduction = reduction_phase_opens(machine.phase);\n",
        "    let invalid_reduction_open = opens_reduction &&\n",
        "      machine.reduction.status != ReductionStatus::IDLE;\n",
        "    let entered_reduction = if opens_reduction {\n",
        "      reduction_open(\n",
        "        machine.entered_from, machine.phase, machine.data)\n",
        "    } else { machine.reduction };\n"
    ].

-spec direct_entry_can_advance(reductions()) -> iodata().
direct_entry_can_advance(none) ->
    "    let can_advance = !emit_effect || egress_ready;\n";
direct_entry_can_advance(_Reductions) ->
    [
        "    let can_advance = (!emit_effect || egress_ready) &&\n",
        "      !invalid_reduction_open;\n"
    ].

-spec direct_entry_reduction_field(reductions()) -> iodata().
direct_entry_reduction_field(none) -> [];
direct_entry_reduction_field(_Reductions) ->
    [
        "      reduction: if entry_complete { entered_reduction }\n",
        "        else { machine.reduction },\n"
    ].

-spec direct_entry_failed_field(reductions()) -> iodata().
direct_entry_failed_field(none) -> [];
direct_entry_failed_field(_Reductions) ->
    "      failed: invalid_reduction_open,\n".

-spec direct_entry_machine_selection(reductions()) -> iodata().
direct_entry_machine_selection(none) ->
    "      machine: if can_advance { advanced_machine } else { machine },\n";
direct_entry_machine_selection(_Reductions) ->
    [
        "      machine: if can_advance || invalid_reduction_open {\n",
        "        advanced_machine\n",
        "      } else { machine },\n"
    ].

-spec direct_entry_egress_valid(reductions()) -> iodata().
direct_entry_egress_valid(none) ->
    "      egress_valid: emit_effect && can_advance,\n";
direct_entry_egress_valid(_Reductions) ->
    [
        "      egress_valid: emit_effect && can_advance &&\n",
        "        !invalid_reduction_open,\n"
    ].

-spec direct_receive_gate(reductions()) -> iodata().
direct_receive_gate(none) -> [];
direct_receive_gate(_Reductions) ->
    " &&\n      machine.reduction.status != ReductionStatus::COMPLETE".

-spec shared_machine_support(reductions(), iodata()) -> iodata().
shared_machine_support(none, _TagOk) -> [];
shared_machine_support(Reductions, TagOk) ->
    [
        shared_reduction_mailbox_step(Reductions, TagOk),
        shared_machine_complete_function(Reductions)
    ].

shared_reduction_mailbox_step(none, _TagOk) -> [];
shared_reduction_mailbox_step(_Reductions, TagOk) ->
    [
        "struct ReductionMailboxStep {\n",
        "  machine: SharedMachine,\n",
        "  valid: u1,\n",
        "  directive: Directive,\n",
        "}\n\n",
        "fn shared_reduction_mailbox_step(\n",
        "    machine: SharedMachine, frame: axis::Frame, received: u1)\n",
        "    -> ReductionMailboxStep {\n",
        "  let tag_ok = ", TagOk, ";\n",
        "  let contribution = reduction_contribution(\n",
        "    frame, machine.phase, machine.data);\n",
        "  let applied = reduction_apply(machine.reduction, contribution);\n",
        "  let candidate = received && tag_ok &&\n",
        "    !machine.failed && !machine.enter_pending &&\n",
        "    applied.outcome != ReductionOutcome::NOT_CANDIDATE;\n",
        "  let mismatch = candidate &&\n",
        "    applied.outcome == ReductionOutcome::MISMATCH;\n",
        "  let accepted = candidate &&\n",
        "    (applied.outcome == ReductionOutcome::PENDING ||\n",
        "     applied.outcome == ReductionOutcome::COMPLETE);\n",
        "  let failed = candidate && !mismatch && !accepted;\n",
        "  let next_machine = SharedMachine {\n",
        "    reduction: if accepted { applied.state }\n",
        "      else { machine.reduction },\n",
        "    failed: machine.failed || failed,\n",
        "    ..machine\n",
        "  };\n",
        "  ReductionMailboxStep {\n",
        "    machine: next_machine,\n",
        "    valid: candidate,\n",
        "    directive: if mismatch { Directive::POSTPONE }\n",
        "      else if accepted { Directive::CONSUME }\n",
        "      else { Directive::FAIL },\n",
        "  }\n",
        "}\n\n"
    ].

shared_machine_complete_function(none) -> [];
shared_machine_complete_function(_Reductions) ->
    [
        "fn shared_machine_complete(machine: SharedMachine)\n",
        "    -> SharedDispatch {\n",
        "  let valid = !machine.failed && !machine.enter_pending &&\n",
        "    machine.reduction.status == ReductionStatus::COMPLETE;\n",
        "  if !valid {\n",
        "    SharedDispatch {\n",
        "      machine: SharedMachine { failed: u1:1, ..machine },\n",
        "      directive: Directive::FAIL,\n",
        "      dispatched: u1:1,\n",
        "      ..zero!<SharedDispatch>()\n",
        "    }\n",
        "  } else {\n",
        "    let completed = reduction_dispatch_completion(\n",
        "      machine.reduction, machine.phase, machine.data);\n",
        "    let invalid_repeat = completed.repeat_phase &&\n",
        "      (completed.directive != Directive::CONSUME ||\n",
        "       completed.phase != machine.phase);\n",
        "    let effective = completed.dispatched && !invalid_repeat;\n",
        "    let phase_boundary = effective &&\n",
        "      completed.directive != Directive::FAIL &&\n",
        "      (completed.phase != machine.phase ||\n",
        "       completed.repeat_phase);\n",
        "    let failed = !completed.dispatched || invalid_repeat ||\n",
        "      (effective && completed.directive == Directive::FAIL);\n",
        "    let next_machine = SharedMachine {\n",
        "      phase: if effective { completed.phase }\n",
        "        else { machine.phase },\n",
        "      entered_from: if phase_boundary { machine.phase }\n",
        "        else { machine.entered_from },\n",
        "      data: if effective { completed.data } else { machine.data },\n",
        "      reduction: completed.reduction,\n",
        "      enter_pending: phase_boundary && !failed,\n",
        "      failed,\n",
        "      ..machine\n",
        "    };\n",
        "    SharedDispatch {\n",
        "      machine: next_machine,\n",
        "      dispatched: completed.dispatched && !invalid_repeat,\n",
        "      directive: completed.directive,\n",
        "      phase_boundary,\n",
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

-spec shared_dispatch_effective_binding(reductions()) -> iodata().
shared_dispatch_effective_binding(none) ->
    "    let effective = tag_ok && !invalid_repeat;\n";
shared_dispatch_effective_binding(_Reductions) ->
    [
        "    let callback_effective = tag_ok && !invalid_repeat;\n",
        "    let requested_boundary = callback_effective &&\n",
        "      (next_phase != machine.phase || repeat_phase);\n",
        "    let incomplete_boundary = requested_boundary &&\n",
        "      directive != Directive::FAIL &&\n",
        "      machine.reduction.status == ReductionStatus::OPEN;\n",
        "    let effective = callback_effective &&\n",
        "      !incomplete_boundary;\n"
    ].

-spec shared_dispatch_failed_binding(reductions()) -> iodata().
shared_dispatch_failed_binding(none) ->
    [
        "    let failed = !tag_ok || invalid_repeat ||\n",
        "      (effective && directive == Directive::FAIL);\n"
    ];
shared_dispatch_failed_binding(_Reductions) ->
    [
        "    let failed = !tag_ok || invalid_repeat ||\n",
        "      incomplete_boundary ||\n",
        "      (effective && directive == Directive::FAIL);\n"
    ].

-spec shared_dispatch_dispatched_field(reductions()) -> iodata().
shared_dispatch_dispatched_field(none) ->
    "      dispatched: tag_ok && !invalid_repeat,\n";
shared_dispatch_dispatched_field(_Reductions) ->
    [
        "      dispatched: tag_ok && !invalid_repeat &&\n",
        "        !incomplete_boundary,\n"
    ].

-spec shared_entry_step(reductions()) -> iodata().
shared_entry_step(Reductions) ->
    [
        "    let (entered_data, effects) = enter(\n",
        "      machine.entered_from, machine.phase, machine.data);\n",
        "    let effects_valid = entry_effects_valid(effects);\n",
        shared_entry_open_bindings(Reductions),
        shared_entry_can_advance(Reductions),
        "    let advanced_machine = SharedMachine {\n",
        shared_entry_data_field(Reductions),
        shared_entry_reduction_field(Reductions),
        "      enter_pending: u1:0,\n",
        shared_entry_failed_field(Reductions),
        "      ..machine\n",
        "    };\n",
        "    SharedStep {\n",
        shared_entry_machine_selection(Reductions),
        "      effects,\n",
        shared_entry_effects_valid(Reductions),
        shared_entry_egress_blocked(Reductions),
        "      ..zero!<SharedStep>()\n",
        "    }\n"
    ].

shared_entry_open_bindings(none) -> [];
shared_entry_open_bindings(_Reductions) ->
    [
        "    let opens_reduction = reduction_phase_opens(machine.phase);\n",
        "    let invalid_reduction_open = opens_reduction &&\n",
        "      machine.reduction.status != ReductionStatus::IDLE;\n",
        "    let entered_reduction = if opens_reduction {\n",
        "      reduction_open(\n",
        "        machine.entered_from, machine.phase, machine.data)\n",
        "    } else { machine.reduction };\n"
    ].

shared_entry_can_advance(none) ->
    "    let can_advance = !effects_valid || egress_ready;\n";
shared_entry_can_advance(_Reductions) ->
    [
        "    let can_advance = (!effects_valid || egress_ready) &&\n",
        "      !invalid_reduction_open;\n"
    ].

shared_entry_reduction_field(none) -> [];
shared_entry_reduction_field(_Reductions) ->
    [
        "      reduction: if invalid_reduction_open { machine.reduction }\n",
        "        else { entered_reduction },\n"
    ].

shared_entry_data_field(none) ->
    "      data: entered_data,\n";
shared_entry_data_field(_Reductions) ->
    [
        "      data: if invalid_reduction_open { machine.data }\n",
        "        else { entered_data },\n"
    ].

shared_entry_failed_field(none) -> [];
shared_entry_failed_field(_Reductions) ->
    "      failed: invalid_reduction_open,\n".

shared_entry_machine_selection(none) ->
    "      machine: if can_advance { advanced_machine } else { machine },\n";
shared_entry_machine_selection(_Reductions) ->
    [
        "      machine: if can_advance || invalid_reduction_open {\n",
        "        advanced_machine\n",
        "      } else { machine },\n"
    ].

shared_entry_effects_valid(none) ->
    "      effects_valid: effects_valid && can_advance,\n";
shared_entry_effects_valid(_Reductions) ->
    [
        "      effects_valid: effects_valid && can_advance &&\n",
        "        !invalid_reduction_open,\n"
    ].

shared_entry_egress_blocked(none) ->
    "      egress_blocked: effects_valid && !egress_ready,\n";
shared_entry_egress_blocked(_Reductions) ->
    [
        "      egress_blocked: effects_valid && !egress_ready &&\n",
        "        !invalid_reduction_open,\n"
    ].

-spec shared_executor_dispatch(reductions()) -> iodata().
shared_executor_dispatch(none) ->
    [
        "\n  let dispatched = shared_machine_dispatch(\n",
        "    machine, request.frame, request.received);\n"
    ];
shared_executor_dispatch(_Reductions) ->
    [
        "\n  let dispatched = if request.internal {\n",
        "    shared_machine_complete(machine)\n",
        "  } else {\n",
        "    shared_machine_dispatch(\n",
        "      machine, request.frame, request.received)\n",
        "  };\n"
    ].

-spec shared_service_helpers(reductions()) -> iodata().
shared_service_helpers(none) -> [];
shared_service_helpers(_Reductions) ->
    """
    // Reduction completion is private actor work. It takes priority over
    // that actor's entry or mailbox work, while round-robin selection across
    // distinct actors remains unchanged.
    fn reduction_ready_selection<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        cursor: u32,
        in_flight: u1[ACTOR_COUNT]) -> (u1, u32) {
      let (after_found, after_slot, before_found, before_slot) =
          unroll_for! (slot, acc):
              (u32, (u1, u32, u1, u32)) in u32:0..ACTOR_COUNT {
        let internal_active = state.internal_candidates[slot];
        let entry_active =
          state.entry_probes[slot] || state.egress_waiters[slot];
        let ready = internal_active || (!internal_active && (
          state.entry_probes[slot] ||
          (state.mail_candidates[slot] && !entry_active) ||
          (state.egress_waiters[slot] && !state.egress_busy)));
        let selectable = ready && !in_flight[slot];
        let take_after = !acc.0 && slot >= cursor && selectable;
        let take_before = !acc.2 && slot < cursor && selectable;
        (
          acc.0 || take_after,
          if take_after { slot } else { acc.1 },
          acc.2 || take_before,
          if take_before { slot } else { acc.3 }
        )
      }((u1:0, u32:0, u1:0, u32:0));
      (
        after_found || before_found,
        if after_found { after_slot } else { before_slot }
      )
    }

    // While an effect-bearing result waits for credit, only mailbox heads
    // can be tested locally. Each non-contribution head is tested once per
    // blocked epoch so it cannot starve a later foldable actor.
    fn reduction_blocked_selection<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        cursor: u32,
        in_flight: u1[ACTOR_COUNT],
        blocked_probed: u1[ACTOR_COUNT]) -> (u1, u32) {
      let (after_found, after_slot, before_found, before_slot) =
          unroll_for! (slot, acc):
              (u32, (u1, u32, u1, u32)) in u32:0..ACTOR_COUNT {
        let mail_only = state.mail_candidates[slot] &&
          !state.internal_candidates[slot] &&
          !state.entry_probes[slot] &&
          !state.egress_waiters[slot];
        let selectable = mail_only && !in_flight[slot] &&
          !blocked_probed[slot];
        let take_after = !acc.0 && slot >= cursor && selectable;
        let take_before = !acc.2 && slot < cursor && selectable;
        (
          acc.0 || take_after,
          if take_after { slot } else { acc.1 },
          acc.2 || take_before,
          if take_before { slot } else { acc.3 }
        )
      }((u1:0, u32:0, u1:0, u32:0));
      (
        after_found || before_found,
        if after_found { after_slot } else { before_slot }
      )
    }

    fn retire_reduction_actor<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        valid: u1,
        slot: u32,
        machine: SharedMachine) ->
        SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      let internal_candidates = if valid {
        update(
          state.internal_candidates,
          slot,
          machine.reduction.status == ReductionStatus::COMPLETE &&
            !machine.failed)
      } else {
        state.internal_candidates
      };
      SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
        internal_candidates,
        ..state
      }
    }

    fn shared_reduction_fold_result(
        slot: u32,
        machine_bits: MachineBits,
        frame: axis::Frame,
        received: u1,
        mailbox_index: u8,
        order_index: u8) -> (u1, SharedExecutorResult) {
      let folded = shared_reduction_mailbox_step(
        machine_from_bits(machine_bits), frame, received);
      (
        folded.valid,
        SharedExecutorResult {
          slot,
          machine: bits_from_machine(folded.machine),
          effects: zero!<EntryEffects>(),
          effects_valid: u1:0,
          dispatched: folded.valid,
          directive: folded.directive,
          phase_boundary: u1:0,
          egress_blocked: u1:0,
          received,
          mailbox_index,
          order_index,
        }
      )
    }

    """.

-spec shared_executor_internal_request_field(reductions()) -> iodata().
shared_executor_internal_request_field(none) -> "\n";
shared_executor_internal_request_field(_Reductions) ->
    "\n              internal: internal_active,\n".

-spec shared_ready_selection_call(reductions()) -> iodata().
shared_ready_selection_call(none) ->
    [
        " ready_selection(\n",
        "          selection_state,\n",
        "          cursor,\n",
        "          issued_in_flight);\n"
    ];
shared_ready_selection_call(_Reductions) ->
    ["\n", """
              reduction_ready_selection(
                selection_state,
                cursor,
                issued_in_flight);
    """, "\n"].

-spec shared_local_fold_bindings(reductions()) -> iodata().
shared_local_fold_bindings(none) -> "\n";
shared_local_fold_bindings(_Reductions) ->
    ["\n", """
            let (local_fold_valid, local_fold) =
              shared_reduction_fold_result(
                read_slot,
                response.data,
                frame,
                read_mailbox && received,
                mailbox_index,
                order_index);
    """, "\n"].

-spec shared_blocked_probe_bindings(reductions()) -> iodata().
shared_blocked_probe_bindings(none) -> [];
shared_blocked_probe_bindings(_Reductions) ->
    ["\n", """
            let blocked_nonfold = completion_blocked && issue_valid &&
              !local_fold_valid;
            let final_in_flight = if blocked_nonfold {
              update(issued_in_flight, read_slot, u1:0)
            } else {
              issued_in_flight
            };
            let blocked_probed = if !completion_blocked {
              zero!<u1[ACTOR_COUNT]>()
            } else if blocked_nonfold {
              update(state.blocked_probed, read_slot, u1:1)
            } else {
              state.blocked_probed
            };
            let (blocked_ready, blocked_slot) =
              reduction_blocked_selection(
                selection_state,
                cursor,
                final_in_flight,
                blocked_probed);
            let ready = if completion_blocked {
              blocked_ready
            } else {
              selected_ready
            };
            let next_slot = if completion_blocked {
              blocked_slot
            } else {
              selected_slot
            };
    """, "\n"].

-spec shared_ready_bindings(reductions()) -> iodata().
shared_ready_bindings(none) ->
    ["""
            let ready = if completion_blocked {
              state.next_valid
            } else {
              selected_ready
            };
            let next_slot = if completion_blocked {
              state.next_slot
            } else {
              selected_slot
            };
    """, "\n"];
shared_ready_bindings(_Reductions) -> [].

-spec shared_executor_send_condition(reductions()) -> iodata().
shared_executor_send_condition(none) ->
    "\n          issue_valid,\n";
shared_executor_send_condition(_Reductions) ->
    "\n          issue_valid && !completion_blocked && !local_fold_valid,\n".

-spec shared_in_flight_field(reductions()) -> iodata().
shared_in_flight_field(none) ->
    "\n          in_flight: issued_in_flight,\n";
shared_in_flight_field(_Reductions) ->
    "              in_flight: final_in_flight,\n".

-spec shared_folded_state_fields(reductions()) -> iodata().
shared_folded_state_fields(none) -> "\n";
shared_folded_state_fields(_Reductions) ->
    ["\n", """
              folded_valid: local_fold_valid ||
                (state.folded_valid && !fold_retire_valid),
              folded: if local_fold_valid {
                local_fold
              } else {
                state.folded
              },
              blocked_probed,
    """, "\n"].

-spec shared_result_retirement_head(reductions()) -> iodata().
shared_result_retirement_head(none) ->
    ["\n", """
            let buffered_can_retire = state.completed_valid &&
              (!state.completed.effects_valid || !credit_busy);
            let accept_executor_result =
              !state.completed_valid || buffered_can_retire;
            let (executor_result_tok, incoming_result, incoming_valid) =
              recv_if_non_blocking(
                capture_tok,
                executor_result_in,
                accept_executor_result,
                zero!<SharedExecutorResult>());
            let result = if state.completed_valid {
              state.completed
            } else {
              incoming_result
            };
            let result_valid = state.completed_valid || incoming_valid;
            let retire_valid = result_valid &&
              (!result.effects_valid || !credit_busy);
            let resolved = SharedStep {
              machine: machine_from_bits(result.machine),
              effects: result.effects,
              effects_valid: result.effects_valid,
              dispatched: result.dispatched,
              directive: result.directive,
              phase_boundary: result.phase_boundary,
              egress_blocked: result.egress_blocked,
            };
            let credited = SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
              pending: captured_pending,
              pending_valid: credit_pending_valid,
              egress_busy: credit_busy ||
                (retire_valid && result.effects_valid),
              ..state
            };
            let retired = retire_actor(
              credited,
              retire_valid,
              result.slot,
              resolved,
              result.received,
              result.mailbox_index,
              result.order_index);
            let retired_in_flight = if retire_valid {
              update(retired.in_flight, result.slot, u1:0)
            } else {
              retired.in_flight
            };
            let completed_valid = if state.completed_valid {
              if buffered_can_retire { incoming_valid } else { u1:1 }
            } else {
              incoming_valid && !retire_valid
            };
            let completed = if state.completed_valid {
              if buffered_can_retire { incoming_result } else { state.completed }
            } else {
              incoming_result
            };
    """, "\n"];
shared_result_retirement_head(_Reductions) ->
    ["\n", """
            // A retireable executor result wins this single RAM write port.
            // A result blocked on an unrelated effect credit does not fence a
            // local fold: the selected actor's in-flight bit proves that no
            // older activation for that same actor can still be outstanding.
            let buffered_can_retire = state.completed_valid &&
              (!state.completed.effects_valid || !credit_busy);
            let accept_executor_result =
              !state.completed_valid || buffered_can_retire;
            let (executor_result_tok, incoming_result, incoming_valid) =
              recv_if_non_blocking(
                capture_tok,
                executor_result_in,
                accept_executor_result,
                zero!<SharedExecutorResult>());
            let ordinary_result = if state.completed_valid {
              state.completed
            } else {
              incoming_result
            };
            let ordinary_result_valid =
              state.completed_valid || incoming_valid;
            let ordinary_retire_valid = ordinary_result_valid &&
              (!ordinary_result.effects_valid || !credit_busy);
            let fold_retire_valid = state.folded_valid &&
              !ordinary_retire_valid;
            let result = if ordinary_retire_valid {
              ordinary_result
            } else {
              state.folded
            };
            let retire_valid =
              ordinary_retire_valid || fold_retire_valid;
            let resolved = SharedStep {
              machine: machine_from_bits(result.machine),
              effects: result.effects,
              effects_valid: result.effects_valid,
              dispatched: result.dispatched,
              directive: result.directive,
              phase_boundary: result.phase_boundary,
              egress_blocked: result.egress_blocked,
            };
            let credited = SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
              pending: captured_pending,
              pending_valid: credit_pending_valid,
              egress_busy: credit_busy ||
                (retire_valid && result.effects_valid),
              ..state
            };
            let retired0 = retire_actor(
              credited,
              retire_valid,
              result.slot,
              resolved,
              result.received,
              result.mailbox_index,
              result.order_index);
            let retired = retire_reduction_actor(
              retired0, retire_valid, result.slot, resolved.machine);
            let retired_in_flight = if retire_valid {
              update(retired.in_flight, result.slot, u1:0)
            } else {
              retired.in_flight
            };
            let completed_valid = if state.completed_valid {
              if buffered_can_retire { incoming_valid } else { u1:1 }
            } else {
              incoming_valid && !ordinary_retire_valid
            };
            let completed = if state.completed_valid {
              if buffered_can_retire { incoming_result } else { state.completed }
            } else {
              incoming_result
            };
    """, "\n"].

-spec shared_issue_bindings(reductions()) -> iodata().
shared_issue_bindings(none) ->
    ["\n", """
            let issue_valid = state.next_valid && !completion_blocked;
            let read_slot = if state.next_valid {
              state.next_slot
            } else {
              u32:0
            };
            let entry_active = state.entry_probes[read_slot] ||
              state.egress_waiters[read_slot];
            let read_mailbox =
              issue_valid &&
              state.mail_candidates[read_slot] && !entry_active;
    """, "\n"];
shared_issue_bindings(_Reductions) ->
    ["\n", """
            let fold_may_issue =
              !state.folded_valid || fold_retire_valid;
            let read_slot = if state.next_valid {
              state.next_slot
            } else {
              u32:0
            };
            let blocked_mail_only = state.mail_candidates[read_slot] &&
              !state.internal_candidates[read_slot] &&
              !state.entry_probes[read_slot] &&
              !state.egress_waiters[read_slot];
            let blocked_issue_valid = blocked_mail_only &&
              !state.blocked_probed[read_slot] &&
              !state.in_flight[read_slot];
            let issue_valid = state.next_valid && fold_may_issue &&
              (!completion_blocked || blocked_issue_valid);
            let internal_active =
              issue_valid && state.internal_candidates[read_slot];
            let entry_active = internal_active ||
              state.entry_probes[read_slot] ||
              state.egress_waiters[read_slot];
            let read_mailbox = issue_valid && !internal_active &&
              state.mail_candidates[read_slot] && !entry_active;
    """, "\n"].

join_with(_Separator, []) ->
    [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].
