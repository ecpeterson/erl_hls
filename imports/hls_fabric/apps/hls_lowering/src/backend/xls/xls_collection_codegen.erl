-module(xls_collection_codegen).
-moduledoc "Renders physical reduction-collection fragments for scheduler admission and retirement. xls_scheduler_actor checks the policy before code generation; scheduler rendering consumes these fragments without changing callback semantics.".

%% Policy validation and compilation requirements.
-export([validate/2, requirements/3]).

%% Collector declarations and retained fields.
-export([
    helpers/1, state_fields/1, ticket_field/1, ticket_value/1, loader_value/1, captured_field/1
]).

%% Admission, selection and completion transitions.
-export([
    retire/1,
    retire_binding/1,
    admit/1,
    admission_guard/1,
    commit/1,
    resolve/1,
    selection/2,
    issue/1,
    capture/1
]).

-export_type([selection_bindings/0]).

-doc "Compiler-generated DSLX identifiers for the ordinary admission source, independent collector source and new ordinary intent. Sources must already be bound; these names are rendered directly, never parsed or rewritten.".
-type selection_bindings() :: #{
    ordinary_state := string(),
    collection_state := string(),
    ordinary_result := string()
}.

-doc "Requires an ordinary reduced actor; collection never replaces aggregate-only delivery.".
-spec validate(map(), map()) -> ok.
validate(Spec, Options) ->
    case maps:get(admission_reductions, Options, false) of
        false ->
            ok;
        Mode when Mode =:= true; Mode =:= exclusive_epoch ->
            case
                {
                    maps:get(shared_service, Options, ordinary),
                    maps:get(reductions, Spec, none),
                    xls_statem_reply_codegen:enabled(Spec)
                }
            of
                {ordinary, R, false} when is_map(R), Mode =:= true -> ok;
                {ordinary, R, false} when is_map(R) -> xls_exclusive_collection_codegen:validate(R);
                _ -> error(admission_reductions_require_ordinary_reduced_actor)
            end;
        Other ->
            error({admission_reductions, Other})
    end.

-doc "Requires one collector policy per shared module and excludes direct instances of selected modules.".
-spec requirements([map()], [map()], map()) -> map().
requirements(Groups, Direct, Requirements) ->
    lists:foldl(
        fun(Module, Initial) ->
            GatherFlags = lists:usort([
                maps:get(gather_collection, G, false)
             || G = #{module := M} <- Groups, M =:= Module
            ]),
            Acc =
                case GatherFlags of
                    [false] ->
                        Initial;
                    [true] ->
                        Initial#{Module := (maps:get(Module, Initial))#{gather_collection => true}};
                    _ ->
                        error({gather_collection_module_policy, Module})
                end,
            Flags = lists:usort([
                maps:get(admission_reductions, G, false)
             || G = #{module := M} <- Groups, M =:= Module
            ]),
            case Flags of
                [false] ->
                    Acc;
                [Mode] when Mode =:= true; Mode =:= exclusive_epoch ->
                    case lists:any(fun(#{module := M}) -> M =:= Module end, Direct) of
                        true ->
                            error({admission_reductions_direct_instance, Module});
                        false ->
                            Acc#{Module := (maps:get(Module, Acc))#{admission_reductions => Mode}}
                    end;
                _ ->
                    error({admission_reductions_module_policy, Module})
            end
        end,
        Requirements,
        lists:usort([M || #{module := M} <- Groups])
    ).

-doc "Adds the authoritative collector context; XLS removes callback fields unused by contribution selection.".
-spec state_fields(map()) -> iodata().
state_fields(#{admission_reductions := exclusive_epoch}) ->
    template("exclusive_collection_fields.x.in");
state_fields(Spec) ->
    optional(
        Spec,
        "  collection_context: ActorState[ACTOR_COUNT],\n  collection_initialized: bool[ACTOR_COUNT],\n"
    ).

-doc "Freezes the authoritative reduction with the actor's dispatch reservation.".
-spec ticket_field(map()) -> iodata().
ticket_field(#{admission_reductions := exclusive_epoch}) ->
    "  collection: ReductionState,\n  collection_failure: hls_failure::Code,\n";
ticket_field(Spec) ->
    optional(Spec, "  collection: ReductionState,\n").

-doc "Copies the committed collector state before transferring actor ownership.".
-spec ticket_value(map()) -> iodata().
ticket_value(#{admission_reductions := exclusive_epoch}) ->
    "              collection: if state.collection_owners.opened[read_slot] && state.collection_context[read_slot].reduction.status == ReductionStatus::COMPLETE { state.collection_context[read_slot].reduction } else { zero!<ReductionState>() },\n              collection_failure: state.collection_context[read_slot].failure,\n";
ticket_value(Spec) ->
    optional(
        Spec,
        "              collection: state.collection_context[read_slot].reduction,\n"
    ).

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
-spec helpers(map()) -> xls_dslx:value().
helpers(Spec = #{admission_reductions := exclusive_epoch}) ->
    xls_exclusive_collection_codegen:helpers(Spec);
helpers(Spec = #{message_names := Names, message_words := Words}) ->
    case enabled(Spec) of
        false ->
            [];
        true ->
            Layout = xls_machine_layout:from_spec(Spec),
            #{offset := Start, width := Width} = xls_machine_layout:field(Layout, reduction),
            End = Start + Width,
            HasTail = End < xls_machine_layout:width(Layout),
            [
                "// RAM retains the last executor result, not current collection progress.\n",
                "fn collection_machine_bits(raw: MachineBits, reduction: ReductionState) -> MachineBits {\n  ",
                case HasTail of
                    true -> ["raw[", integer_to_list(End), ":] ++ "];
                    false -> []
                end,
                "bits_from_reduction_state(reduction) ++ raw[0:",
                integer_to_list(Start),
                "]\n}\n\n",
                "// Evaluate the same checked contribution and reducer as ordinary delivery.\n",
                "fn collection_try(machine: ActorState, frame: axis::Frame) -> (bool, ReductionState) {\n",
                "  let tag_ok = ",
                xls_actor_codegen:input_tag_ok(Spec, Names, Words),
                ";\n",
                "  let eligible = !hls_failure::failed(machine.failure) && !machine.enter_pending",
                xls_statem_event_codegen:optional(Spec, " && machine.next_event == u8:0"),
                ";\n",
                "  let contribution = reduction_contribution(frame, machine.phase, machine.data);\n",
                "  let applied = reduction_apply(machine.reduction, contribution);\n",
                "  let accepted = eligible && tag_ok &&\n",
                "    (applied.outcome == ReductionOutcome::PENDING || applied.outcome == ReductionOutcome::COMPLETE);\n",
                "  (accepted, if accepted { applied.state } else { machine.reduction })\n}\n\n",
                template("shared_collection.x")
            ]
    end.

-doc "Registers retired ownership commands while applying only the prior collector command.".
-spec retire(map()) -> iodata().
retire(Spec) ->
    case enabled(Spec) of
        false ->
            [];
        true ->
            "        let retired = collection_retire(before_collection, retire_valid, result.slot, resolved.machine);\n"
    end.

-doc "Collects the admission choice under the selected ownership policy; exclusive mode also accepts early and owned-actor input.".
-spec admit(map()) -> iodata().
admit(#{admission_reductions := exclusive_epoch}) ->
    "\n        let collection = collection_admit(state, collection_intent);\n";
admit(Spec) ->
    optional(
        Spec,
        "\n"
        "        let collection = collection_admit(state, intent, issue_valid, read_slot);\n"
    ).

-doc "A collected frame consumes its producer slot instead of a mailbox RAM cell.".
-spec admission_guard(map()) -> iodata().
admission_guard(#{admission_reductions := exclusive_epoch}) -> [];
admission_guard(Spec) -> optional(Spec, " && !collection.0").

-doc "Commits collection progress and producer fairness after unrelated retirement and ordinary admission.".
-spec commit(map()) -> iodata().
commit(#{admission_reductions := exclusive_epoch}) ->
    "\n        let admitted = collection_commit(reserved, collection_intent, collection);\n";
commit(Spec) ->
    case enabled(Spec) of
        false ->
            "\n"
            "        let admitted = reserved;\n";
        true ->
            "\n"
            "        let admitted = collection_commit(reserved, intent, collection);\n"
    end.

%% The option is validated at the shared-artifact boundary.
-spec enabled(map()) -> boolean().
enabled(Spec) -> maps:get(admission_reductions, Spec, false) =/= false.

%% Keeps ordinary generated services unchanged apart from local binding names.
-spec optional(map(), iodata()) -> iodata().
optional(Spec, Text) ->
    case enabled(Spec) of
        true -> Text;
        false -> []
    end.

%% Static proc-independent definitions remain readable DSLX source.
-spec template(file:filename()) -> binary().
template(Name) ->
    {ok, Text} = file:read_file(
        filename:join([code:priv_dir(hls_lowering), "xls", "templates", Name])
    ),
    Text.

-doc "Applies a previously detected protocol fault before a retiring callback can publish effects.".
-spec resolve(map()) -> iodata().
resolve(#{admission_reductions := exclusive_epoch}) ->
    "        let resolved = collection_resolve(state, result.slot, resolved);\n";
resolve(_) ->
    [].

-doc "Renders independent ordinary-mail and reserved-contribution selection from the supplied state identifiers. Indexed collection filters only the ordinary source. Exclusive epoch mode also binds collection_intent from the separate collector source; other modes do not emit collector selection. The caller owns reservation masking and retention of the resulting ordinary intent.".
-spec selection(map(), selection_bindings()) -> iodata().
selection(Spec, #{
    ordinary_state := Ordinary,
    collection_state := Collection,
    ordinary_result := Result
}) ->
    [ordinary_selection(Spec, Ordinary, Result), collection_selection(Spec, Collection)].

%% Indexed filtering and exclusive ownership choose the operation, not generated-text edits.
-spec ordinary_selection(map(), string(), string()) -> iodata().
ordinary_selection(
    #{gather_collection := true, admission_reductions := exclusive_epoch}, State, Result
) ->
    exclusive_selection(["indexed_ordinary_state(", State, ")"], Result);
ordinary_selection(#{admission_reductions := exclusive_epoch}, State, Result) ->
    exclusive_selection(State, Result);
ordinary_selection(#{gather_collection := true}, State, Result) ->
    [
        "\n        let ordinary_state = indexed_ordinary_state(",
        State,
        ");\n",
        mailbox_selection("ordinary_state", Result)
    ];
ordinary_selection(_, State, Result) ->
    mailbox_selection(State, Result).

%% Exclusive ownership protects mailbox admission while keeping collector fairness separate.
-spec exclusive_selection(iodata(), string()) -> iodata().
exclusive_selection(State, Result) ->
    ["\n        let ", Result, " = collection_select_ordinary(", State, ");\n"].

%% Ordinary and opportunistic collection share the same free-cell admission selector.
-spec mailbox_selection(string(), string()) -> iodata().
mailbox_selection(State, Result) ->
    [
        "\n        let ",
        Result,
        " = mailbox::select_admission(\n          ",
        State,
        ".occupied, ",
        State,
        ".used, ",
        State,
        ".admission_cursor,\n          ",
        State,
        ".pending, ",
        State,
        ".pending_valid, false, u32:0, false, u32:0);\n"
    ].

%% Collector selection observes its original ownership source, never the ordinary mask.
-spec collection_selection(map(), string()) -> iodata().
collection_selection(#{admission_reductions := exclusive_epoch}, State) ->
    ["        let collection_intent = collection_select(", State, ");\n"];
collection_selection(_, _) ->
    [].

-doc "Retains completion ownership until its callback retires and requests release.".
-spec issue(map()) -> iodata().
issue(#{admission_reductions := exclusive_epoch}) ->
    "        let admitted = collection_issue(state, admitted, issue_valid && internal_active, read_slot);\n";
issue(_) ->
    [].

-doc "Decodes newly captured requests at the existing input holding boundary.".
-spec capture(map()) -> iodata().
capture(#{admission_reductions := exclusive_epoch}) ->
    "        let captured_collection_inputs = collection_capture_inputs(state, captured_pending, captured_pending_valid);\n";
capture(_) ->
    [].

-doc "Commits held decoding with its raw request; other collection policies retain their original storage.".
-spec captured_field(map()) -> iodata().
captured_field(#{admission_reductions := exclusive_epoch}) ->
    "          collection_inputs: captured_collection_inputs,\n";
captured_field(_) ->
    [].

-doc "Names the ordinary retirement result before optional collection ownership handling.".
-spec retire_binding(map()) -> string().
retire_binding(Spec) ->
    case enabled(Spec) of
        true -> "before_collection";
        false -> "retired"
    end.
