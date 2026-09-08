%%%% xls_statem_reduction_service_codegen
%%%%
%%%% Splices actor-local reduction semantics into the ordinary direct and
%%%% shared state-machine services. Contributions remain ordinary mailbox
%%%% messages: both services load the actor, run the common reduction logic,
%%%% and retire the resulting actor state through their usual paths.

-module(xls_statem_reduction_service_codegen).
-moduledoc false.

-export([
    direct_after_failed/2,
    direct_dispatch_bindings/1,
    direct_effective_binding/1,
    direct_entry_bindings/1,
    direct_entry_can_advance/1,
    direct_entry_egress_valid/1,
    direct_entry_failed_field/1,
    direct_entry_machine_selection/1,
    direct_entry_reduction_field/1,
    direct_failed_binding/1,
    direct_reduction_field/1,
    direct_receive_gate/1,
    machine_decode_field/3,
    machine_encode_prefix/1,
    machine_state_copy_field/1,
    machine_state_field/1,
    shared_dispatch_bindings/1,
    shared_dispatch_dispatched_field/1,
    shared_dispatch_effective_binding/1,
    shared_dispatch_failed_binding/1,
    shared_dispatch_reduction_field/1,
    shared_entry_step/1,
    shared_executor_dispatch/1,
    shared_executor_request_field/1,
    shared_executor_request_value/1,
    shared_issue_bindings/1,
    shared_machine_support/1,
    shared_ready_selection_call/1,
    shared_retire_binding/1,
    shared_service_helpers/1,
    shared_state_fields/1
]).

-type reductions() :: none | xls_statem_reduction_ir:reduction().

%%%
%%% Stored-state and scheduler declarations
%%%

-spec machine_state_field(reductions()) -> iodata().
machine_state_field(none) ->
    [];
machine_state_field(_Reductions) ->
    "  reduction: ReductionState,\n".

-spec machine_state_copy_field(reductions()) -> iodata().
machine_state_copy_field(none) ->
    [];
machine_state_copy_field(_Reductions) ->
    "    reduction: machine.reduction,\n".

-spec machine_decode_field(reductions(), non_neg_integer(), non_neg_integer()) ->
    iodata().
machine_decode_field(none, _Start, _End) ->
    [];
machine_decode_field(_Reductions, Start, End) ->
    [
        "    reduction: reduction_state_from_bits(raw[",
        integer_to_list(Start),
        ":",
        integer_to_list(End),
        "]),\n"
    ].

-spec machine_encode_prefix(reductions()) -> iodata().
machine_encode_prefix(none) ->
    [];
machine_encode_prefix(_Reductions) ->
    "  bits_from_reduction_state(machine.reduction) ++\n".

-spec shared_state_fields(reductions()) -> iodata().
shared_state_fields(none) ->
    [];
shared_state_fields(_Reductions) ->
    [
        "  // Private completion events outrank entry and mailbox work for\n",
        "  // the same actor, but retain round-robin fairness across actors.\n",
        "  internal_candidates: u1[ACTOR_COUNT],\n"
    ].

-spec shared_executor_request_field(reductions()) -> iodata().
shared_executor_request_field(none) ->
    [];
shared_executor_request_field(_Reductions) ->
    "  internal: u1,\n".

%%%
%%% Direct Service
%%%

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
                "MailboxSlot { postponed: u1:0, ..",
                Slots,
                "[",
                integer_to_list(Index),
                "] }"
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
        "          (machine.phase, machine.data, ",
        "Directive::CONSUME, u1:0)\n",
        "        };\n"
    ];
direct_dispatch_bindings(_Reductions) ->
    [
        "      let contribution = reduction_contribution(\n",
        "        selected_frame, machine.phase, machine.data);\n",
        "      let reduction_applied = reduction_apply(\n",
        "        machine.reduction, contribution);\n",
        "      let reduction_candidate = dispatchable &&\n",
        "        reduction_applied.outcome != ",
        "ReductionOutcome::NOT_CANDIDATE;\n",
        "      let reduction_mismatch = reduction_candidate &&\n",
        "        reduction_applied.outcome == ReductionOutcome::MISMATCH;\n",
        "      let reduction_accepted = reduction_candidate &&\n",
        "        (reduction_applied.outcome == ReductionOutcome::PENDING ||\n",
        "         reduction_applied.outcome == ",
        "ReductionOutcome::COMPLETE);\n",
        "      let (next_phase, next_data, directive, repeat_phase) =\n",
        "        if !dispatchable {\n",
        "          (machine.phase, machine.data, ",
        "Directive::CONSUME, u1:0)\n",
        "        } else if !reduction_candidate {\n",
        "          dispatch(selected_frame, machine.phase, machine.data)\n",
        "        } else if reduction_mismatch {\n",
        "          (machine.phase, machine.data, ",
        "Directive::POSTPONE, u1:0)\n",
        "        } else if reduction_accepted {\n",
        "          (machine.phase, machine.data, ",
        "Directive::CONSUME, u1:0)\n",
        "        } else {\n",
        "          (machine.phase, machine.data, Directive::FAIL, u1:0)\n",
        "        };\n",
        "      let next_reduction = if reduction_accepted {\n",
        "        reduction_applied.state\n",
        "      } else { machine.reduction };\n"
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

-spec direct_reduction_field(reductions()) -> iodata().
direct_reduction_field(none) ->
    [];
direct_reduction_field(_Reductions) ->
    "        reduction: next_reduction,\n".

-spec direct_entry_bindings(reductions()) -> iodata().
direct_entry_bindings(none) ->
    [];
direct_entry_bindings(_Reductions) ->
    [
        "    let opens_reduction = reduction_phase_opens(machine.phase);\n",
        "    let invalid_reduction_open =\n",
        "      opens_reduction &&\n",
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
direct_entry_reduction_field(none) ->
    [];
direct_entry_reduction_field(_Reductions) ->
    [
        "      reduction: if entry_complete { entered_reduction }\n",
        "        else { machine.reduction },\n"
    ].

-spec direct_entry_failed_field(reductions()) -> iodata().
direct_entry_failed_field(none) ->
    [];
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
direct_receive_gate(none) ->
    [];
direct_receive_gate(_Reductions) ->
    [
        " &&\n",
        "      machine.reduction.status != ReductionStatus::COMPLETE"
    ].

%%%
%%% SharedService actor execution
%%%

-spec shared_machine_support(reductions()) -> iodata().
shared_machine_support(none) ->
    [];
shared_machine_support(_Reductions) ->
    """
    fn shared_machine_complete(machine: SharedMachine) -> SharedDispatch {
      let valid = !machine.failed && !machine.enter_pending &&
        machine.reduction.status == ReductionStatus::COMPLETE;
      if !valid {
        SharedDispatch {
          machine: SharedMachine { failed: u1:1, ..machine },
          directive: Directive::FAIL,
          dispatched: u1:1,
          ..zero!<SharedDispatch>()
        }
      } else {
        let completed = reduction_dispatch_completion(
          machine.reduction, machine.phase, machine.data);
        let invalid_repeat = completed.repeat_phase &&
          (completed.directive != Directive::CONSUME ||
           completed.phase != machine.phase);
        let effective = completed.dispatched && !invalid_repeat;
        let phase_boundary = effective &&
          completed.directive != Directive::FAIL &&
          (completed.phase != machine.phase || completed.repeat_phase);
        let failed = !completed.dispatched || invalid_repeat ||
          (effective && completed.directive == Directive::FAIL);
        let next_machine = SharedMachine {
          phase: if effective { completed.phase } else { machine.phase },
          entered_from: if phase_boundary {
            machine.phase
          } else { machine.entered_from },
          data: if effective { completed.data } else { machine.data },
          reduction: completed.reduction,
          enter_pending: phase_boundary && !failed,
          failed,
          ..machine
        };
        SharedDispatch {
          machine: next_machine,
          dispatched: completed.dispatched && !invalid_repeat,
          directive: completed.directive,
          phase_boundary,
          ..zero!<SharedDispatch>()
        }
      }
    }

    """.

-spec shared_dispatch_bindings(reductions()) -> iodata().
shared_dispatch_bindings(none) ->
    [
        "    let (next_phase, next_data, directive, repeat_phase) =\n",
        "      if tag_ok {\n",
        "        dispatch(frame, machine.phase, machine.data)\n",
        "      } else {\n",
        "        (machine.phase, machine.data, Directive::FAIL, u1:0)\n",
        "      };\n"
    ];
shared_dispatch_bindings(_Reductions) ->
    [
        "    let contribution = reduction_contribution(\n",
        "      frame, machine.phase, machine.data);\n",
        "    let reduction_applied = reduction_apply(\n",
        "      machine.reduction, contribution);\n",
        "    let reduction_candidate = tag_ok &&\n",
        "      reduction_applied.outcome != ",
        "ReductionOutcome::NOT_CANDIDATE;\n",
        "    let reduction_mismatch = reduction_candidate &&\n",
        "      reduction_applied.outcome == ReductionOutcome::MISMATCH;\n",
        "    let reduction_accepted = reduction_candidate &&\n",
        "      (reduction_applied.outcome == ReductionOutcome::PENDING ||\n",
        "       reduction_applied.outcome == ReductionOutcome::COMPLETE);\n",
        "    let (next_phase, next_data, directive, repeat_phase) =\n",
        "      if !tag_ok {\n",
        "        (machine.phase, machine.data, Directive::FAIL, u1:0)\n",
        "      } else if !reduction_candidate {\n",
        "        dispatch(frame, machine.phase, machine.data)\n",
        "      } else if reduction_mismatch {\n",
        "        (machine.phase, machine.data, ",
        "Directive::POSTPONE, u1:0)\n",
        "      } else if reduction_accepted {\n",
        "        (machine.phase, machine.data, ",
        "Directive::CONSUME, u1:0)\n",
        "      } else {\n",
        "        (machine.phase, machine.data, Directive::FAIL, u1:0)\n",
        "      };\n",
        "    let next_reduction = if reduction_accepted {\n",
        "      reduction_applied.state\n",
        "    } else { machine.reduction };\n"
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

-spec shared_dispatch_reduction_field(reductions()) -> iodata().
shared_dispatch_reduction_field(none) ->
    [];
shared_dispatch_reduction_field(_Reductions) ->
    "      reduction: next_reduction,\n".

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
        shared_entry_bindings(Reductions),
        shared_entry_can_advance(Reductions),
        "    let advanced_machine = SharedMachine {\n",
        shared_entry_data_field(Reductions),
        shared_entry_reduction_field(Reductions),
        "      enter_pending: u1:0,\n",
        shared_entry_failed_field(Reductions),
        "      ..machine\n",
        "    };\n",
        "    SharedStep {\n",
        shared_entry_machine_field(Reductions),
        "      effects,\n",
        shared_entry_effects_valid_field(Reductions),
        shared_entry_egress_blocked_field(Reductions),
        "      ..zero!<SharedStep>()\n",
        "    }\n"
    ].

shared_entry_bindings(none) ->
    [];
shared_entry_bindings(_Reductions) ->
    [
        "    let opens_reduction = reduction_phase_opens(machine.phase);\n",
        "    let invalid_reduction_open =\n",
        "      opens_reduction &&\n",
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

shared_entry_data_field(none) ->
    "      data: entered_data,\n";
shared_entry_data_field(_Reductions) ->
    [
        "      data: if invalid_reduction_open { machine.data }\n",
        "        else { entered_data },\n"
    ].

shared_entry_reduction_field(none) ->
    [];
shared_entry_reduction_field(_Reductions) ->
    [
        "      reduction: if invalid_reduction_open { machine.reduction }\n",
        "        else { entered_reduction },\n"
    ].

shared_entry_failed_field(none) ->
    [];
shared_entry_failed_field(_Reductions) ->
    "      failed: invalid_reduction_open,\n".

shared_entry_machine_field(none) ->
    "      machine: if can_advance { advanced_machine } else { machine },\n";
shared_entry_machine_field(_Reductions) ->
    [
        "      machine: if can_advance || invalid_reduction_open {\n",
        "        advanced_machine\n",
        "      } else { machine },\n"
    ].

shared_entry_effects_valid_field(none) ->
    "      effects_valid: effects_valid && can_advance,\n";
shared_entry_effects_valid_field(_Reductions) ->
    [
        "      effects_valid: effects_valid && can_advance &&\n",
        "        !invalid_reduction_open,\n"
    ].

shared_entry_egress_blocked_field(none) ->
    "      egress_blocked: effects_valid && !egress_ready,\n";
shared_entry_egress_blocked_field(_Reductions) ->
    [
        "      egress_blocked: effects_valid && !egress_ready &&\n",
        "        !invalid_reduction_open,\n"
    ].

-spec shared_executor_dispatch(reductions()) -> iodata().
shared_executor_dispatch(none) ->
    [
        "  let dispatched = shared_machine_dispatch(\n",
        "    machine, request.frame, request.received);\n"
    ];
shared_executor_dispatch(_Reductions) ->
    [
        "  let dispatched = if request.internal {\n",
        "    shared_machine_complete(machine)\n",
        "  } else {\n",
        "    shared_machine_dispatch(\n",
        "      machine, request.frame, request.received)\n",
        "  };\n"
    ].

%%%
%%% SharedService scheduling
%%%

-spec shared_service_helpers(reductions()) -> iodata().
shared_service_helpers(none) ->
    [];
shared_service_helpers(_Reductions) ->
    """
    fn reduction_ready_selection<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        cursor: u32,
        in_flight: u1[ACTOR_COUNT]) -> (u1, u32) {
      let (after_found, after_slot, before_found, before_slot) =
          unroll_for! (slot, acc):
              (u32, (u1, u32, u1, u32)) in u32:0..ACTOR_COUNT {
        let internal_active = state.internal_candidates[slot];
        let entry_active = state.entry_probes[slot] ||
          state.egress_waiters[slot];
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

    """.

-spec shared_retire_binding(reductions()) -> iodata().
shared_retire_binding(none) ->
    [
        "        let retired = retire_actor(\n",
        "          credited,\n",
        "          retire_valid,\n",
        "          result.slot,\n",
        "          resolved,\n",
        "          result.received,\n",
        "          result.mailbox_index,\n",
        "          result.order_index);\n"
    ];
shared_retire_binding(_Reductions) ->
    "        let retired = retire_reduction_actor(\n"
    "          retire_actor(\n"
    "            credited, retire_valid, result.slot, resolved,\n"
    "            result.received, result.mailbox_index,\n"
    "            result.order_index),\n"
    "          retire_valid, result.slot, resolved.machine);\n".

-spec shared_issue_bindings(reductions()) -> iodata().
shared_issue_bindings(none) ->
    [
        "        let issue_valid = state.next_valid && !completion_blocked;\n",
        "        let read_slot = if state.next_valid {\n",
        "          state.next_slot\n",
        "        } else {\n",
        "          u32:0\n",
        "        };\n",
        "        let entry_active = state.entry_probes[read_slot] ||\n",
        "          state.egress_waiters[read_slot];\n",
        "        let read_mailbox =\n",
        "          issue_valid &&\n",
        "          state.mail_candidates[read_slot] && !entry_active;\n"
    ];
shared_issue_bindings(_Reductions) ->
    [
        "        let issue_valid =\n",
        "          state.next_valid && !completion_blocked;\n",
        "        let read_slot = if state.next_valid {\n",
        "          state.next_slot\n",
        "        } else { u32:0 };\n",
        "        let internal_active = issue_valid &&\n",
        "          state.internal_candidates[read_slot];\n",
        "        let entry_active = internal_active ||\n",
        "          state.entry_probes[read_slot] ||\n",
        "          state.egress_waiters[read_slot];\n",
        "        let read_mailbox = issue_valid && !internal_active &&\n",
        "          state.mail_candidates[read_slot] && !entry_active;\n"
    ].

-spec shared_ready_selection_call(reductions()) -> iodata().
shared_ready_selection_call(none) ->
    [
        " ready_selection(\n",
        "          selection_state,\n",
        "          cursor,\n",
        "          issued_in_flight);\n"
    ];
shared_ready_selection_call(_Reductions) ->
    [
        " reduction_ready_selection(\n",
        "          selection_state, cursor, issued_in_flight);\n"
    ].

-spec shared_executor_request_value(reductions()) -> iodata().
shared_executor_request_value(none) ->
    [];
shared_executor_request_value(_Reductions) ->
    "              internal: internal_active,\n".

join_with(_Separator, []) ->
    [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].
