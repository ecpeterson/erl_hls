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
    shared_blocked_probe_bindings/2,
    shared_boot_reduction_io/1,
    shared_admission_exclusion_valid/1,
    shared_direct_reduction_bindings/2,
    shared_entry_step/1,
    shared_executor_dispatch/1,
    shared_executor_internal_request_field/1,
    shared_executor_request_token/1,
    shared_executor_send_condition/1,
    shared_fold_config_bindings/2,
    shared_fold_config_endpoints/2,
    shared_fold_config_spawn/2,
    shared_fold_done_token/2,
    shared_fold_envelope_declaration/2,
    shared_fold_request_send/2,
    shared_fold_service_fields/2,
    shared_folded_state_fields/2,
    shared_fast_issue_bindings/2,
    shared_in_flight_field/1,
    shared_issue_bindings/2,
    shared_local_fold_bindings/2,
    shared_machine_support/3,
    shared_ready_bindings/1,
    shared_ready_selection_call/2,
    shared_result_retirement_head/2,
    shared_reduction_config_parameters/2,
    shared_reduction_read_io/1,
    shared_reduction_write_io/1,
    shared_retirement_token/2,
    shared_service_helpers/2,
    shared_state_fields/2,
    shared_state_read_condition/1
]).

-type reductions() :: none | map().
-type service_mode() :: ordinary | joined | aggregate_only.

shared_state_fields(none, _Mode) -> [];
shared_state_fields(_Reductions, Mode) ->
    [
    """
      // In an ordinary reducing scheduler a contribution is consumed by the
      // mailbox-head sidecar.  An aggregate-only source-fragment scheduler
      // instead receives completed aggregates.  In both cases only completion
      // and protocol errors become private actor work.
      // Reduction words are deliberately register-resident: these arrays are
      // small, and direct indexing avoids a read/write/acknowledgment trip
      // through a shallow, badly fragmented external RAM on every fold.
      reductions: ReductionBits[ACTOR_COUNT],
      internal_candidates: u1[ACTOR_COUNT],
      reduction_errors: u1[ACTOR_COUNT],
      reduction_active: u1[ACTOR_COUNT],
      // A non-contribution head is handed to the ordinary actor exactly once.
      reduction_probed: u1[ACTOR_COUNT],
    """,
        case Mode of
            ordinary -> [];
            joined -> aggregate_pending_fields();
            aggregate_only -> aggregate_pending_fields()
        end,
        case Mode of
            ordinary -> fold_state_fields();
            joined -> fold_state_fields();
            aggregate_only -> []
        end
    ].

aggregate_pending_fields() ->
    """
      // A source-fragment plane now withholds semantic early arrivals until
      // the destination actor's own opening batch has reached that plane.
      // Only short scheduler hazards therefore need this scalar skid slot;
      // completed payloads are not duplicated into actor-indexed banks.
      aggregate_pending: ReductionAggregateRequest,
      aggregate_pending_valid: u1,
    """.

fold_state_fields() ->
    """
      next_fold: u1,
      // Once ordinary retirement wins, a waiting sidecar result gets the
      // next contested retirement opportunity.
      fold_retire_turn: u1,
    """.

shared_boot_reduction_io(none) ->
    "\n        let boot_write_tok = write_tok;\n";
shared_boot_reduction_io(_Reductions) ->
    ["\n", """
            // Register-resident reduction words start at zero with SharedState.
            // reduction_active gates their interpretation until an actor opens
            // its first reduction.
            let boot_write_tok = write_tok;
    """, "\n"].

shared_state_read_condition(none) ->
    "\n          issue_valid,\n";
shared_state_read_condition(_Reductions) ->
    "\n          actor_issue_valid,\n".

-spec shared_admission_exclusion_valid(reductions()) -> iodata().
shared_admission_exclusion_valid(none) ->
    "\n          issue_valid,\n";
shared_admission_exclusion_valid(_Reductions) ->
    %% A sidecar probe reads an occupied mailbox-head row while admission
    %% writes a distinct free row and appends it to the logical order.  Only
    %% an ordinary actor activation must exclude same-slot admission: it may
    %% rewrite mailbox metadata after dispatch, and it also reads actor RAM.
    "\n          actor_issue_valid,\n".

shared_reduction_read_io(none) -> "\n";
shared_reduction_read_io(_Reductions) ->
    ["\n", """
            let reduction_bits = direct_state.reductions[read_slot];
    """, "\n"].

shared_reduction_write_io(none) -> "\n";
shared_reduction_write_io(_Reductions) -> "\n".

-spec shared_direct_reduction_bindings(reductions(), service_mode()) ->
    iodata().
shared_direct_reduction_bindings(none, _Mode) ->
    ["\n", """
            let direct_state = retired;
            let direct_pending = captured_pending;
            let direct_pending_valid = credit_pending_valid;
            let direct_in_flight_slots = retired_in_flight;
    """, "\n"];
shared_direct_reduction_bindings(_Reductions, ordinary) ->
    ["\n", """
            let direct_fold = reserve_direct_reduction(
              retired,
              captured_pending,
              credit_pending_valid,
              retired_in_flight,
              prior_issue_valid,
              prior_read_slot,
              reduction_write_valid,
              reduction_write_slot,
              reduction_write_bits);
            // Retirement and a sender-addressed fold may update distinct
            // receptacles in one activation. Spell the two writes as one
            // constant-index unrolled bank so XLS does not synthesize two
            // cascaded variable-index update networks.
            let reductions = apply_reduction_writes(
              retired.reductions,
              reduction_write_valid,
              reduction_write_slot,
              reduction_write_bits,
              direct_fold.valid,
              direct_fold.slot,
              direct_fold.reduction);
            let direct_state = SharedState<
                ACTOR_COUNT, PRODUCER_COUNT> {
              reductions,
              reduction_active: direct_fold.reduction_active,
              internal_candidates: direct_fold.internal_candidates,
              reduction_errors: direct_fold.reduction_errors,
              admission_cursor: direct_fold.cursor,
              ..retired
            };
            let direct_pending = direct_fold.pending;
            let direct_pending_valid = direct_fold.pending_valid;
            let direct_in_flight_slots = retired_in_flight;
    """, "\n"];
shared_direct_reduction_bindings(_Reductions, joined) ->
    ["\n", """
            let direct_fold = reserve_direct_reduction(
              retired,
              captured_pending,
              credit_pending_valid,
              retired_in_flight,
              prior_issue_valid,
              prior_read_slot,
              reduction_write_valid,
              reduction_write_slot,
              reduction_write_bits);
            let reductions = apply_reduction_writes(
              retired.reductions,
              reduction_write_valid,
              reduction_write_slot,
              reduction_write_bits,
              direct_fold.valid,
              direct_fold.slot,
              direct_fold.reduction);
            let pre_aggregate_state = SharedState<
                ACTOR_COUNT, PRODUCER_COUNT> {
              reductions,
              reduction_active: direct_fold.reduction_active,
              internal_candidates: direct_fold.internal_candidates,
              reduction_errors: direct_fold.reduction_errors,
              admission_cursor: direct_fold.cursor,
              ..retired
            };
            let aggregate_pending_valid =
              pre_aggregate_state.aggregate_pending_valid;
            let (aggregate_tok, incoming_aggregate,
                 incoming_aggregate_valid) = recv_if_non_blocking(
              join(), aggregate_in,
              !aggregate_pending_valid,
              zero!<ReductionAggregateRequest>());
            let aggregate_request = if aggregate_pending_valid {
              pre_aggregate_state.aggregate_pending
            } else {
              incoming_aggregate
            };
            let direct_state = reserve_reduction_aggregate<
                ACTOR_COUNT, PRODUCER_COUNT>(
              pre_aggregate_state,
              aggregate_request,
              aggregate_pending_valid || incoming_aggregate_valid,
              retired_in_flight,
              prior_issue_valid,
              prior_read_slot);
            let direct_pending = direct_fold.pending;
            let direct_pending_valid = direct_fold.pending_valid;
            let direct_in_flight_slots = retired_in_flight;
    """, "\n"];
shared_direct_reduction_bindings(_Reductions, aggregate_only) ->
    ["\n", """
            let reductions = if reduction_write_valid {
              update(
                retired.reductions,
                reduction_write_slot,
                reduction_write_bits)
            } else {
              retired.reductions
            };
            let pre_aggregate_state = SharedState<
                ACTOR_COUNT, PRODUCER_COUNT> {
              reductions,
              ..retired
            };
            // The source-fragment plane holds semantic early arrivals in its
            // per-edge queues until the destination's opening batch supplies
            // a token. This scalar slot covers only bounded scheduler skew.
            let aggregate_pending_valid =
              pre_aggregate_state.aggregate_pending_valid;
            let (aggregate_tok, incoming_aggregate,
                 incoming_aggregate_valid) = recv_if_non_blocking(
              join(), aggregate_in,
              !aggregate_pending_valid,
              zero!<ReductionAggregateRequest>());
            let aggregate_request = if aggregate_pending_valid {
              pre_aggregate_state.aggregate_pending
            } else {
              incoming_aggregate
            };
            let direct_state = reserve_complete_reduction_aggregate<
                ACTOR_COUNT, PRODUCER_COUNT>(
              pre_aggregate_state,
              aggregate_request,
              aggregate_pending_valid || incoming_aggregate_valid,
              retired_in_flight,
              prior_issue_valid,
              prior_read_slot);
            let direct_pending = captured_pending;
            let direct_pending_valid = credit_pending_valid;
            let direct_in_flight_slots = retired_in_flight;
    """, "\n"].

-spec shared_fast_issue_bindings(reductions(), service_mode()) -> iodata().
shared_fast_issue_bindings(none, _Mode) -> [];
shared_fast_issue_bindings(Reductions, joined) ->
    shared_fast_issue_bindings(Reductions, ordinary);
shared_fast_issue_bindings(_Reductions, Mode) ->
    SelectionFunction = case Mode of
        ordinary -> "reduction_ready_selection";
        aggregate_only -> "aggregate_ready_selection"
    end,
    FoldSelection = case Mode of
        ordinary -> """
            let (fast_fold_ready, fast_fold_slot) =
              reduction_fold_selection(
                direct_ready_metadata, state.cursor, fast_in_flight);
            let fast_ready = if completion_blocked {
              fast_fold_ready
            } else {
              fast_selected_ready
            };
            let fast_slot = if completion_blocked {
              fast_fold_slot
            } else {
              fast_selected_slot
            };
        """;
        aggregate_only -> """
            let fast_ready = !completion_blocked && fast_selected_ready;
            let fast_slot = if completion_blocked {
              u32:0
            } else {
              fast_selected_slot
            };
        """
    end,
    FoldIssue = case Mode of
        ordinary -> """
            let fold_issue_valid = issue_valid &&
              (if prior_issue_valid {
                state.next_fold
              } else {
                sidecar_fold_ready(direct_ready_metadata, read_slot)
              });
        """;
        aggregate_only ->
            "            let fold_issue_valid = u1:0;\n"
    end,
    ["\n", """
            // The retained next slot remains the first choice. When it
            // cannot issue, select newly visible work after retirement,
            // direct folding, and aggregate intake, and launch its RAM read
            // in this same activation. Keep a retiring actor excluded from
            // this bypass because its new state is being written concurrently;
            // a later activation may safely read it after the write response.
            let fast_in_flight = if retire_valid {
              update(direct_in_flight_slots, result.slot, u1:1)
            } else {
              direct_in_flight_slots
            };
            let direct_ready_metadata = ReductionReadyMetadata<ACTOR_COUNT> {
              internal_candidates: direct_state.internal_candidates,
              reduction_errors: direct_state.reduction_errors,
              entry_probes: direct_state.entry_probes,
              egress_waiters: direct_state.egress_waiters,
              reduction_active: direct_state.reduction_active,
              mail_candidates: direct_state.mail_candidates,
              reduction_probed: direct_state.reduction_probed,
              egress_busy: direct_state.egress_busy,
            };
            let (fast_selected_ready, fast_selected_slot) =
    """,
        "              ", SelectionFunction, "<ACTOR_COUNT>(\n",
        "                direct_ready_metadata, state.cursor, ",
        "fast_in_flight);\n",
        FoldSelection, """
            let fast_issue = !prior_issue_valid && fast_ready;
            let issue_valid = prior_issue_valid || fast_issue;
            let read_slot = if prior_issue_valid {
              prior_read_slot
            } else {
              fast_slot
            };
    """,
        FoldIssue, """
            let actor_issue_valid = issue_valid && !fold_issue_valid;
            let internal_active = actor_issue_valid &&
              direct_state.internal_candidates[read_slot];
            let reduction_error_active = actor_issue_valid &&
              direct_state.reduction_errors[read_slot];
            let private_active = internal_active ||
              reduction_error_active;
            let entry_active = private_active ||
              direct_state.entry_probes[read_slot] ||
              direct_state.egress_waiters[read_slot];
            let read_mailbox = issue_valid && !private_active &&
              direct_state.mail_candidates[read_slot] &&
              (fold_issue_valid || !entry_active);
    """, "\n"].

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

-spec shared_machine_support(reductions(), iodata(), service_mode()) ->
    iodata().
shared_machine_support(none, _TagOk, _Mode) -> [];
shared_machine_support(Reductions, TagOk, Mode) ->
    [
        direct_reduction_candidate(Reductions, TagOk),
        case Mode of
            ordinary -> shared_reduction_sidecar_step(Reductions, TagOk);
            joined -> shared_reduction_sidecar_step(Reductions, TagOk);
            aggregate_only -> []
        end,
        shared_machine_complete_function(Reductions)
    ].

direct_reduction_candidate(none, _TagOk) -> [];
direct_reduction_candidate(Reductions, TagOk) ->
    [
        "pub fn direct_reduction_candidate(frame: axis::Frame) -> u1 {\n",
        "  (", TagOk, ") && (",
        direct_contribution_tag_expression(Reductions), ")\n",
        "}\n\n"
    ].

shared_reduction_sidecar_step(none, _TagOk) -> [];
shared_reduction_sidecar_step(_Reductions, TagOk) ->
    [
        "fn shared_reduction_sidecar_step(\n",
        "    state: ReductionState, frame: axis::Frame)\n",
        "    -> ReductionApply {\n",
        "  let tag_ok = ", TagOk, ";\n",
        "  if tag_ok {\n",
        "    reduction_apply(\n",
        "      state, reduction_sidecar_contribution(frame, state))\n",
        "  } else {\n",
        "    ReductionApply {\n",
        "      state, outcome: ReductionOutcome::NOT_CANDIDATE }\n",
        "  }\n",
        "}\n\n"
    ].

direct_contribution_tag_expression(Reductions) ->
    Tags = xls_statem_reduction_codegen:contribution_tags(Reductions),
    join_with(" || ", [
        ["frame.header.op == (Tag::", uppercase(Tag), " as u8)"]
        || Tag <- Tags
    ]).

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
        "  let dispatched = shared_machine_dispatch(\n",
        "    machine, request.frame, request.received);\n"
    ];
shared_executor_dispatch(_Reductions) ->
    [
        "  let dispatched = if request.reduction_error {\n",
        "    SharedDispatch {\n",
        "      machine: SharedMachine { failed: u1:1, ..machine },\n",
        "      dispatched: u1:1,\n",
        "      directive: Directive::FAIL,\n",
        "      ..zero!<SharedDispatch>()\n",
        "    }\n",
        "  } else if request.internal {\n",
        "    shared_machine_complete(machine)\n",
        "  } else {\n",
        "    shared_machine_dispatch(\n",
        "      machine, request.frame, request.received)\n",
        "  };\n"
    ].

-spec shared_fold_envelope_declaration(reductions(), service_mode()) ->
    iodata().
shared_fold_envelope_declaration(none, _Mode) -> [];
shared_fold_envelope_declaration(_Reductions, Mode) ->
    [
        case Mode of
            ordinary -> fold_envelope_declarations();
            joined -> fold_envelope_declarations();
            aggregate_only -> []
        end,
        """
    // Selection needs only one-bit scheduling metadata. Keeping this view
    // separate from SharedState avoids carrying mailbox contents, producer
    // holds, and completed executor results through each unrolled scan.
    struct ReductionReadyMetadata<ACTOR_COUNT: u32> {
      internal_candidates: u1[ACTOR_COUNT],
      reduction_errors: u1[ACTOR_COUNT],
      entry_probes: u1[ACTOR_COUNT],
      egress_waiters: u1[ACTOR_COUNT],
      reduction_active: u1[ACTOR_COUNT],
      mail_candidates: u1[ACTOR_COUNT],
      reduction_probed: u1[ACTOR_COUNT],
      egress_busy: u1,
    }

    """, "\n\n"].

fold_envelope_declarations() ->
    """
    // Reduction contribution traffic never carries actor state or effects.
    // This keeps the mailbox-head sidecar narrow and independent of the
    // actor executor's main-state RAM pipeline.
    struct FoldEnvelope {
      slot: u32,
      reduction: ReductionBits,
      outcome: ReductionOutcome,
      mailbox_index: u8,
      order_index: u8,
    }

    struct DirectFoldResult<ACTOR_COUNT: u32, PRODUCER_COUNT: u32> {
      pending: ScheduledRequest[PRODUCER_COUNT],
      pending_valid: u1[PRODUCER_COUNT],
      reduction: ReductionBits,
      reduction_active: u1[ACTOR_COUNT],
      internal_candidates: u1[ACTOR_COUNT],
      reduction_errors: u1[ACTOR_COUNT],
      cursor: u32,
      valid: u1,
      slot: u32,
      outcome: ReductionOutcome,
    }
    """.

-spec shared_service_helpers(reductions(), service_mode()) -> iodata().
shared_service_helpers(none, _Mode) -> "\n\n";
shared_service_helpers(_Reductions, Mode) ->
    [
        "\n\n",
        sidecar_readiness_helpers(Mode),
        aggregate_readiness_helpers(Mode),
        ordinary_ready_selection_helper(Mode),
        aggregate_ready_selection_helper(Mode),
        reduction_fold_selection_helper(Mode),
        apply_reduction_writes_helper(Mode),
        complete_aggregate_apply_helper(Mode),
        aggregate_reserve_helper(Mode),
        direct_reserve_helper(Mode),
        retire_actor_helper(),
        fold_retirement_helpers(Mode),
        "\n\n"
    ].

sidecar_readiness_helpers(aggregate_only) -> [];
sidecar_readiness_helpers(_Mode) ->
    """
    fn sidecar_fold_ready<ACTOR_COUNT: u32>(
        metadata: ReductionReadyMetadata<ACTOR_COUNT>,
        slot: u32) -> u1 {
      let private_work = metadata.internal_candidates[slot] ||
        metadata.reduction_errors[slot];
      let entry_work = metadata.entry_probes[slot] ||
        metadata.egress_waiters[slot];
      metadata.reduction_active[slot] &&
        metadata.mail_candidates[slot] &&
        !metadata.reduction_probed[slot] &&
        !private_work && !entry_work
    }

    fn actor_ready<ACTOR_COUNT: u32>(
        metadata: ReductionReadyMetadata<ACTOR_COUNT>,
        slot: u32) -> u1 {
      let private_work = metadata.internal_candidates[slot] ||
        metadata.reduction_errors[slot];
      let entry_work = metadata.entry_probes[slot] ||
        metadata.egress_waiters[slot];
      let ordinary_mail = metadata.mail_candidates[slot] &&
        (!metadata.reduction_active[slot] ||
         metadata.reduction_probed[slot]);
      private_work || (!private_work && (
        metadata.entry_probes[slot] ||
        (ordinary_mail && !entry_work) ||
        (metadata.egress_waiters[slot] && !metadata.egress_busy)))
    }

    """.

aggregate_readiness_helpers(aggregate_only) ->
    """
    fn aggregate_actor_ready<ACTOR_COUNT: u32>(
        metadata: ReductionReadyMetadata<ACTOR_COUNT>,
        slot: u32) -> u1 {
      let private_work = metadata.internal_candidates[slot] ||
        metadata.reduction_errors[slot];
      let entry_work = metadata.entry_probes[slot] ||
        metadata.egress_waiters[slot];
      let ordinary_mail = metadata.mail_candidates[slot];
      private_work || (!private_work && (
        metadata.entry_probes[slot] ||
        (ordinary_mail && !entry_work) ||
        (metadata.egress_waiters[slot] && !metadata.egress_busy)))
    }

    """;
aggregate_readiness_helpers(_Mode) -> [].

ordinary_ready_selection_helper(aggregate_only) -> [];
ordinary_ready_selection_helper(_Mode) ->
    """
    // The actor and sidecar share a fair slot cursor but have disjoint RAM
    // datapaths. A selected slot remains excluded until its write, if any,
    // has completed, which gives synchronous 1R1W storage defined RAW order.
    fn reduction_ready_selection<ACTOR_COUNT: u32>(
        metadata: ReductionReadyMetadata<ACTOR_COUNT>,
        cursor: u32,
        in_flight: u1[ACTOR_COUNT]) -> (u1, u32) {
      let (after_found, after_slot, before_found, before_slot) =
          unroll_for! (slot, acc):
              (u32, (u1, u32, u1, u32)) in u32:0..ACTOR_COUNT {
        let ready = actor_ready(metadata, slot) ||
          sidecar_fold_ready(metadata, slot);
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

    """.

aggregate_ready_selection_helper(aggregate_only) ->
    """
    fn aggregate_ready_selection<ACTOR_COUNT: u32>(
        metadata: ReductionReadyMetadata<ACTOR_COUNT>,
        cursor: u32,
        in_flight: u1[ACTOR_COUNT]) -> (u1, u32) {
      let (after_found, after_slot, before_found, before_slot) =
          unroll_for! (slot, acc):
              (u32, (u1, u32, u1, u32)) in u32:0..ACTOR_COUNT {
        let selectable = aggregate_actor_ready(metadata, slot) &&
          !in_flight[slot];
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

    """;
aggregate_ready_selection_helper(_Mode) -> [].

reduction_fold_selection_helper(aggregate_only) -> [];
reduction_fold_selection_helper(_Mode) ->
    """
    fn reduction_fold_selection<ACTOR_COUNT: u32>(
        metadata: ReductionReadyMetadata<ACTOR_COUNT>,
        cursor: u32,
        in_flight: u1[ACTOR_COUNT]) -> (u1, u32) {
      let (after_found, after_slot, before_found, before_slot) =
          unroll_for! (slot, acc):
              (u32, (u1, u32, u1, u32)) in u32:0..ACTOR_COUNT {
        let selectable = sidecar_fold_ready(metadata, slot) &&
          !in_flight[slot];
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

    """.

apply_reduction_writes_helper(aggregate_only) -> [];
apply_reduction_writes_helper(_Mode) ->
    """
    fn apply_reduction_writes<ACTOR_COUNT: u32>(
        reductions: ReductionBits[ACTOR_COUNT],
        retired_valid: u1,
        retired_slot: u32,
        retired_reduction: ReductionBits,
        direct_valid: u1,
        direct_slot: u32,
        direct_reduction: ReductionBits) ->
        ReductionBits[ACTOR_COUNT] {
      unroll_for! (slot, result):
          (u32, ReductionBits[ACTOR_COUNT]) in u32:0..ACTOR_COUNT {
        let next = if direct_valid && direct_slot == slot {
          direct_reduction
        } else if retired_valid && retired_slot == slot {
          retired_reduction
        } else {
          result[slot]
        };
        update(result, slot, next)
      }(reductions)
    }

    """.

complete_aggregate_apply_helper(aggregate_only) ->
    """
    // A completed sender-side aggregate has its own transport path, but the
    // owning scheduler remains the sole writer of actor reduction state. Keep
    // the register-bank update behind a typed helper boundary: this leaves the
    // already-large SharedService recurrence small enough for XLS to elaborate
    // without duplicating the aggregate decision tree into every use site.
    //
    // Aggregate-only deployments have no partial local fold to merge. Their
    // transport promises a complete population, so install its accumulator
    // directly instead of unnecessarily reducing it with the actor's identity.
    fn reduction_apply_complete_aggregate(
        state: ReductionState, aggregate: ReductionAggregate)
        -> ReductionApply {
      if !aggregate.valid {
        ReductionApply {
          state, outcome: ReductionOutcome::NOT_CANDIDATE }
      } else if state.status != ReductionStatus::OPEN ||
          state.site as u8 != aggregate.site ||
          state.key != aggregate.key {
        ReductionApply { state, outcome: ReductionOutcome::MISMATCH }
      } else if aggregate.failed ||
          reduction_site_mode(state.site) as u1 != aggregate.mode {
        ReductionApply { state, outcome: ReductionOutcome::WRONG_MODE }
      } else {
        let member_mode =
          reduction_site_mode(state.site) == ReductionMode::MEMBERS;
        let duplicate = member_mode &&
          (state.seen & aggregate.seen) != zero!<ReductionMembers>();
        let complete_population =
          state.remaining == reduction_site_population(state.site) &&
          aggregate.count == state.remaining;
        if duplicate {
          ReductionApply { state,
            outcome: ReductionOutcome::DUPLICATE_MEMBER }
        } else if !complete_population {
          ReductionApply { state,
            outcome: ReductionOutcome::UNEXPECTED_MEMBER }
        } else {
          ReductionApply {
            state: ReductionState {
              status: ReductionStatus::COMPLETE,
              remaining: u8:0,
              seen: if member_mode { aggregate.seen } else { state.seen },
              accumulator: aggregate.accumulator,
              ..state
            },
            outcome: ReductionOutcome::COMPLETE,
          }
        }
      }
    }

    """;
complete_aggregate_apply_helper(_Mode) -> [].

aggregate_reserve_helper(joined) ->
    """
    fn reserve_reduction_aggregate<
        ACTOR_COUNT: u32,
        PRODUCER_COUNT: u32
    >(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        request: ReductionAggregateRequest,
        found: u1,
        in_flight: u1[ACTOR_COUNT],
        excluded_valid: u1,
        excluded_slot: u32) ->
        SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      let slot = if request.slot < ACTOR_COUNT {
        request.slot
      } else {
        u32:0
      };
      let private_work = state.internal_candidates[slot] ||
        state.reduction_errors[slot];
      let entry_work = state.entry_probes[slot] ||
        state.egress_waiters[slot];
      let reduction = reduction_state_from_bits(state.reductions[slot]);
      let applied = reduction_apply_aggregate(
        reduction, request.reduction_aggregate);
      let aggregate_failed = request.reduction_aggregate.failed;
      // Source-fragment planes use the destination actor's own opening batch
      // as a narrow readiness token, so their aggregates cannot be
      // semantically early.  This scalar input can still outrun a transient
      // retirement/entry hazard and waits here until that clears.  Captured
      // contributions have no ordinary same-family route, so unrelated mail
      // may commute with an aggregate-only completion.  The general joined
      // transport retains its older mailbox-order and early-arrival rules.
      let mailbox_hazard = state.mail_candidates[slot];
      let aggregate_hazard_free = found && request.slot < ACTOR_COUNT &&
        !mailbox_hazard &&
        !private_work && !entry_work && !in_flight[slot] &&
        (!excluded_valid || slot != excluded_slot);
      let coherent_open = state.reduction_active[slot] &&
        applied.outcome != ReductionOutcome::MISMATCH;
      let aggregate_eligible = aggregate_hazard_free &&
        (aggregate_failed || coherent_open);
      let aggregate_accepted = aggregate_eligible &&
        !aggregate_failed &&
        (applied.outcome == ReductionOutcome::PENDING ||
         applied.outcome == ReductionOutcome::COMPLETE);
      let aggregate_complete = aggregate_accepted &&
        applied.outcome == ReductionOutcome::COMPLETE;
      let aggregate_error = aggregate_eligible && !aggregate_accepted;
      let reductions = if aggregate_accepted {
        update(
          state.reductions,
          slot,
          bits_from_reduction_state(applied.state))
      } else {
        state.reductions
      };
      let reduction_active = if aggregate_eligible {
        update(
          state.reduction_active,
          slot,
          aggregate_accepted && !aggregate_complete)
      } else {
        state.reduction_active
      };
      let internal_candidates = if aggregate_complete {
        update(state.internal_candidates, slot, u1:1)
      } else {
        state.internal_candidates
      };
      let reduction_errors = if aggregate_error {
        update(state.reduction_errors, slot, u1:1)
      } else {
        state.reduction_errors
      };
      SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
        reductions,
        reduction_active,
        internal_candidates,
        reduction_errors,
        aggregate_pending: request,
        aggregate_pending_valid: found && !aggregate_eligible,
        ..state
      }
    }

    """;
aggregate_reserve_helper(aggregate_only) ->
    """
    // Source-fragment planes release an aggregate only after the destination
    // actor's opening batch has supplied its readiness token. Consequently a
    // completed aggregate may commute with ordinary mailbox traffic and an
    // OPEN site/key mismatch is a protocol error rather than an early arrival.
    fn reserve_complete_reduction_aggregate<
        ACTOR_COUNT: u32,
        PRODUCER_COUNT: u32
    >(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        request: ReductionAggregateRequest,
        found: u1,
        in_flight: u1[ACTOR_COUNT],
        excluded_valid: u1,
        excluded_slot: u32) ->
        SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      let slot = if request.slot < ACTOR_COUNT {
        request.slot
      } else {
        u32:0
      };
      let private_work = state.internal_candidates[slot] ||
        state.reduction_errors[slot];
      let entry_work = state.entry_probes[slot] ||
        state.egress_waiters[slot];
      let reduction = reduction_state_from_bits(state.reductions[slot]);
      let applied = reduction_apply_complete_aggregate(
        reduction, request.reduction_aggregate);
      let aggregate_failed = request.reduction_aggregate.failed;
      let aggregate_hazard_free = found && request.slot < ACTOR_COUNT &&
        !private_work && !entry_work && !in_flight[slot] &&
        (!excluded_valid || slot != excluded_slot);
      // The source-fragment plane releases a completed aggregate only after
      // seeing this actor's opening batch.  Once local scheduling hazards
      // clear, a closed or incoherent receptacle is therefore a protocol
      // error, not an early value to retain forever.
      let aggregate_eligible = aggregate_hazard_free;
      let aggregate_accepted = aggregate_eligible &&
        !aggregate_failed &&
        (applied.outcome == ReductionOutcome::PENDING ||
         applied.outcome == ReductionOutcome::COMPLETE);
      let aggregate_complete = aggregate_accepted &&
        applied.outcome == ReductionOutcome::COMPLETE;
      let aggregate_error = aggregate_eligible && !aggregate_accepted;
      let reductions = if aggregate_accepted {
        update(
          state.reductions,
          slot,
          bits_from_reduction_state(applied.state))
      } else {
        state.reductions
      };
      let reduction_active = if aggregate_eligible {
        update(
          state.reduction_active,
          slot,
          aggregate_accepted && !aggregate_complete)
      } else {
        state.reduction_active
      };
      let internal_candidates = if aggregate_complete {
        update(state.internal_candidates, slot, u1:1)
      } else {
        state.internal_candidates
      };
      let reduction_errors = if aggregate_error {
        update(state.reduction_errors, slot, u1:1)
      } else {
        state.reduction_errors
      };
      SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
        reductions,
        reduction_active,
        internal_candidates,
        reduction_errors,
        aggregate_pending: request,
        aggregate_pending_valid: found && !aggregate_eligible,
        ..state
      }
    }

    """;
aggregate_reserve_helper(ordinary) -> [].

direct_reserve_helper(aggregate_only) -> [];
direct_reserve_helper(_Mode) ->
    """
    // A sender-marked contribution can update an open actor's receptacle
    // without first becoming mailbox work when no older mailbox event is
    // selectable in the current phase. Physically queued postponed events may
    // remain: ordinary mailbox scanning already permits younger selectable
    // events to pass them. Selection uses the same round-robin producer cursor
    // as ordinary admission. A transient same-slot hazard leaves the request
    // in its producer holding slot; a semantic miss clears the hint and falls
    // through to ordinary mailbox admission.
    fn reserve_direct_reduction<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        pending: ScheduledRequest[PRODUCER_COUNT],
        pending_valid: u1[PRODUCER_COUNT],
        in_flight: u1[ACTOR_COUNT],
        excluded_valid: u1,
        excluded_slot: u32,
        forwarded_valid: u1,
        forwarded_slot: u32,
        forwarded_reduction: ReductionBits) ->
        DirectFoldResult<ACTOR_COUNT, PRODUCER_COUNT> {
      let (after_found, after_producer, before_found, before_producer) =
          unroll_for! (candidate, acc):
              (u32, (u1, u32, u1, u32)) in u32:0..PRODUCER_COUNT {
        let request = pending[candidate];
        let valid_slot = request.slot < ACTOR_COUNT;
        let slot = if valid_slot { request.slot } else { u32:0 };
        let private_work = state.internal_candidates[slot] ||
          state.reduction_errors[slot];
        let entry_work = state.entry_probes[slot] ||
          state.egress_waiters[slot];
        let reduction_request = request.direct_reduction;
        let eligible = pending_valid[candidate] &&
          !request.credit && reduction_request && valid_slot &&
          state.reduction_active[slot] &&
          !state.mail_candidates[slot] &&
          !private_work && !entry_work && !in_flight[slot] &&
          (!excluded_valid || slot != excluded_slot);
        let take_after = !acc.0 &&
          candidate >= state.admission_cursor && eligible;
        let take_before = !acc.2 &&
          candidate < state.admission_cursor && eligible;
        (
          acc.0 || take_after,
          if take_after { candidate } else { acc.1 },
          acc.2 || take_before,
          if take_before { candidate } else { acc.3 }
        )
      }((u1:0, u32:0, u1:0, u32:0));
      let found = after_found || before_found;
      let producer = if after_found {
        after_producer
      } else {
        before_producer
      };
      let request = pending[producer];
      let slot = if request.slot < ACTOR_COUNT {
        request.slot
      } else {
        u32:0
      };
      // An actor open can retire in the same activation as its first direct
      // contribution. Forward that newly opened word into the fold before
      // the combined register-bank write below.
      let reduction_bits = if forwarded_valid && slot == forwarded_slot {
        forwarded_reduction
      } else {
        state.reductions[slot]
      };
      let reduction = reduction_state_from_bits(reduction_bits);
      let applied = shared_reduction_sidecar_step(reduction, request.frame);
      let direct_fold_outcome = applied.outcome;
      let direct_fold_accepted = found &&
        (direct_fold_outcome == ReductionOutcome::PENDING ||
         direct_fold_outcome == ReductionOutcome::COMPLETE);
      let consumed = direct_fold_accepted;
      let complete = direct_fold_outcome == ReductionOutcome::COMPLETE;
      let fallback = found && !direct_fold_accepted;
      let fallback_request = ScheduledRequest {
        direct_reduction: u1:0,
        ..request
      };
      let next_pending = if fallback {
        update(pending, producer, fallback_request)
      } else {
        pending
      };
      let next_pending_valid = if consumed {
        update(pending_valid, producer, u1:0)
      } else {
        pending_valid
      };
      let reduction_active = if direct_fold_accepted {
        update(state.reduction_active, slot, !complete)
      } else {
        state.reduction_active
      };
      let internal_candidates = if direct_fold_accepted && complete {
        update(state.internal_candidates, slot, u1:1)
      } else {
        state.internal_candidates
      };
      let reduction_errors = state.reduction_errors;
      let cursor = if consumed {
        if producer + u32:1 == PRODUCER_COUNT {
          u32:0
        } else {
          producer + u32:1
        }
      } else {
        state.admission_cursor
      };
      DirectFoldResult<ACTOR_COUNT, PRODUCER_COUNT> {
        pending: next_pending,
        pending_valid: next_pending_valid,
        reduction: bits_from_reduction_state(applied.state),
        reduction_active,
        internal_candidates,
        reduction_errors,
        cursor,
        valid: direct_fold_accepted,
        slot,
        outcome: direct_fold_outcome,
      }
    }

    """.

retire_actor_helper() ->
    """
    fn retire_reduction_actor<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        valid: u1,
        slot: u32,
        result: SharedExecutorResult) ->
        SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      let reduction = reduction_state_from_bits(result.reduction);
      let private_work = state.internal_candidates[slot] ||
        state.reduction_errors[slot];
      let internal_candidates = if valid {
        update(
          state.internal_candidates,
          slot,
          if private_work { u1:0 }
          else { state.internal_candidates[slot] })
      } else {
        state.internal_candidates
      };
      let reduction_errors = if valid {
        update(
          state.reduction_errors,
          slot,
          if private_work { u1:0 }
          else { state.reduction_errors[slot] })
      } else {
        state.reduction_errors
      };
      // A failed main actor must never leave an apparently live sidecar.
      // Future traffic may still be admitted by the generic shared service,
      // but it must visit the failed actor rather than being folded and
      // consumed without observing that terminal state.
      let machine_failed = machine_from_bits(result.machine).failed;
      let reduction_active = if valid &&
          (result.reduction_write_valid || machine_failed) {
        update(
          state.reduction_active,
          slot,
          !machine_failed && reduction.status == ReductionStatus::OPEN)
      } else {
        state.reduction_active
      };
      let clear_probe = valid && (result.received ||
        result.phase_boundary || result.reduction_write_valid);
      let reduction_probed = if clear_probe {
        update(state.reduction_probed, slot, u1:0)
      } else {
        state.reduction_probed
      };
      SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
        internal_candidates,
        reduction_errors,
        reduction_active,
        reduction_probed,
        ..state
      }
    }

    """.

fold_retirement_helpers(aggregate_only) -> [];
fold_retirement_helpers(_Mode) ->
    """
    fn retire_reduction_fold<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        valid: u1,
        folded: FoldEnvelope) ->
        SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      let candidate = folded.outcome != ReductionOutcome::NOT_CANDIDATE;
      let mismatch = folded.outcome == ReductionOutcome::MISMATCH;
      let accepted = folded.outcome == ReductionOutcome::PENDING ||
        folded.outcome == ReductionOutcome::COMPLETE;
      let complete = folded.outcome == ReductionOutcome::COMPLETE;
      let failed = candidate && !mismatch && !accepted;
      let consumed = valid && accepted;
      let old_count = state.occupied[folded.slot];
      let occupied = if consumed {
        update(state.occupied, folded.slot, old_count - u8:1)
      } else {
        state.occupied
      };
      let compacted = compact_order(
        state.order[folded.slot], folded.order_index, old_count);
      let order = if consumed {
        update(state.order, folded.slot, compacted)
      } else {
        state.order
      };
      let marked = update(
        state.postponed[folded.slot],
        folded.mailbox_index as u32,
        u1:1);
      let postponed = if valid && mismatch {
        update(state.postponed, folded.slot, marked)
      } else {
        state.postponed
      };
      let metadata = SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
        occupied,
        order,
        postponed,
        ..state
      };
      let (mail_remaining, _, _) =
        mailbox_selection(metadata, folded.slot);
      let mail_candidates = if valid && candidate {
        update(
          state.mail_candidates,
          folded.slot,
          mail_remaining && !failed)
      } else {
        state.mail_candidates
      };
      let reduction_active = if valid && accepted {
        update(state.reduction_active, folded.slot, !complete)
      } else {
        state.reduction_active
      };
      let internal_candidates = if valid && complete {
        update(state.internal_candidates, folded.slot, u1:1)
      } else {
        state.internal_candidates
      };
      let reduction_errors = if valid && failed {
        update(state.reduction_errors, folded.slot, u1:1)
      } else {
        state.reduction_errors
      };
      let reduction_probed = if valid {
        update(
          state.reduction_probed,
          folded.slot,
          !candidate)
      } else {
        state.reduction_probed
      };
      SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
        occupied,
        order,
        postponed,
        mail_candidates,
        reduction_active,
        internal_candidates,
        reduction_errors,
        reduction_probed,
        ..state
      }
    }

    fn shared_reduction_fold_result(
        slot: u32,
        reduction_bits: ReductionBits,
        frame: axis::Frame,
        mailbox_index: u8,
        order_index: u8) -> FoldEnvelope {
      let state = reduction_state_from_bits(reduction_bits);
      let applied = shared_reduction_sidecar_step(state, frame);
      FoldEnvelope {
        slot,
        reduction: bits_from_reduction_state(applied.state),
        outcome: applied.outcome,
        mailbox_index,
        order_index,
      }
    }

    // These two depth-one channels form an elastic boundary between the
    // mailbox/reduction RAM responses and SharedService's next-state logic. The
    // relay intentionally does no computation: its storage breaks the state
    // recurrence which otherwise forces the whole service above II=1.
    proc FoldRelay {
      request_in: chan<FoldEnvelope> in;
      result_out: chan<FoldEnvelope> out;

      config(
          request_in: chan<FoldEnvelope> in,
          result_out: chan<FoldEnvelope> out
      ) {
        (request_in, result_out)
      }

      init { () }

      next(state: ()) {
        let (tok, request) = recv(join(), request_in);
        let _done = send(tok, result_out, request);
        state
      }
    }

    """.

-spec shared_fold_service_fields(reductions(), service_mode()) -> iodata().
shared_fold_service_fields(none, _Mode) -> "\n";
shared_fold_service_fields(_Reductions, ordinary) ->
    ["\n", fold_service_fields(), "\n"];
shared_fold_service_fields(_Reductions, joined) ->
    ["\n", fold_service_fields(), aggregate_service_field(), "\n"];
shared_fold_service_fields(_Reductions, aggregate_only) ->
    ["\n", aggregate_service_field(), "\n"].

fold_service_fields() ->
    """
      fold_request_out: chan<FoldEnvelope> out;
      fold_result_in: chan<FoldEnvelope> in;
    """.

aggregate_service_field() ->
    """
      aggregate_in: chan<ReductionAggregateRequest> in;
    """.

-spec shared_reduction_config_parameters(reductions(), service_mode()) ->
    iodata().
shared_reduction_config_parameters(none, _Mode) -> "\n";
shared_reduction_config_parameters(_Reductions, ordinary) -> "\n";
shared_reduction_config_parameters(_Reductions, _AggregateMode) ->
    [",\n", """
          aggregate_in: chan<ReductionAggregateRequest> in
    """, "\n"].

-spec shared_fold_config_bindings(reductions(), service_mode()) -> iodata().
shared_fold_config_bindings(none, _Mode) -> "\n";
shared_fold_config_bindings(_Reductions, aggregate_only) -> "\n";
shared_fold_config_bindings(_Reductions, _FoldMode) ->
    ["\n", """
        let (fold_request_p, fold_request_c) =
          chan<FoldEnvelope, u32:1>("fold_request");
        let (fold_result_p, fold_result_c) =
          chan<FoldEnvelope, u32:1>("fold_result");
    """, "\n"].

-spec shared_fold_config_spawn(reductions(), service_mode()) -> iodata().
shared_fold_config_spawn(none, _Mode) -> "\n";
shared_fold_config_spawn(_Reductions, aggregate_only) -> "\n";
shared_fold_config_spawn(_Reductions, _FoldMode) ->
    "\n    spawn FoldRelay(fold_request_c, fold_result_p);\n\n".

-spec shared_fold_config_endpoints(reductions(), service_mode()) -> iodata().
shared_fold_config_endpoints(none, _Mode) -> "\n";
shared_fold_config_endpoints(_Reductions, ordinary) ->
    ["\n", """
          fold_request_p,
          fold_result_c,
    """, "\n"];
shared_fold_config_endpoints(_Reductions, joined) ->
    ["\n", """
          fold_request_p,
          fold_result_c,
          aggregate_in,
    """, "\n"];
shared_fold_config_endpoints(_Reductions, aggregate_only) ->
    ["\n", """
          aggregate_in,
    """, "\n"].

-spec shared_executor_internal_request_field(reductions()) -> iodata().
shared_executor_internal_request_field(none) -> "\n";
shared_executor_internal_request_field(_Reductions) ->
    ["\n", """
              reduction: if private_active {
                reduction_bits
              } else {
                bits_from_reduction_state(ReductionState {
                  status: if direct_state.reduction_active[read_slot] {
                    ReductionStatus::OPEN
                  } else {
                    ReductionStatus::IDLE
                  },
                  ..zero!<ReductionState>()
                })
              },
              reduction_error: reduction_error_active,
              internal: internal_active,
    """, "\n"].

-spec shared_executor_request_token(reductions()) -> iodata().
shared_executor_request_token(none) ->
    "\n          join(state_done, mailbox_done),\n";
shared_executor_request_token(_Reductions) ->
    "\n          join(state_done, mailbox_done),\n".

-spec shared_ready_selection_call(reductions(), service_mode()) -> iodata().
shared_ready_selection_call(none, _Mode) ->
    [
        " ready_selection(\n",
        "          selection_state,\n",
        "          cursor,\n",
        "          issued_in_flight);\n"
    ];
shared_ready_selection_call(Reductions, joined) ->
    shared_ready_selection_call(Reductions, ordinary);
shared_ready_selection_call(_Reductions, Mode) ->
    SelectionFunction = case Mode of
        ordinary -> "reduction_ready_selection";
        aggregate_only -> "aggregate_ready_selection"
    end,
    ["\n", """
              {
              let selection_ready_metadata =
                ReductionReadyMetadata<ACTOR_COUNT> {
                internal_candidates: selection_state.internal_candidates,
                reduction_errors: selection_state.reduction_errors,
                entry_probes: selection_state.entry_probes,
                egress_waiters: selection_state.egress_waiters,
                reduction_active: selection_state.reduction_active,
                mail_candidates: selection_state.mail_candidates,
                reduction_probed: selection_state.reduction_probed,
                egress_busy: selection_state.egress_busy,
              };
    """,
        "              ", SelectionFunction, "<ACTOR_COUNT>(\n",
        "                selection_ready_metadata,\n",
        "                cursor,\n",
        "                issued_in_flight)\n",
        "              };\n",
        "\n"].

-spec shared_local_fold_bindings(reductions(), service_mode()) -> iodata().
shared_local_fold_bindings(none, _Mode) -> "\n";
shared_local_fold_bindings(_Reductions, aggregate_only) -> "\n";
shared_local_fold_bindings(Reductions, joined) ->
    shared_local_fold_bindings(Reductions, ordinary);
shared_local_fold_bindings(_Reductions, ordinary) ->
    ["\n", """
            let local_fold = shared_reduction_fold_result(
              read_slot,
              reduction_bits,
              frame,
              mailbox_index,
              order_index);
    """, "\n"].

-spec shared_blocked_probe_bindings(reductions(), service_mode()) -> iodata().
shared_blocked_probe_bindings(none, _Mode) -> [];
shared_blocked_probe_bindings(Reductions, joined) ->
    shared_blocked_probe_bindings(Reductions, ordinary);
shared_blocked_probe_bindings(_Reductions, ordinary) ->
    ["\n", """
            let final_in_flight = issued_in_flight;
            let selection_ready_metadata =
              ReductionReadyMetadata<ACTOR_COUNT> {
                internal_candidates: selection_state.internal_candidates,
                reduction_errors: selection_state.reduction_errors,
                entry_probes: selection_state.entry_probes,
                egress_waiters: selection_state.egress_waiters,
                reduction_active: selection_state.reduction_active,
                mail_candidates: selection_state.mail_candidates,
                reduction_probed: selection_state.reduction_probed,
                egress_busy: selection_state.egress_busy,
              };
            let (fold_ready, fold_slot) = reduction_fold_selection(
              selection_ready_metadata,
              cursor,
              final_in_flight);
            let ready = if completion_blocked {
              fold_ready
            } else {
              selected_ready
            };
            let next_slot = if completion_blocked {
              fold_slot
            } else {
              selected_slot
            };
            let next_fold = ready && sidecar_fold_ready(
              selection_ready_metadata, next_slot);
    """, "\n"];
shared_blocked_probe_bindings(_Reductions, aggregate_only) ->
    ["\n", """
            let final_in_flight = issued_in_flight;
            let ready = !completion_blocked && selected_ready;
            let next_slot = if completion_blocked {
              u32:0
            } else {
              selected_slot
            };
            let next_fold = u1:0;
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
    "\n          actor_issue_valid,\n".

-spec shared_fold_request_send(reductions(), service_mode()) -> iodata().
shared_fold_request_send(none, _Mode) -> "\n";
shared_fold_request_send(_Reductions, aggregate_only) -> "\n";
shared_fold_request_send(Reductions, joined) ->
    shared_fold_request_send(Reductions, ordinary);
shared_fold_request_send(_Reductions, ordinary) ->
    ["\n", """
            let fold_request_tok = send_if(
              mailbox_done,
              fold_request_out,
              fold_issue_valid && read_mailbox && received,
              local_fold);
    """, "\n"].

-spec shared_retirement_token(reductions(), service_mode()) -> iodata().
shared_retirement_token(none, _Mode) ->
    "\n          executor_result_tok,\n";
shared_retirement_token(Reductions, joined) ->
    shared_retirement_token(Reductions, ordinary);
shared_retirement_token(_Reductions, ordinary) ->
    "\n          fold_result_tok,\n";
shared_retirement_token(_Reductions, aggregate_only) ->
    "\n          executor_result_tok,\n".

-spec shared_fold_done_token(reductions(), service_mode()) -> iodata().
shared_fold_done_token(none, _Mode) -> "\n";
shared_fold_done_token(_Reductions, ordinary) ->
    ["\n", """
              fold_request_tok,
    """, "\n"];
shared_fold_done_token(_Reductions, joined) ->
    ["\n", """
              fold_request_tok,
              aggregate_tok,
    """, "\n"];
shared_fold_done_token(_Reductions, aggregate_only) ->
    ["\n", """
              aggregate_tok,
    """, "\n"].

-spec shared_in_flight_field(reductions()) -> iodata().
shared_in_flight_field(none) ->
    "\n          in_flight: issued_in_flight,\n";
shared_in_flight_field(_Reductions) ->
    "\n          in_flight: final_in_flight,\n".

-spec shared_folded_state_fields(reductions(), service_mode()) -> iodata().
shared_folded_state_fields(none, _Mode) -> "\n";
shared_folded_state_fields(Reductions, joined) ->
    shared_folded_state_fields(Reductions, ordinary);
shared_folded_state_fields(_Reductions, ordinary) ->
    ["\n", """
              next_fold,
              fold_retire_turn: if incoming_fold_valid {
                u1:0
              } else if retire_valid {
                u1:1
              } else {
                state.fold_retire_turn
              },
    """, "\n"];
shared_folded_state_fields(_Reductions, aggregate_only) ->
    "\n".

-spec shared_result_retirement_head(reductions(), service_mode()) -> iodata().
shared_result_retirement_head(none, _Mode) ->
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
shared_result_retirement_head(Reductions, joined) ->
    shared_result_retirement_head(Reductions, ordinary);
shared_result_retirement_head(_Reductions, ordinary) ->
    ["\n", """
            let buffered_can_retire = state.completed_valid &&
              (!state.completed.effects_valid || !credit_busy);
            let accept_executor_result =
              !state.completed_valid ||
              (buffered_can_retire && !state.fold_retire_turn);
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
            let ordinary_can_retire = ordinary_result_valid &&
              (!ordinary_result.effects_valid || !credit_busy);
            let (fold_result_tok, incoming_fold, incoming_fold_valid) =
              recv_if_non_blocking(
                executor_result_tok,
                fold_result_in,
                state.fold_retire_turn || !ordinary_can_retire,
                zero!<FoldEnvelope>());
            let fold_wins = incoming_fold_valid &&
              (state.fold_retire_turn || !ordinary_can_retire);
            let result = ordinary_result;
            let retire_valid = ordinary_can_retire && !fold_wins;
            let resolved = SharedStep {
              machine: machine_with_reduction(
                result.machine, result.reduction),
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
            let actor_retired0 = retire_actor(
              credited,
              retire_valid,
              result.slot,
              resolved,
              result.received,
              result.mailbox_index,
              result.order_index);
            let actor_retired = retire_reduction_actor(
              actor_retired0, retire_valid, result.slot, result);
            let metadata_retired = retire_reduction_fold(
              actor_retired,
              fold_wins,
              incoming_fold);
            let actor_reduction_write = retire_valid &&
              result.reduction_write_valid;
            let fold_accepted = fold_wins &&
              (incoming_fold.outcome == ReductionOutcome::PENDING ||
               incoming_fold.outcome == ReductionOutcome::COMPLETE);
            let reduction_write_valid =
              actor_reduction_write || fold_accepted;
            let reduction_write_slot = if actor_reduction_write {
              result.slot
            } else {
              incoming_fold.slot
            };
            let reduction_write_bits = if actor_reduction_write {
              result.reduction
            } else {
              incoming_fold.reduction
            };
            // The authoritative receptacle write is combined below with any
            // sender-addressed fold, after next-issue hazards are known.
            let retired = metadata_retired;
            // The authoritative reduction word is updated in this proc state,
            // so retirement itself closes the same-slot hazard. There is no
            // external write acknowledgment to await.
            let retired_in_flight = if retire_valid {
              update(retired.in_flight, result.slot, u1:0)
            } else {
              if fold_wins {
                update(retired.in_flight, incoming_fold.slot, u1:0)
              } else {
                retired.in_flight
              }
            };
            let completed_valid = if state.completed_valid {
              if retire_valid { incoming_valid } else { u1:1 }
            } else {
              incoming_valid && !retire_valid
            };
            let completed = if state.completed_valid {
              if retire_valid {
                incoming_result
              } else {
                state.completed
              }
            } else {
              incoming_result
            };
    """, "\n"];
shared_result_retirement_head(_Reductions, aggregate_only) ->
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
              machine: machine_with_reduction(
                result.machine, result.reduction),
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
            let actor_retired0 = retire_actor(
              credited,
              retire_valid,
              result.slot,
              resolved,
              result.received,
              result.mailbox_index,
              result.order_index);
            let retired = retire_reduction_actor(
              actor_retired0, retire_valid, result.slot, result);
            let reduction_write_valid = retire_valid &&
              result.reduction_write_valid;
            let reduction_write_slot = result.slot;
            let reduction_write_bits = result.reduction;
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
    """, "\n"].

-spec shared_issue_bindings(reductions(), service_mode()) -> iodata().
shared_issue_bindings(none, _Mode) ->
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
shared_issue_bindings(Reductions, joined) ->
    shared_issue_bindings(Reductions, ordinary);
shared_issue_bindings(_Reductions, ordinary) ->
    ["\n", """
            let prior_read_slot = if state.next_valid {
              state.next_slot
            } else {
              u32:0
            };
            let prior_issue_valid = state.next_valid &&
              (!completion_blocked || state.next_fold);
    """, "\n"];
shared_issue_bindings(_Reductions, aggregate_only) ->
    ["\n", """
            let prior_read_slot = if state.next_valid {
              state.next_slot
            } else {
              u32:0
            };
            let prior_issue_valid = state.next_valid && !completion_blocked;
    """, "\n"].

join_with(_Separator, []) ->
    [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].

uppercase(Atom) ->
    string:uppercase(atom_to_list(Atom)).
