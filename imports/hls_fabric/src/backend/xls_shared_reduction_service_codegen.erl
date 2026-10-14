-module(xls_shared_reduction_service_codegen).
-moduledoc false.
-export([shared_dispatch_effective_binding/3, shared_dispatch_failed_binding/3, shared_dispatch_dispatched_field/3, shared_entry_step/2, shared_machine_support/3]).
-export([machine_decode_field/3, machine_encode_prefix/1, shared_state_fields/2, shared_executor_request_field/2, shared_machine_support/2, shared_dispatch_bindings/3, shared_dispatch_effective_binding/2, shared_dispatch_failed_binding/2, shared_dispatch_reduction_field/2, shared_dispatch_dispatched_field/2, shared_entry_step/1, shared_executor_dispatch/2, shared_service_helpers/2, shared_retire_binding/2, shared_issue_bindings/2, shared_executor_request_value/2, shared_proc_field/2, shared_config_parameter/2, shared_config_endpoint/2, shared_capture/2, shared_capture_token/2, shared_state_source/2, shared_post_issue_state/2, shared_post_issue_state_name/2]).
%% Checked actor reduction declarations, or absence of reduction support.
-type reductions() :: none | xls_statem_reduction_ir:reduction().
%% Ordinary frame delivery or precombined aggregate delivery.
-type service_mode() :: ordinary | aggregate_only.


-doc "Extracts private reduction metadata from the packed actor-state row.".
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

-doc "Prepends private reduction metadata to the actor-state row.".
-spec machine_encode_prefix(reductions()) -> iodata().
machine_encode_prefix(none) ->
    [];
machine_encode_prefix(_Reductions) ->
    "  bits_from_reduction_state(machine.reduction) ++\n".

-doc "Adds held-aggregate state only for aggregate-only services.".
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

-doc "Adds the optional aggregate payload to an accepted-work request.".
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
%%% SharedService actor execution
%%%

-doc "Emits completion and aggregate acceptance helpers for shared actors.".
-spec shared_machine_support(reductions(), service_mode()) -> iodata().
shared_machine_support(Reductions, Mode) -> shared_machine_support(Reductions, Mode, #{}).

-doc "Preserves pending continuations, accepts one new completion event and fails conflicting requests atomically.".
-spec shared_machine_support(reductions(), service_mode(), map()) -> iodata().
shared_machine_support(none, _Mode, _Spec) ->
    [];
shared_machine_support(_Reductions, Mode, Spec) ->
    ["""
    fn shared_machine_complete(machine: ActorState) -> ActorDispatch {
      let valid = !hls_failure::failed(machine.failure) && !machine.enter_pending &&
        machine.reduction.status == ReductionStatus::COMPLETE;
      if !valid {
        ActorDispatch {
          machine: ActorState {
            failure: hls_failure::first(machine.failure, hls_failure::REDUCTION_PROTOCOL),
            ..machine
          },
          directive: Directive::FAIL,
          dispatched: u1:1,
          ..zero!<ActorDispatch>()
        }
      } else {
        let completed = reduction_dispatch_completion(
          machine.reduction, machine.phase, machine.data);
    """, "\n", xls_statem_event_codegen:completion_bindings(Spec, "completed.next_event"), """
        let invalid_repeat = completed.repeat_phase &&
          (completed.directive != Directive::CONSUME ||
           completed.phase != machine.phase);
    """, "\n    let effective = completed.dispatched && !invalid_repeat", xls_statem_event_codegen:optional(Spec, " && !hls_failure::failed(completion_event_failure)"), ";\n", """
        let phase_boundary = effective &&
          completed.directive != Directive::FAIL &&
          (completed.phase != machine.phase || completed.repeat_phase);
    """, "\n    let failure = ", xls_statem_event_codegen:optional(Spec, "hls_failure::first("), "hls_failure::completion(\n",
        "      completed.dispatched, invalid_repeat, completed.failure)",
        xls_statem_event_codegen:optional(Spec, ", completion_event_failure)"), ";\n", """
        let failed = hls_failure::failed(failure);
        let next_machine = ActorState {
          phase: if effective { completed.phase } else { machine.phase },
          entered_from: if phase_boundary {
            machine.phase
          } else { machine.entered_from },
          data: if effective { completed.data } else { machine.data },
          reduction: completed.reduction,
    """, "\n", xls_statem_event_codegen:optional(Spec,
        "      next_event: if effective && !failed { completion_event } else { u8:0 },\n"), """
          enter_pending: phase_boundary && !failed,
          failure,
          ..machine
        };
        ActorDispatch {
          machine: next_machine,
          dispatched: completed.dispatched && !invalid_repeat,
          directive: completed.directive,
          phase_boundary,
          ..zero!<ActorDispatch>()
        }
      }
    }

    """, shared_machine_accept_aggregate(Mode)].

%% Select completion inputs before the callback, so internal and aggregate
%% requests share one arithmetic datapath. Rejection preserves data/reduction
%% state and records a failure.
-spec shared_machine_accept_aggregate(service_mode()) -> iodata().
shared_machine_accept_aggregate(ordinary) ->
    [];
shared_machine_accept_aggregate(aggregate_only) ->
    """
    fn shared_machine_accept_aggregate(
        machine: ActorState,
        request: ReductionAggregateRequest,
        slot: u32) -> ActorState {
      let applied = reduction_apply_complete_aggregate(
        machine.reduction, request.aggregate);
      let accepted = !hls_failure::failed(machine.failure) && !machine.enter_pending &&
        request.slot == slot &&
        applied.outcome == ReductionOutcome::COMPLETE;
      if accepted {
        ActorState {
          reduction: applied.state,
          ..machine
        }
      } else {
        ActorState {
          failure: hls_failure::first(machine.failure, hls_failure::REDUCTION_PROTOCOL),
          ..machine
        }
      }
    }

    """.

-doc "Binds a shared callback result while preserving reduction dispatch precedence.".
-spec shared_dispatch_bindings(reductions(), service_mode(), map()) -> iodata().
shared_dispatch_bindings(none, _Mode, Events) ->
    [
        "    let (next_phase, next_data, directive, repeat_phase, dispatch_failure", xls_statem_reduction_service_codegen:event_tail(Events, "next_event"), ") =\n",
        "      if tag_ok {\n",
        "        dispatch(frame, machine.phase, machine.data", xls_statem_reply_codegen:optional(Events, ", call_from, call_error"), ")\n",
        "      } else {\n",
        "        (machine.phase, machine.data, Directive::FAIL, u1:0, hls_failure::REDUCTION_PROTOCOL", xls_statem_reduction_service_codegen:event_tail(Events, "u8:0"), ")\n",
        "      };\n"
    ];
shared_dispatch_bindings(_Reductions, aggregate_only, Events) ->
    %% A source-fragment artifact receives contribution messages only through
    %% its aggregate port. Any such frame on an ordinary mailbox is therefore
    %% handled by the actor's ordinary dispatch table (normally as an error).
    shared_dispatch_bindings(none, ordinary, Events);
shared_dispatch_bindings(_Reductions, ordinary, Events) ->
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
        "    let (next_phase, next_data, directive, repeat_phase, dispatch_failure", xls_statem_reduction_service_codegen:event_tail(Events, "next_event"), ") =\n",
        "      if !tag_ok {\n",
        "        (machine.phase, machine.data, Directive::FAIL, u1:0, hls_failure::REDUCTION_PROTOCOL", xls_statem_reduction_service_codegen:event_tail(Events, "u8:0"), ")\n",
        "      } else if !reduction_candidate {\n",
        "        dispatch(frame, machine.phase, machine.data", xls_statem_reply_codegen:optional(Events, ", call_from, call_error"), ")\n",
        "      } else if reduction_mismatch {\n",
        "        (machine.phase, machine.data, ",
        "Directive::POSTPONE, u1:0, hls_failure::NONE", xls_statem_reduction_service_codegen:event_tail(Events, "u8:0"), ")\n",
        "      } else if reduction_accepted {\n",
        "        (machine.phase, machine.data, ",
        "Directive::CONSUME, u1:0, hls_failure::NONE", xls_statem_reduction_service_codegen:event_tail(Events, "u8:0"), ")\n",
        "      } else {\n",
        "        (machine.phase, machine.data, Directive::FAIL, u1:0, hls_failure::REDUCTION_PROTOCOL", xls_statem_reduction_service_codegen:event_tail(Events, "u8:0"), ")\n",
        "      };\n",
        "    let next_reduction = if reduction_accepted {\n",
        "      reduction_applied.state\n",
        "    } else { machine.reduction };\n"
    ].

-doc "Selects aggregate or ordinary work for the accepted request.".
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

-doc "Rejects phase changes or repeats while either declared collection remains incomplete.".
-spec shared_dispatch_effective_binding(reductions(), service_mode(), map()) -> iodata().
shared_dispatch_effective_binding(Reductions, Mode, Spec) ->
    case maps:get(gathers, Spec, none) of
        none -> shared_dispatch_effective_binding(Reductions, Mode);
        _ -> [
            "    let callback_effective = tag_ok && !invalid_repeat;\n",
            "    let requested_boundary = callback_effective &&\n",
            "      (next_phase != machine.phase || repeat_phase);\n",
            "    let incomplete_boundary = requested_boundary &&\n",
            "      directive != Directive::FAIL && (machine.gather.progress.status == GatherStatus::OPEN",
            case Reductions of none -> []; _ -> " || machine.reduction.status == ReductionStatus::OPEN" end,
            ");\n",
            "    let effective = callback_effective && !incomplete_boundary;\n"
        ]
    end.

-doc "Propagates the selected dispatch failure before committing state.".
-spec shared_dispatch_failed_binding(reductions(), service_mode()) -> iodata().
shared_dispatch_failed_binding(Reductions, _Mode) ->
    [
        "    let failure = hls_failure::dispatch(!tag_ok, invalid_repeat, ",
        case Reductions of none -> "false"; _ -> "incomplete_boundary" end,
        ", effective, dispatch_failure);\n",
        "    let failed = hls_failure::failed(failure);\n"
    ].

-doc "Propagates incomplete gather boundaries with the existing scalar protocol-failure priority.".
-spec shared_dispatch_failed_binding(reductions(), service_mode(), map()) -> iodata().
shared_dispatch_failed_binding(Reductions, Mode, Spec) ->
    case maps:get(gathers, Spec, none) of
        none -> shared_dispatch_failed_binding(Reductions, Mode);
        _ ->
            "    let failure = hls_failure::dispatch(!tag_ok, invalid_repeat, incomplete_boundary, effective, dispatch_failure);\n"
            "    let failed = hls_failure::failed(failure);\n"
    end.

-doc "Chooses the reduction state produced by the selected dispatch path.".
-spec shared_dispatch_reduction_field(reductions(), service_mode()) -> iodata().
shared_dispatch_reduction_field(none, _Mode) ->
    [];
shared_dispatch_reduction_field(_Reductions, aggregate_only) ->
    [];
shared_dispatch_reduction_field(_Reductions, ordinary) ->
    "      reduction: next_reduction,\n".

-doc "Reports whether ordinary or aggregate work was actually consumed.".
-spec shared_dispatch_dispatched_field(reductions(), service_mode()) ->
    iodata().
shared_dispatch_dispatched_field(none, _Mode) ->
    "      dispatched: tag_ok && !invalid_repeat,\n";
shared_dispatch_dispatched_field(_Reductions, _Mode) ->
    [
        "      dispatched: tag_ok && !invalid_repeat &&\n",
        "        !incomplete_boundary,\n"
    ].

-doc "Does not consume an input whose requested boundary violates an active collection.".
-spec shared_dispatch_dispatched_field(reductions(), service_mode(), map()) -> iodata().
shared_dispatch_dispatched_field(Reductions, Mode, Spec) ->
    case maps:get(gathers, Spec, none) of
        none -> shared_dispatch_dispatched_field(Reductions, Mode);
        _ -> "      dispatched: tag_ok && !invalid_repeat && !incomplete_boundary,\n"
    end.

-doc "Applies a checked phase entry while respecting batch capacity.".
-spec shared_entry_step(reductions()) -> iodata().
shared_entry_step(Reductions) ->
    shared_entry_step_code(Reductions, xls_statem_reduction_service_codegen:entry_bindings(Reductions), []).

-doc "Commits a gather opening only with its successful complete entry and enforces collection exclusivity.".
-spec shared_entry_step(reductions(), map()) -> iodata().
shared_entry_step(Reductions, Spec) ->
    case maps:get(gathers, Spec, none) of
        none -> shared_entry_step(Reductions);
        _ -> shared_entry_step_code(Reductions, xls_statem_gather_codegen:entry_bindings(Spec),
            "      gather: if entry_failed { machine.gather } else { entered_gather },\n")
    end.

%% Scalar-only emission remains byte-identical; additional collection fields share its transaction boundary.
-spec shared_entry_step_code(reductions(), iodata(), iodata()) -> iodata().
shared_entry_step_code(Reductions, EntryBindings, GatherField) ->
    [
        "    let outcome = enter(\n",
        "      machine.entered_from, machine.phase, machine.data);\n",
        "    let effects = outcome.effects;\n",
        "    let effects_valid = entry_effects_valid(effects);\n",
        EntryBindings,
        "    let can_advance = !entry_failed && (!effects_valid || egress_ready);\n",
        "    let advanced_machine = ActorState {\n",
        "      data: if entry_failed { machine.data } else { outcome.data },\n",
        shared_entry_reduction_field(Reductions), GatherField,
        "      enter_pending: u1:0,\n",
        "      failure: entry_failure,\n",
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

%% Commits the selected reduction open with successful entry work.
-spec shared_entry_reduction_field(term()) -> iodata().
shared_entry_reduction_field(none) ->
    [];
shared_entry_reduction_field(_Reductions) ->
    [
        "      reduction: if entry_failed { machine.reduction }\n",
        "        else { entered_reduction },\n"
    ].

-doc "Emits shared dispatch, prioritizing internal completion over aggregates and mail.".
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
        "  let completion_machine = if request.internal { machine } else {\n",
        "    shared_machine_accept_aggregate(\n",
        "      machine, request.aggregate_request, request.slot)\n",
        "  };\n",
        "  let dispatched = if request.internal || request.aggregate_valid {\n",
        "    shared_machine_complete(completion_machine)\n",
        "  } else {\n",
        "    shared_machine_dispatch(\n",
        "      machine, request.frame, request.received)\n",
        "  };\n"
    ].

%%%
%%% SharedService scheduling
%%%

%% Selects reduction work without borrowing another actor's reserved output space.
-doc "Emits selection and retirement helpers for ordinary or aggregated reduction scheduling.".
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
        }, state.egress_busy, scheduler::exclude_reserved(in_flight, state.outbox_busy), cursor)
    }

    fn retire_reduction_actor<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        valid: u1,
        slot: u32,
        machine: ActorState) ->
        SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      let internal_candidates = if valid {
        update(
          state.internal_candidates,
          slot,
          machine.reduction.status == ReductionStatus::COMPLETE &&
            !hls_failure::failed(machine.failure))
      } else {
        state.internal_candidates
      };
      SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
        internal_candidates,
        ..state
      }
    }

    """].

-doc "Publishes the reduction state produced by retiring work.".
-spec shared_retire_binding(reductions(), iodata()) -> iodata().
shared_retire_binding(none, Binding) ->
    [
        "        let ", Binding, " = retire_actor(\n",
        "          credited,\n",
        "          retire_valid,\n",
        "          result.slot,\n",
        "          resolved,\n",
        "          result.received,\n",
        "          result.mailbox_index,\n",
        "          result.order_index);\n"
    ];
shared_retire_binding(_Reductions, Binding) ->
    ["        let ", Binding, " = retire_reduction_actor(\n",
    "          retire_actor(\n"
    "            credited, retire_valid, result.slot, resolved,\n"
    "            result.received, result.mailbox_index,\n"
    "            result.order_index),\n"
    "          retire_valid, result.slot, resolved.machine);\n"].

-doc "Chooses ready ordinary or aggregate work for the selected actor.".
-spec shared_issue_bindings(reductions(), service_mode()) -> iodata().
shared_issue_bindings(Reductions, Mode) ->
    Select = case Reductions of none -> "ready_selection"; _ -> "reduction_ready_selection" end,
    ["        let (ready, read_slot) = ", Select, "(state, state.cursor as u32, shared_write_mask(state));\n",
     "        let issue_valid = ready;\n",
     case Reductions of
         none -> "        let private_active = false;\n";
         _ -> ["        let internal_active = issue_valid && state.internal_candidates[read_slot];\n",
               case Mode of
                   ordinary -> "        let private_active = internal_active;\n";
                   aggregate_only -> [
                       "        let aggregate_active = issue_valid && !internal_active &&\n",
                       "          state.aggregate_pending_valid[read_slot];\n",
                       "        let private_active = internal_active || aggregate_active;\n"]
               end]
     end,
     "        let entry_active = private_active || state.entry_probes[read_slot] ||\n",
     "          state.egress_waiters[read_slot];\n",
     "        let read_mailbox = issue_valid && !entry_active && state.mail_candidates[read_slot];\n"].

-doc "Copies held aggregate data into the accepted-work ticket.".
-spec shared_executor_request_value(reductions(), service_mode()) -> iodata().
shared_executor_request_value(none, _Mode) ->
    [];
shared_executor_request_value(_Reductions, ordinary) ->
    "              internal: internal_active,\n";
shared_executor_request_value(_Reductions, aggregate_only) ->
    [
        "              internal: internal_active,\n",
        "              aggregate_request:\n",
        "                state.aggregate_pending[read_slot],\n",
        "              aggregate_valid: aggregate_active,\n"
    ].

-doc "Declares the aggregate input only for aggregate-only services.".
-spec shared_proc_field(reductions(), service_mode()) -> iodata().
shared_proc_field(_Reductions, ordinary) ->
    "\n";
shared_proc_field(_Reductions, aggregate_only) ->
    "\n      aggregate_in: chan<ReductionAggregateRequest> in;\n".

-doc "Adds the aggregate input to the service constructor.".
-spec shared_config_parameter(reductions(), service_mode()) -> iodata().
shared_config_parameter(_Reductions, ordinary) ->
    "\n";
shared_config_parameter(_Reductions, aggregate_only) ->
    [
        ",\n",
        "          aggregate_in: chan<ReductionAggregateRequest> in\n"
    ].

-doc "Retains the aggregate input in the configured service.".
-spec shared_config_endpoint(reductions(), service_mode()) -> iodata().
shared_config_endpoint(_Reductions, ordinary) ->
    "\n";
shared_config_endpoint(_Reductions, aggregate_only) ->
    "\n          aggregate_in,\n".

-doc "Receives an aggregate only when its holding slot is free.".
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
              failure: hls_failure::REDUCTION_PROTOCOL,
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

-doc "Orders state-dependent aggregate handling after its accepted receive.".
-spec shared_capture_token(reductions(), service_mode()) -> iodata().
shared_capture_token(_Reductions, ordinary) ->
    "capture_tok";
shared_capture_token(_Reductions, aggregate_only) ->
    "aggregate_tok".

-doc "Selects the current captured aggregate state before issuing work.".
-spec shared_state_source(reductions(), service_mode()) -> iodata().
shared_state_source(_Reductions, ordinary) ->
    "state";
shared_state_source(_Reductions, aggregate_only) ->
    "aggregate_state".

-doc "Releases captured aggregate storage only after the corresponding issue.".
-spec shared_post_issue_state(reductions(), service_mode()) -> iodata().
shared_post_issue_state(_Reductions, ordinary) ->
    "\n";
shared_post_issue_state(_Reductions, aggregate_only) ->
    ["\n", """
        let post_issue_state = SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
          // A duplicate captured at transfer carries a protocol failure. Keep
          // that replacement pending instead of discarding it with the ticket.
          aggregate_pending_valid: scheduler::release_pending(
            admitted.aggregate_pending_valid, aggregate_active, read_slot,
            incoming_aggregate_valid, aggregate_slot),
          ..admitted
        };
    """, "\n"].

-doc "Names the aggregate state retained after work issue.".
-spec shared_post_issue_state_name(reductions(), service_mode()) -> iodata().
shared_post_issue_state_name(_Reductions, ordinary) ->
    "admitted";
shared_post_issue_state_name(_Reductions, aggregate_only) ->
    "post_issue_state".
