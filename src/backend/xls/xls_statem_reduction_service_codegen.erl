-module(xls_statem_reduction_service_codegen).
-moduledoc false.
-export([machine_state_field/1, machine_state_copy_field/1, direct_after_failed/2, direct_dispatch_bindings/2, direct_effective_binding/1, direct_failed_binding/1, direct_reduction_field/1, direct_entry_bindings/1, direct_entry_reduction_field/1, direct_receive_gate/1]).
-type reductions() :: none | xls_statem_reduction_ir:reduction().

-export([event_tail/2, entry_bindings/1]).

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
        "    let failure = hls_failure::completion(\n",
        "      completed.dispatched, invalid_repeat, completed.failure);\n",
        "    let failed = hls_failure::failed(failure);\n",
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
        "      failure,\n",
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

-doc "Binds a singleton callback result, including optional internal-event and reply fields.".
-spec direct_dispatch_bindings(reductions(), map()) -> iodata().
direct_dispatch_bindings(none, Events) ->
    [
        "      let (next_phase, next_data, directive, repeat_phase, dispatch_failure", event_tail(Events, "next_event"), ") =\n",
        "        if dispatchable {\n",
        "          dispatch(selected_frame, machine.phase, machine.data", xls_statem_reply_codegen:optional(Events, ", call_from, call_error"), ")\n",
        "        } else {\n",
        "          (machine.phase, machine.data, ",
        "Directive::CONSUME, u1:0, hls_failure::NONE", event_tail(Events, "u8:0"), ")\n",
        "        };\n"
    ];
direct_dispatch_bindings(_Reductions, Events) ->
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
        "      let (next_phase, next_data, directive, repeat_phase, dispatch_failure", event_tail(Events, "next_event"), ") =\n",
        "        if !dispatchable {\n",
        "          (machine.phase, machine.data, ",
        "Directive::CONSUME, u1:0, hls_failure::NONE", event_tail(Events, "u8:0"), ")\n",
        "        } else if !reduction_candidate {\n",
        "          dispatch(selected_frame, machine.phase, machine.data", xls_statem_reply_codegen:optional(Events, ", call_from, call_error"), ")\n",
        "        } else if reduction_mismatch {\n",
        "          (machine.phase, machine.data, ",
        "Directive::POSTPONE, u1:0, hls_failure::NONE", event_tail(Events, "u8:0"), ")\n",
        "        } else if reduction_accepted {\n",
        "          (machine.phase, machine.data, ",
        "Directive::CONSUME, u1:0, hls_failure::NONE", event_tail(Events, "u8:0"), ")\n",
        "        } else {\n",
        "          (machine.phase, machine.data, Directive::FAIL, u1:0, hls_failure::REDUCTION_PROTOCOL", event_tail(Events, "u8:0"), ")\n",
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
direct_failed_binding(Reductions) ->
    [
        "      let failure = hls_failure::dispatch(invalid_input, invalid_repeat, ",
        case Reductions of none -> "false"; _ -> "incomplete_boundary" end,
        ", effective, dispatch_failure);\n",
        "      let failed = hls_failure::failed(failure);\n"
    ].

-spec direct_reduction_field(reductions()) -> iodata().
direct_reduction_field(none) ->
    [];
direct_reduction_field(_Reductions) ->
    "        reduction: next_reduction,\n".

-spec direct_entry_bindings(reductions()) -> iodata().
direct_entry_bindings(Reductions) ->
    entry_bindings(Reductions).

-doc "Emits checked entry evaluation and the reduction-open failure condition.".
-spec entry_bindings(none | xls_statem_reduction_ir:reduction()) -> iodata().
entry_bindings(none) ->
    "    let entry_failure = outcome.failure;\n"
    "    let entry_failed = hls_failure::failed(entry_failure);\n";
entry_bindings(_Reductions) ->
    [
        "    let opens_reduction = outcome.reduction.status != ReductionStatus::IDLE;\n",
        "    let entry_failure = hls_failure::first(outcome.failure,\n",
        "      hls_failure::check(opens_reduction &&\n",
        "        machine.reduction.status != ReductionStatus::IDLE, hls_failure::REDUCTION_PROTOCOL));\n",
        "    let entry_failed = hls_failure::failed(entry_failure);\n",
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

join_with(_Separator, []) ->
    [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].

%% Add the finite event selector only to opted-in callback results.
-doc "Selects the reduction completion continuation after ordinary dispatch handling.".
-spec event_tail(map(), iodata()) -> iodata().
event_tail(Spec, Value) ->
    [xls_statem_event_codegen:optional(Spec, [", ", Value]),
     xls_statem_reply_codegen:optional(Spec, case Value of
        "next_event" -> ", reply_from, reply_frame, reply_allowed";
        "u8:0" -> ", u64:0, zero!<axis::Frame>(), true"
     end)].
