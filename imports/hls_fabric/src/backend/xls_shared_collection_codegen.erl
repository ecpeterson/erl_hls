-module(xls_shared_collection_codegen).
-moduledoc "Selects opportunistic admission capture or explicitly asserted exclusive epoch collection.".
-export([validate/2, requirements/3, helpers/1, state_fields/1, ticket_field/1,
    ticket_value/1, loader_value/1, retire/1, retire_binding/1, admit/1, admission_guard/1, commit/1, resolve/1, selection/1, issue/1, capture/1, captured_field/1]).

-doc "Requires an ordinary reduced actor; collection never replaces aggregate-only delivery.".
-spec validate(map(), map()) -> ok.
validate(Spec, Options) ->
    case maps:get(admission_reductions, Options, false) of
        false -> ok;
        Mode when Mode =:= true; Mode =:= exclusive_epoch ->
            case {maps:get(shared_service, Options, ordinary), maps:get(reductions, Spec, none),
                    xls_statem_reply_codegen:enabled(Spec)} of
                {ordinary, R, false} when is_map(R), Mode =:= true -> ok;
                {ordinary, R, false} when is_map(R) -> xls_exclusive_collection_codegen:validate(R);
                _ -> error(admission_reductions_require_ordinary_reduced_actor)
            end;
        Other -> error({admission_reductions, Other})
    end.

-doc "Requires one collector policy per shared module and excludes direct instances of selected modules.".
-spec requirements([map()], [map()], map()) -> map().
requirements(Groups, Direct, Requirements) ->
    lists:foldl(fun(Module, Acc) ->
        Flags = lists:usort([maps:get(admission_reductions, G, false) ||
            G = #{module := M} <- Groups, M =:= Module]),
        case Flags of
            [false] -> Acc;
            [Mode] when Mode =:= true; Mode =:= exclusive_epoch ->
                case lists:any(fun(#{module := M}) -> M =:= Module end, Direct) of
                    true -> error({admission_reductions_direct_instance, Module});
                    false -> Acc#{Module := (maps:get(Module, Acc))#{admission_reductions => Mode}}
                end;
            _ -> error({admission_reductions_module_policy, Module})
        end
    end, Requirements, lists:usort([M || #{module := M} <- Groups])).

-doc "Adds the authoritative collector context; XLS removes callback fields unused by contribution selection.".
-spec state_fields(map()) -> iodata().
state_fields(#{admission_reductions := exclusive_epoch}) ->
    template("exclusive_collection_fields.x.in");
state_fields(Spec) -> optional(Spec,
    "  collection_context: ActorState[ACTOR_COUNT],\n  collection_initialized: bool[ACTOR_COUNT],\n").

-doc "Freezes the authoritative reduction with the actor's dispatch reservation.".
-spec ticket_field(map()) -> iodata().
ticket_field(#{admission_reductions := exclusive_epoch}) ->
    "  collection: ReductionState,\n  collection_failure: hls_failure::Code,\n";
ticket_field(Spec) -> optional(Spec, "  collection: ReductionState,\n").

-doc "Copies the committed collector state before transferring actor ownership.".
-spec ticket_value(map()) -> iodata().
ticket_value(#{admission_reductions := exclusive_epoch}) ->
    "              collection: if state.collection_owners.opened[read_slot] && state.collection_context[read_slot].reduction.status == ReductionStatus::COMPLETE { state.collection_context[read_slot].reduction } else { zero!<ReductionState>() },\n              collection_failure: state.collection_context[read_slot].failure,\n";
ticket_value(Spec) -> optional(Spec,
    "              collection: state.collection_context[read_slot].reduction,\n").

-doc "Replaces the RAM snapshot's reduction bits before the executor sees ordinary or completion work.".
-spec loader_value(map()) -> iodata().
loader_value(#{admission_reductions := exclusive_epoch}) ->
    "collection_machine_bits(machine.data, ticket.collection, ticket.collection_failure)";
loader_value(Spec) ->
    case enabled(Spec) of
        false -> "machine.data";
        true -> "collection_machine_bits(machine.data, ticket.collection)"
    end.

-doc "Emits collection admission and authoritative-state handoff functions without changing callback semantics.".
-spec helpers(map()) -> iodata().
helpers(Spec = #{admission_reductions := exclusive_epoch}) ->
    xls_exclusive_collection_codegen:helpers(Spec);
helpers(Spec = #{message_names := Names, message_words := Words}) ->
    case enabled(Spec) of
        false -> [];
        true ->
            R = maps:get(reductions, Spec),
            #{reduction := #{offset := Start}, width := End} =
                xls_shared_codegen:shared_machine_layout(xls_state_projection:width(Spec),
                    xls_statem_reduction_codegen:private_width(R)),
            HasTail = maps:get(continuations, Spec, []) =/= [],
            ["// RAM retains the last executor result, not current collection progress.\n",
             "fn collection_machine_bits(raw: MachineBits, reduction: ReductionState) -> MachineBits {\n  ",
             case HasTail of true -> ["raw[", integer_to_list(End), ":] ++ "]; false -> [] end,
             "bits_from_reduction_state(reduction) ++ raw[0:", integer_to_list(Start), "]\n}\n\n",
             "// Evaluate the same checked contribution and reducer as ordinary delivery.\n",
             "fn collection_try(machine: ActorState, frame: axis::Frame) -> (bool, ReductionState) {\n",
             "  let tag_ok = ", xls_actor_codegen:input_tag_ok(Spec, Names, Words), ";\n",
             "  let eligible = !hls_failure::failed(machine.failure) && !machine.enter_pending",
             xls_statem_event_codegen:optional(Spec, " && machine.next_event == u8:0"), ";\n",
             "  let contribution = reduction_contribution(frame, machine.phase, machine.data);\n",
             "  let applied = reduction_apply(machine.reduction, contribution);\n",
             "  let accepted = eligible && tag_ok &&\n",
             "    (applied.outcome == ReductionOutcome::PENDING || applied.outcome == ReductionOutcome::COMPLETE);\n",
             "  (accepted, if accepted { applied.state } else { machine.reduction })\n}\n\n",
             template("shared_collection.x")]
    end.

-doc "Registers retired ownership commands while applying only the prior collector command.".
-spec retire(map()) -> iodata().
retire(Spec) ->
    case enabled(Spec) of
        false -> [];
        true -> "        let retired = collection_retire(before_collection, retire_valid, result.slot, resolved.machine);\n"
    end.

-doc "Collects the admission choice under the selected ownership policy; exclusive mode also accepts early and owned-actor input.".
-spec admit(map()) -> iodata().
admit(#{admission_reductions := exclusive_epoch}) ->
    "\n        let collection = collection_admit(state, collection_intent);\n";
admit(Spec) -> optional(Spec,
    "
        let collection = collection_admit(state, intent, issue_valid, read_slot);\n").

-doc "A collected frame consumes its producer slot instead of a mailbox RAM cell.".
-spec admission_guard(map()) -> iodata().
admission_guard(#{admission_reductions := exclusive_epoch}) -> [];
admission_guard(Spec) -> optional(Spec, " && !collection.0").

-doc "Commits collection progress and producer fairness after unrelated retirement and ordinary admission.".
-spec commit(map()) -> iodata().
commit(#{admission_reductions := exclusive_epoch}) ->
    "\n        let admitted = collection_commit(reserved, collection_intent, collection);\n";
commit(Spec) -> case enabled(Spec) of
    false -> "
        let admitted = reserved;\n";
    true -> "
        let admitted = collection_commit(reserved, intent, collection);\n"
end.

%% The option is validated at the shared-artifact boundary.
-spec enabled(map()) -> boolean().
enabled(Spec) -> maps:get(admission_reductions, Spec, false) =/= false.

%% Keeps ordinary generated services unchanged apart from local binding names.
-spec optional(map(), iodata()) -> iodata().
optional(Spec, Text) -> case enabled(Spec) of true -> Text; false -> [] end.

%% Static proc-independent definitions remain readable DSLX source.
-spec template(file:filename()) -> binary().
template(Name) ->
    {ok, Text} = file:read_file(filename:join([code:priv_dir(hls_fabric), "xls", "templates", Name])),
    Text.

-doc "Applies a previously detected protocol fault before a retiring callback can publish effects.".
-spec resolve(map()) -> iodata().
resolve(#{admission_reductions := exclusive_epoch}) ->
    "        let resolved = collection_resolve(state, result.slot, resolved);\n";
resolve(_) -> [].

-doc "Selects ordinary mail and reserved contributions independently, with fairness within each class.".
-spec selection(map()) -> iodata().
selection(#{admission_reductions := exclusive_epoch}) ->
    "\n        let intent = collection_select_ordinary(state);\n        let collection_intent = collection_select(state);\n";
selection(_) ->
    "\n        let intent = mailbox::select_admission(\n          state.occupied, state.used, state.admission_cursor,\n          state.pending, state.pending_valid, false, u32:0, false, u32:0);\n".

-doc "Retains completion ownership until its callback retires and requests release.".
-spec issue(map()) -> iodata().
issue(#{admission_reductions := exclusive_epoch}) ->
    "        let admitted = collection_issue(state, admitted, issue_valid && internal_active, read_slot);\n";
issue(_) -> [].

-doc "Decodes newly captured requests at the existing input holding boundary.".
-spec capture(map()) -> iodata().
capture(#{admission_reductions := exclusive_epoch}) ->
    "        let captured_collection_inputs = collection_capture_inputs(state, captured_pending, captured_pending_valid);\n";
capture(_) -> [].

-doc "Commits held decoding with its raw request; other collection policies retain their original storage.".
-spec captured_field(map()) -> iodata().
captured_field(#{admission_reductions := exclusive_epoch}) ->
    "          collection_inputs: captured_collection_inputs,\n";
captured_field(_) -> [].

-doc "Names the ordinary retirement result before optional collection ownership handling.".
-spec retire_binding(map()) -> string().
retire_binding(Spec) -> case enabled(Spec) of
    true -> "before_collection";
    false -> "retired"
end.
