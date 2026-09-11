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
    direct_entry_reduction_field/1,
    direct_failed_binding/1,
    direct_reduction_field/1,
    direct_receive_gate/1,
    machine_decode_field/3,
    machine_encode_prefix/1,
    machine_state_copy_field/1,
    machine_state_field/1,
    shared_capture/2,
    shared_capture_token/2,
    shared_config_endpoint/2,
    shared_config_parameter/2,
    shared_dispatch_bindings/2,
    shared_dispatch_dispatched_field/2,
    shared_dispatch_effective_binding/2,
    shared_dispatch_failed_binding/2,
    shared_dispatch_reduction_field/2,
    shared_entry_step/1,
    shared_executor_dispatch/2,
    shared_executor_request_field/2,
    shared_executor_request_value/2,
    shared_issue_bindings/2,
    shared_machine_support/2,
    shared_post_issue_state/2,
    shared_post_issue_state_name/2,
    shared_proc_field/2,
    shared_ready_selection_call/2,
    shared_retire_binding/1,
    shared_service_helpers/2,
    shared_state_fields/2,
    shared_state_source/2
]).

-type reductions() :: none | xls_statem_reduction_ir:reduction().
-type service_mode() :: ordinary | aggregate_only.

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

-spec shared_state_fields(reductions(), service_mode()) -> iodata().
shared_state_fields(none, _Mode) ->
    [];
shared_state_fields(_Reductions, ordinary) ->
    [
        "  // Private completion events outrank entry and mailbox work for\n",
        "  // the same actor, but retain round-robin fairness across actors.\n",
        "  internal_candidates: u1[ACTOR_COUNT],\n"
    ];
shared_state_fields(_Reductions, aggregate_only) ->
    [
        "  // Private completion events outrank aggregate, entry, and\n",
        "  // mailbox work for the same actor; actor choice stays fair.\n",
        "  internal_candidates: u1[ACTOR_COUNT],\n",
        "  // Each actor can have at most one completed aggregate awaiting\n",
        "  // application: it cannot open its next reduction until this one\n",
        "  // retires. Per-actor receptacles prevent one blocked actor from\n",
        "  // backpressuring the reduction plane for every other actor.\n",
        "  aggregate_pending: ReductionAggregateRequest[ACTOR_COUNT],\n",
        "  aggregate_pending_valid: u1[ACTOR_COUNT],\n"
    ].

-spec shared_executor_request_field(reductions(), service_mode()) -> iodata().
shared_executor_request_field(none, _Mode) ->
    [];
shared_executor_request_field(_Reductions, ordinary) ->
    "  internal: u1,\n";
shared_executor_request_field(_Reductions, aggregate_only) ->
    [
        "  internal: u1,\n",
        "  aggregate_request: ReductionAggregateRequest,\n",
        "  aggregate_valid: u1,\n"
    ].

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
direct_entry_bindings(Reductions) ->
    entry_bindings(Reductions).

entry_bindings(none) ->
    "    let entry_failed = outcome.failed;\n";
entry_bindings(_Reductions) ->
    [
        "    let opens_reduction = outcome.reduction.status != ReductionStatus::IDLE;\n",
        "    let entry_failed = outcome.failed || (opens_reduction &&\n",
        "      machine.reduction.status != ReductionStatus::IDLE);\n",
        "    let entered_reduction = if opens_reduction {\n",
        "      outcome.reduction\n",
        "    } else { machine.reduction };\n"
    ].

-spec direct_entry_reduction_field(reductions()) -> iodata().
direct_entry_reduction_field(none) ->
    [];
direct_entry_reduction_field(_Reductions) ->
    [
        "      reduction: if entry_complete { entered_reduction }\n",
        "        else { machine.reduction },\n"
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

-spec shared_machine_support(reductions(), service_mode()) -> iodata().
shared_machine_support(none, _Mode) ->
    [];
shared_machine_support(_Reductions, Mode) ->
    ["""
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

    """, shared_machine_aggregate(Mode)].

shared_machine_aggregate(ordinary) ->
    [];
shared_machine_aggregate(aggregate_only) ->
    """
    fn shared_machine_aggregate(
        machine: SharedMachine,
        request: ReductionAggregateRequest,
        slot: u32) -> SharedDispatch {
      let applied = reduction_apply_complete_aggregate(
        machine.reduction, request.aggregate);
      let accepted = !machine.failed && !machine.enter_pending &&
        request.slot == slot &&
        applied.outcome == ReductionOutcome::COMPLETE;
      if accepted {
        shared_machine_complete(SharedMachine {
          reduction: applied.state,
          ..machine
        })
      } else {
        SharedDispatch {
          machine: SharedMachine { failed: u1:1, ..machine },
          dispatched: u1:1,
          directive: Directive::FAIL,
          ..zero!<SharedDispatch>()
        }
      }
    }

    """.

-spec shared_dispatch_bindings(reductions(), service_mode()) -> iodata().
shared_dispatch_bindings(none, _Mode) ->
    [
        "    let (next_phase, next_data, directive, repeat_phase) =\n",
        "      if tag_ok {\n",
        "        dispatch(frame, machine.phase, machine.data)\n",
        "      } else {\n",
        "        (machine.phase, machine.data, Directive::FAIL, u1:0)\n",
        "      };\n"
    ];
shared_dispatch_bindings(_Reductions, aggregate_only) ->
    %% A source-fragment artifact receives contribution messages only through
    %% its aggregate port. Any such frame on an ordinary mailbox is therefore
    %% handled by the actor's ordinary dispatch table (normally as an error).
    shared_dispatch_bindings(none, ordinary);
shared_dispatch_bindings(_Reductions, ordinary) ->
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

-spec shared_dispatch_effective_binding(reductions(), service_mode()) ->
    iodata().
shared_dispatch_effective_binding(none, _Mode) ->
    "    let effective = tag_ok && !invalid_repeat;\n";
shared_dispatch_effective_binding(_Reductions, _Mode) ->
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

-spec shared_dispatch_failed_binding(reductions(), service_mode()) -> iodata().
shared_dispatch_failed_binding(none, _Mode) ->
    [
        "    let failed = !tag_ok || invalid_repeat ||\n",
        "      (effective && directive == Directive::FAIL);\n"
    ];
shared_dispatch_failed_binding(_Reductions, _Mode) ->
    [
        "    let failed = !tag_ok || invalid_repeat ||\n",
        "      incomplete_boundary ||\n",
        "      (effective && directive == Directive::FAIL);\n"
    ].

-spec shared_dispatch_reduction_field(reductions(), service_mode()) -> iodata().
shared_dispatch_reduction_field(none, _Mode) ->
    [];
shared_dispatch_reduction_field(_Reductions, aggregate_only) ->
    [];
shared_dispatch_reduction_field(_Reductions, ordinary) ->
    "      reduction: next_reduction,\n".

-spec shared_dispatch_dispatched_field(reductions(), service_mode()) ->
    iodata().
shared_dispatch_dispatched_field(none, _Mode) ->
    "      dispatched: tag_ok && !invalid_repeat,\n";
shared_dispatch_dispatched_field(_Reductions, _Mode) ->
    [
        "      dispatched: tag_ok && !invalid_repeat &&\n",
        "        !incomplete_boundary,\n"
    ].

-spec shared_entry_step(reductions()) -> iodata().
shared_entry_step(Reductions) ->
    [
        "    let outcome = enter(\n",
        "      machine.entered_from, machine.phase, machine.data);\n",
        "    let effects = outcome.effects;\n",
        "    let effects_valid = entry_effects_valid(effects);\n",
        entry_bindings(Reductions),
        "    let can_advance = !entry_failed && (!effects_valid || egress_ready);\n",
        "    let advanced_machine = SharedMachine {\n",
        "      data: if entry_failed { machine.data } else { outcome.data },\n",
        shared_entry_reduction_field(Reductions),
        "      enter_pending: u1:0,\n",
        "      failed: entry_failed,\n",
        "      ..machine\n",
        "    };\n",
        "    SharedStep {\n",
        "      machine: if can_advance || entry_failed { advanced_machine }\n",
        "        else { machine },\n",
        "      effects,\n",
        "      effects_valid: effects_valid && can_advance,\n",
        "      egress_blocked: effects_valid && !egress_ready && !entry_failed,\n",
        "      ..zero!<SharedStep>()\n",
        "    }\n"
    ].

shared_entry_reduction_field(none) ->
    [];
shared_entry_reduction_field(_Reductions) ->
    [
        "      reduction: if entry_failed { machine.reduction }\n",
        "        else { entered_reduction },\n"
    ].

-spec shared_executor_dispatch(reductions(), service_mode()) -> iodata().
shared_executor_dispatch(none, _Mode) ->
    [
        "  let dispatched = shared_machine_dispatch(\n",
        "    machine, request.frame, request.received);\n"
    ];
shared_executor_dispatch(_Reductions, ordinary) ->
    [
        "  let dispatched = if request.internal {\n",
        "    shared_machine_complete(machine)\n",
        "  } else {\n",
        "    shared_machine_dispatch(\n",
        "      machine, request.frame, request.received)\n",
        "  };\n"
    ];
shared_executor_dispatch(_Reductions, aggregate_only) ->
    [
        "  let dispatched = if request.internal {\n",
        "    shared_machine_complete(machine)\n",
        "  } else if request.aggregate_valid {\n",
        "    shared_machine_aggregate(\n",
        "      machine, request.aggregate_request, request.slot)\n",
        "  } else {\n",
        "    shared_machine_dispatch(\n",
        "      machine, request.frame, request.received)\n",
        "  };\n"
    ].

%%%
%%% SharedService scheduling
%%%

-spec shared_service_helpers(reductions(), service_mode()) -> iodata().
shared_service_helpers(none, _Mode) ->
    [];
shared_service_helpers(_Reductions, Mode) ->
    ["""
    fn reduction_ready_selection<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        cursor: u32,
        in_flight: u1[ACTOR_COUNT]) -> (u1, u32) {
      scheduler::select(
        scheduler::Candidates<ACTOR_COUNT> {
          entry: state.entry_probes,
          mail: state.mail_candidates,
          egress: state.egress_waiters,
          internal: state.internal_candidates,
    """, "\n",
    case Mode of
        ordinary -> [];
        aggregate_only ->
            "      aggregate: state.aggregate_pending_valid,\n"
    end,
    """
          ..zero!<scheduler::Candidates<ACTOR_COUNT>>()
        }, state.egress_busy, in_flight, cursor)
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

    """].

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

-spec shared_issue_bindings(reductions(), service_mode()) -> iodata().
shared_issue_bindings(none, _Mode) ->
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
shared_issue_bindings(_Reductions, ordinary) ->
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
    ];
shared_issue_bindings(_Reductions, aggregate_only) ->
    [
        "        let prior_issue_valid =\n",
        "          state.next_valid && !completion_blocked;\n",
        "        let prior_read_slot = if state.next_valid {\n",
        "          state.next_slot\n",
        "        } else { u32:0 };\n",
        "        // The retained choice wins. Otherwise select work made\n",
        "        // visible by aggregate capture or retirement and issue it\n",
        "        // without another activation's selection bubble.\n",
        "        let fast_in_flight = if retire_valid {\n",
        "          update(retired_in_flight, result.slot, u1:1)\n",
        "        } else {\n",
        "          retired_in_flight\n",
        "        };\n",
        "        let (fast_ready, fast_slot) = reduction_ready_selection(\n",
        "          retired, state.cursor, fast_in_flight);\n",
        "        let fast_issue = !prior_issue_valid &&\n",
        "          !completion_blocked && fast_ready;\n",
        "        let issue_valid = prior_issue_valid || fast_issue;\n",
        "        let read_slot = if prior_issue_valid {\n",
        "          prior_read_slot\n",
        "        } else { fast_slot };\n",
        "        let internal_active = issue_valid &&\n",
        "          retired.internal_candidates[read_slot];\n",
        "        let aggregate_active = issue_valid &&\n",
        "          !internal_active &&\n",
        "          retired.aggregate_pending_valid[read_slot];\n",
        "        let private_active = internal_active || aggregate_active;\n",
        "        let entry_active = private_active ||\n",
        "          state.entry_probes[read_slot] ||\n",
        "          state.egress_waiters[read_slot];\n",
        "        let read_mailbox = issue_valid && !private_active &&\n",
        "          state.mail_candidates[read_slot] && !entry_active;\n"
    ].

-spec shared_ready_selection_call(reductions(), service_mode()) -> iodata().
shared_ready_selection_call(none, _Mode) ->
    [
        " ready_selection(\n",
        "          selection_state,\n",
        "          cursor,\n",
        "          issued_in_flight);\n"
    ];
shared_ready_selection_call(_Reductions, _Mode) ->
    [
        " reduction_ready_selection(\n",
        "          selection_state, cursor, issued_in_flight);\n"
    ].

-spec shared_executor_request_value(reductions(), service_mode()) -> iodata().
shared_executor_request_value(none, _Mode) ->
    [];
shared_executor_request_value(_Reductions, ordinary) ->
    "              internal: internal_active,\n";
shared_executor_request_value(_Reductions, aggregate_only) ->
    [
        "              internal: internal_active,\n",
        "              aggregate_request:\n",
        "                retired.aggregate_pending[read_slot],\n",
        "              aggregate_valid: aggregate_active,\n"
    ].

-spec shared_proc_field(reductions(), service_mode()) -> iodata().
shared_proc_field(_Reductions, ordinary) ->
    "\n";
shared_proc_field(_Reductions, aggregate_only) ->
    "\n      aggregate_in: chan<ReductionAggregateRequest> in;\n".

-spec shared_config_parameter(reductions(), service_mode()) -> iodata().
shared_config_parameter(_Reductions, ordinary) ->
    "\n";
shared_config_parameter(_Reductions, aggregate_only) ->
    [
        ",\n",
        "          aggregate_in: chan<ReductionAggregateRequest> in\n"
    ].

-spec shared_config_endpoint(reductions(), service_mode()) -> iodata().
shared_config_endpoint(_Reductions, ordinary) ->
    "\n";
shared_config_endpoint(_Reductions, aggregate_only) ->
    "\n          aggregate_in,\n".

-spec shared_capture(reductions(), service_mode()) -> iodata().
shared_capture(_Reductions, ordinary) ->
    "\n";
shared_capture(_Reductions, aggregate_only) ->
    ["\n", """
        let (aggregate_tok, incoming_aggregate, incoming_aggregate_valid) =
          recv_if_non_blocking(
            capture_tok,
            aggregate_in,
            capture_enabled,
            zero!<ReductionAggregateRequest>());
        let aggregate_slot = if incoming_aggregate.slot < ACTOR_COUNT {
          incoming_aggregate.slot
        } else { u32:0 };
        let aggregate_protocol_error = incoming_aggregate_valid &&
          (incoming_aggregate.slot >= ACTOR_COUNT ||
           state.aggregate_pending_valid[aggregate_slot]);
        let captured_aggregate = ReductionAggregateRequest {
          aggregate: if aggregate_protocol_error {
            ReductionAggregate {
              failed: u1:1,
              ..incoming_aggregate.aggregate
            }
          } else {
            incoming_aggregate.aggregate
          },
          ..incoming_aggregate
        };
        let aggregate_pending = if incoming_aggregate_valid {
          update(
            state.aggregate_pending, aggregate_slot, captured_aggregate)
        } else {
          state.aggregate_pending
        };
        let aggregate_pending_valid = if incoming_aggregate_valid {
          update(state.aggregate_pending_valid, aggregate_slot, u1:1)
        } else {
          state.aggregate_pending_valid
        };
        let aggregate_state = SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
          aggregate_pending,
          aggregate_pending_valid,
          ..state
        };
    """, "\n"].

-spec shared_capture_token(reductions(), service_mode()) -> iodata().
shared_capture_token(_Reductions, ordinary) ->
    "capture_tok";
shared_capture_token(_Reductions, aggregate_only) ->
    "aggregate_tok".

-spec shared_state_source(reductions(), service_mode()) -> iodata().
shared_state_source(_Reductions, ordinary) ->
    "state";
shared_state_source(_Reductions, aggregate_only) ->
    "aggregate_state".

-spec shared_post_issue_state(reductions(), service_mode()) -> iodata().
shared_post_issue_state(_Reductions, ordinary) ->
    "\n";
shared_post_issue_state(_Reductions, aggregate_only) ->
    ["\n", """
        let post_issue_state = SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
          aggregate_pending_valid: if aggregate_active {
            update(
              admitted.aggregate_pending_valid, read_slot, u1:0)
          } else {
            admitted.aggregate_pending_valid
          },
          ..admitted
        };
    """, "\n"].

-spec shared_post_issue_state_name(reductions(), service_mode()) -> iodata().
shared_post_issue_state_name(_Reductions, ordinary) ->
    "admitted";
shared_post_issue_state_name(_Reductions, aggregate_only) ->
    "post_issue_state".

join_with(_Separator, []) ->
    [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].
