-module(xls_shared_gather_codegen).
-moduledoc "Shared indexed-gather state codecs and transient completion injection.".
-export([enabled/1, progress_width/1, storage_width/1,
    machine_decode_field/3, machine_encode_prefix/1, helpers/1,
    shared_dispatch/2, state_fields/1, selection_helpers/1, issue_bindings/1, retire/1]).

-doc "Reports whether the checked actor specification declares any indexed gather.".
-spec enabled(map()) -> boolean().
enabled(Spec) -> maps:get(gathers, Spec, none) =/= none.

-doc "Returns progress bits independently of the ordered element payload.".
-spec progress_width(map()) -> non_neg_integer().
progress_width(Spec) ->
    xls_statem_gather_codegen:progress_width(maps:get(gathers, Spec, none)).

-doc "Returns circulating storage: full ordinary state or progress alone with physical collection.".
-spec storage_width(map()) -> non_neg_integer().
storage_width(Spec) ->
    Gathers = maps:get(gathers, Spec, none),
    case maps:get(gather_collection, Spec, false) of
        true -> xls_statem_gather_codegen:progress_width(Gathers);
        false -> xls_statem_gather_codegen:storage_width(Gathers)
    end.

-doc "Decodes the declared gather slice; physical collection reconstructs no stored payload copy.".
-spec machine_decode_field(map(), non_neg_integer(), non_neg_integer()) -> iodata().
machine_decode_field(Spec, Start, End) ->
    case enabled(Spec) of
        false -> [];
        true ->
            Width = storage_width(Spec),
            case End - Start =:= Width of
                true -> ok;
                false -> error({gather_storage_width, Width, End - Start})
            end,
            Slice = ["raw[", integer_to_list(Start), ":", integer_to_list(End), "]"],
            case maps:get(gather_collection, Spec, false) of
                false -> ["    gather: gather_state_from_bits(", Slice, "),\n"];
                true -> ["    gather: GatherState { progress: gather_progress_from_bits(",
                    Slice, "), values: zero!<GatherValues>() },\n"]
            end
    end.

-doc "Encodes the gather slice before the lower-order reduction and actor fields.".
-spec machine_encode_prefix(map()) -> iodata().
machine_encode_prefix(Spec) ->
    case {enabled(Spec), maps:get(gather_collection, Spec, false)} of
        {false, _} -> [];
        {true, false} -> "  bits_from_gather_state(machine.gather) ++\n";
        {true, true} -> "  bits_from_gather_progress(machine.gather.progress) ++\n"
    end.

-doc "Emits a checked transient completion helper and ordinary fused-contribution dispatch.".
-spec helpers(map()) -> iodata().
helpers(Spec) ->
    case enabled(Spec) of
        false -> [];
        true -> [completion_helper(), ordinary_helper(Spec)]
    end.

-doc "Prioritizes complete views and ordinary indexed contributions before scalar or mailbox dispatch.".
-spec shared_dispatch(map(), iodata()) -> iodata().
shared_dispatch(Spec, Ordinary) ->
    case {enabled(Spec), maps:get(gather_collection, Spec, false)} of
        {false, _} -> Ordinary;
        {true, true} -> Ordinary;
        {true, false} -> [
            "  let gathered = if !hls_failure::failed(machine.failure) &&\n",
            "      !machine.enter_pending && machine.gather.progress.status == GatherStatus::COMPLETE {\n",
            "    shared_machine_complete_gather(machine, machine.gather.progress, machine.gather.values)\n",
            "  } else if request.received",
            xls_statem_event_codegen:optional(Spec, " && machine.next_event == u8:0"), " {\n",
            "    shared_machine_gather_dispatch(machine, request.frame)\n",
            "  } else { ActorDispatch { machine, ..zero!<ActorDispatch>() } };\n",
            "  let selected_gather = gathered.dispatched ||\n",
            "    (!hls_failure::failed(machine.failure) && hls_failure::failed(gathered.machine.failure));\n",
            "  let dispatched = if selected_gather { gathered } else {\n",
            Ordinary,
            "    dispatched\n  };\n"
        ]
    end.

%% The public consumer owns callback result semantics, including repeat, failure and continuation.
-spec completion_helper() -> iodata().
completion_helper() ->
    """
    // Consume one checked complete view without requiring its values in circulating MachineBits.
    fn shared_machine_complete_gather(
        machine: ActorState, progress: GatherProgress, values: GatherValues) -> ActorDispatch {
      let valid = !hls_failure::failed(machine.failure) && !machine.enter_pending &&
        progress.status == GatherStatus::COMPLETE;
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
        let hydrated = ActorState { gather: GatherState { progress, values }, ..machine };
        actor_gather_complete(hydrated)
      }
    }

    """.

%% Contribution extraction shares the ordinary callback predicates and never folds accepted values.
-spec ordinary_helper(map()) -> iodata().
ordinary_helper(Spec = #{message_names := Names, message_words := Words}) ->
    ["""
    // Recognize indexed input before ordinary/scalar dispatch; fuse its last member with completion.
    fn shared_machine_gather_dispatch(machine: ActorState, frame: axis::Frame) -> ActorDispatch {
      let tag_ok =
    """, xls_statem_reply_codegen:optional(Spec, "!is_call(frame.header.op) && ("),
        xls_actor_codegen:input_tag_ok(Spec, Names, Words),
        xls_statem_reply_codegen:optional(Spec, ")"), ";\n", """
      if hls_failure::failed(machine.failure) || machine.enter_pending || !tag_ok {
        ActorDispatch { machine, ..zero!<ActorDispatch>() }
      } else {
        let applied = gather_apply(
          machine.gather, gather_contribution(frame, machine.phase, machine.data));
        let outcome = applied.outcome;
        if outcome == GatherOutcome::NOT_CANDIDATE {
          ActorDispatch { machine, ..zero!<ActorDispatch>() }
        } else if outcome == GatherOutcome::COMPLETE {
          shared_machine_complete_gather(machine, applied.state.progress, applied.state.values)
        } else if outcome == GatherOutcome::PENDING {
          ActorDispatch {
            machine: ActorState { gather: applied.state, ..machine },
            directive: Directive::CONSUME,
            dispatched: u1:1,
            ..zero!<ActorDispatch>()
          }
        } else if outcome == GatherOutcome::MISMATCH {
          ActorDispatch { machine, directive: Directive::POSTPONE,
            dispatched: u1:1, ..zero!<ActorDispatch>() }
        } else {
          ActorDispatch {
            machine: ActorState {
              failure: hls_failure::first(machine.failure, hls_failure::REDUCTION_PROTOCOL),
              ..machine
            },
            directive: Directive::FAIL,
            dispatched: u1:1,
            ..zero!<ActorDispatch>()
          }
        }
      }
    }

    """].

-doc "Adds ordinary completion wakeups; physical collection owns its separate candidate flags.".
-spec state_fields(map()) -> iodata().
state_fields(Spec) ->
    case {enabled(Spec), maps:get(gather_collection, Spec, false)} of
        {true, false} -> ["  gather_candidates: u1[ACTOR_COUNT],\n", xls_collection_observation:state_fields(Spec)];
        _ -> []
    end.

-doc "Combines scalar and gather readiness under the existing actor fairness and reservation policy.".
-spec selection_helpers(map()) -> iodata().
selection_helpers(Spec) ->
    case enabled(Spec) of
        false -> [];
        true -> [
            "fn gather_ready_selection<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(\n",
            "    state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,\n",
            "    cursor: u32, in_flight: u1[ACTOR_COUNT]) -> (u1, u32) {\n",
            "  let internal = unroll_for! (slot, internal):\n",
            "      (u32, u1[ACTOR_COUNT]) in u32:0..ACTOR_COUNT {\n",
            "    update(internal, slot, ", scalar_candidate(Spec, "slot"),
            " || state.", candidate_field(Spec), "[slot])\n",
            "  }(zero!<u1[ACTOR_COUNT]>());\n",
            "  scheduler::select(scheduler::Candidates<ACTOR_COUNT> {\n",
            "    entry: state.entry_probes, mail: state.mail_candidates,\n",
            "    egress: state.egress_waiters, internal,\n",
            case has_aggregate(Spec) of
                true -> "    aggregate: state.aggregate_pending_valid,\n";
                false -> []
            end,
            "    ..zero!<scheduler::Candidates<ACTOR_COUNT>>()\n",
            "  }, state.egress_busy, scheduler::exclude_reserved(in_flight, state.outbox_busy), cursor)\n",
            "}\n\n"
        ]
    end.

-doc "Issues private completions before mailbox reads while retaining aggregate service precedence.".
-spec issue_bindings(map()) -> iodata().
issue_bindings(Spec) ->
    case enabled(Spec) of
        false -> xls_shared_reduction_service_codegen:shared_issue_bindings(
            maps:get(reductions, Spec, none), maps:get(shared_service, Spec, ordinary));
        true -> [
            "        let (ready, read_slot) = gather_ready_selection(state, state.cursor as u32, state.in_flight);\n",
            "        let issue_valid = ready;\n",
            "        let internal_active = issue_valid && ", scalar_candidate(Spec, "read_slot"), ";\n",
            "        let gather_active = issue_valid && state.", candidate_field(Spec), "[read_slot];\n",
            "        let private_active = internal_active || gather_active;\n",
            case has_aggregate(Spec) of
                true -> [
                    "        let aggregate_active = issue_valid && !private_active && state.aggregate_pending_valid[read_slot];\n",
                    "        let private_active = private_active || aggregate_active;\n"];
                false -> []
            end,
            "        let entry_active = private_active || state.entry_probes[read_slot] ||\n",
            "          state.egress_waiters[read_slot];\n",
            "        let read_mailbox = issue_valid && !entry_active && state.mail_candidates[read_slot];\n"
        ]
    end.

-doc "Updates only a valid retiring actor's ordinary completion shadow after the common retirement step.".
-spec retire(map()) -> iodata().
retire(Spec) ->
    case {enabled(Spec), maps:get(gather_collection, Spec, false)} of
        {true, false} -> [
            "        let gather_candidates = if retire_valid {\n"
            "          update(retired.gather_candidates, result.slot,\n"
            "            resolved.machine.gather.progress.status == GatherStatus::COMPLETE &&\n"
            "              !hls_failure::failed(resolved.machine.failure))\n"
            "        } else { retired.gather_candidates };\n"
            "        let retired = SharedState<ACTOR_COUNT, PRODUCER_COUNT> { gather_candidates, ..retired };\n",
            xls_collection_observation:retire(Spec)];
        _ -> []
    end.

%% The physical adapter owns indexed candidate storage and ordinary actors own the local shadow.
-spec candidate_field(map()) -> string().
candidate_field(Spec) ->
    case maps:get(gather_collection, Spec, false) of
        true -> "indexed_candidates";
        false -> "gather_candidates"
    end.

%% Gather-only actors have no scalar completion field in their shared state.
-spec scalar_candidate(map(), string()) -> iodata().
scalar_candidate(Spec, Slot) ->
    case maps:get(reductions, Spec, none) of
        none -> "false";
        _ -> ["state.internal_candidates[", Slot, "]"]
    end.

%% Aggregate pending state exists only for actors with the scalar aggregate service enabled.
-spec has_aggregate(map()) -> boolean().
has_aggregate(Spec) ->
    maps:get(reductions, Spec, none) =/= none andalso
        maps:get(shared_service, Spec, ordinary) =:= aggregate_only.
