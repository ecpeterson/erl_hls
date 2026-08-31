-module(xls_parse_tests).

-include_lib("eunit/include/eunit.hrl").

passive_state_observation_is_not_emitted_test() ->
    Xls = iolist_to_binary(xls_parse:to_xls("src/examples/regsvc/regsvc.erl")),

    %% State serialization remains part of the generated API, but the live
    %% Service recurrence carries only the tagged struct and never packs it.
    ?assertMatch({_, _}, binary:match(Xls, <<"fn bits_from_state(s: State)">>)),
    ?assertEqual(1, length(binary:matches(Xls, <<"bits_from_state">>))),
    ?assertMatch({_, _}, binary:match(Xls, <<"let state_record = (Tag::STATE, state);">>)),
    ?assertMatch({_, _}, binary:match(Xls, <<"new_state.1">>)),

    ?assertEqual(nomatch, binary:match(Xls, <<"state_out">>)),
    ?assertEqual(nomatch, binary:match(Xls, <<"ext_state">>)).

ordered_gs_clauses_share_one_tag_arm_test() ->
    Xls = iolist_to_binary(xls_parse:to_xls("src/examples/regsvc/regsvc.erl")),

    %% Multiple cast and call clauses each share one wire-tag dispatch arm.
    ?assertEqual(1, length(binary:matches(Xls, <<"Tag::SET =>">>))),
    ?assertEqual(1, length(binary:matches(Xls, <<"Tag::BULK_GET =>">>))).

repeated_hls_tags_follow_include_expanded_source_order_test() ->
    Path = "test_data/hls_tags_fixture.erl",
    Xls = iolist_to_binary(xls_parse:to_xls(Path)),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"FIRST = u8:3">>)),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"SHARED = u8:4">>)),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"LAST = u8:5">>)),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"Tag::FIRST =>">>)),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"Tag::SHARED =>">>)),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"Tag::LAST =>">>)),

    {ok, Module, Binary} = compile:file(Path, [binary]),
    {module, Module} = code:load_binary(Module, Path, Binary),
    try
        ?assertEqual(3, Module:pack_tag(first)),
        ?assertEqual(4, Module:pack_tag(shared)),
        ?assertEqual(5, Module:pack_tag(last)),
        ?assertEqual(first, Module:unpack_tag(3)),
        ?assertEqual(shared, Module:unpack_tag(4)),
        ?assertEqual(last, Module:unpack_tag(5))
    after
        true = code:delete(Module),
        _ = code:purge(Module)
    end.

repeated_hls_tags_reach_state_machine_lowering_test() ->
    Xls = iolist_to_binary(xls_parse:to_xls(
        "test_data/hls_tags_statem_fixture.erl"
    )),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"FIRST = u8:3">>)),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"SHARED = u8:4">>)),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"LAST = u8:5">>)),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"Tag::FIRST">>)),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"Tag::SHARED">>)),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"Tag::LAST">>)).

duplicate_hls_tags_are_rejected_across_blocks_test() ->
    Forms = [
        {attribute, 1, hls_tags, [first, shared]},
        {attribute, 2, hls_tags, [shared, last]}
    ],
    ?assertError({duplicate_hls_tags, [shared]}, xls_parse:find_tags(Forms)),
    ?assertError(
        {duplicate_hls_tags, [first]},
        xls_parse:find_tags([
            {attribute, 3, hls_tags, [first, first]}
        ])
    ).

malformed_hls_tag_fragments_are_rejected_test() ->
    ?assertError(
        {invalid_hls_tags, 7, [first, 2]},
        xls_parse:find_tags([{attribute, 7, hls_tags, [first, 2]}])
    ),
    ?assertError(
        {invalid_hls_tags, 9, first},
        xls_parse:find_tags([{attribute, 9, hls_tags, first}])
    ).

hls_tags_fill_but_do_not_overflow_the_u8_namespace_test() ->
    Tags = [
        list_to_atom("hls_capacity_tag_" ++ integer_to_list(Index))
        || Index <- lists:seq(1, 254)
    ],
    ?assertEqual(
        lists:sublist(Tags, 253),
        xls_parse:find_tags([
            {attribute, 1, hls_tags, lists:sublist(Tags, 253)}
        ])
    ),
    ?assertError(
        {too_many_hls_tags, 254, 253},
        xls_parse:find_tags([{attribute, 2, hls_tags, Tags}])
    ).

guard_alternatives_are_rejected_test() ->
    [Clause] = parse_clauses(
        "probe(#message{value = Value}, State) "
        "when Value =:= 0; Value =:= 1 -> State."
    ),
    ?assertException(
        error,
        {unsupported_xls_guard_sequences, _, _},
        xls_callback_lower:lower(
            [Clause],
            callback_arguments(),
            state,
            fun(R) -> R end,
            "no_clause",
            "body_failure",
            #{}
        )
    ).

non_boolean_guard_root_is_rejected_test() ->
    [Clause] = parse_clauses(
        "probe(#message{value = Value}, State) "
        "when Value band 1 -> State."
    ),
    ?assertError(
        {unsupported_xls_guard, 1, {non_boolean_predicate, 'band'}},
        xls_callback_lower:lower(
            [Clause],
            callback_arguments(),
            state,
            fun(R) -> R end,
            "no_clause",
            "body_failure",
            #{}
        )
    ).

guard_record_access_uses_the_bound_record_test() ->
    XLS = lower_callback_clauses(
        "probe(#message{}, State) "
        "when State#state.value =:= 0 -> State."
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"Xls_clause_1_State_1.1.value">>)
    ).

guard_orelse_keeps_rhs_in_false_branch_test() ->
    XLS = lower_callback_clauses(
        "probe(#message{value = Value}, State) "
        "when Value =:= 0 orelse Value =:= 1 -> State."
    ),
    ?assertEqual(nomatch, binary:match(XLS, <<" || ">>)),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<
            "if _0 {\n"
            "  (bool:1, bool:false)\n"
            "} else {\n"
            "  let _1 = Xls_clause_1_Value_1 == 1;"
        >>)
    ).

comma_guards_keep_rhs_in_true_branch_test() ->
    XLS = lower_callback_clauses(
        "probe(#message{value = Value}, State) "
        "when Value >= 0, Value < 2 -> State."
    ),
    ?assertEqual(nomatch, binary:match(XLS, <<" && ">>)),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<
            "if _0 {\n"
            "  let _1 = Xls_clause_1_Value_1 < 2;"
        >>)
    ).

clause_guard_runs_only_after_the_head_matches_test() ->
    XLS = lower_callback_clauses(
        "probe(#message{value = 0}, State) "
        "when State#state.value =:= 1 -> State."
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<
            "if message.value == 0 {\n"
            "  let _0 = Xls_clause_1_State_1.1.value;\n"
            "  let _1 = _0 == 1;"
        >>)
    ).

tuple_head_patterns_are_projected_for_xls_typechecking_test() ->
    XLS = lower_callback_clauses(
        "probe(#message{value = {Left, Right}}, State) -> "
        "{Left, Right, State}."
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"message.value.0">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"message.value.1">>)).

case_distinct_callback_variables_remain_distinct_test() ->
    XLS = lower_callback_clauses(
        "probe(#message{value = Foo}, #state{value = FOO}) -> "
        "{Foo, FOO}."
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Foo_1">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"FOO_1">>)).

selected_body_badmatch_does_not_try_later_clause_test() ->
    XLS = lower_callback_clauses(
        "probe(#message{value = 0}, State) -> "
        "true = false, State; "
        "probe(#message{}, State) -> State."
    ),
    ?assertEqual(
        <<
            "let Xls_clause_1_State_1 = (Tag::STATE, data);\n"
            "if message.value == 0 {\n"
            "  let static_match_1_1 = bool:1 ;\n"
            "  let static_match_1_2 = bool:0 ;\n"
            "  if ((static_match_1_1 != static_match_1_2) || "
                "bool:false) {\n"
            "    body_failure\n"
            "  } else {\n"
            "    Xls_clause_1_State_1\n"
            "  }\n"
            "} else {\n"
            "  let Xls_clause_2_State_1 = (Tag::STATE, data);\n"
            "  if bool:true {\n"
            "    if (bool:false) {\n"
            "      body_failure\n"
            "    } else {\n"
            "      Xls_clause_2_State_1\n"
            "    }\n"
            "  } else {\n"
            "    no_clause\n"
            "  }\n"
            "}"
        >>,
        XLS
    ).

same_gs_tag_cannot_be_both_call_and_cast_test() ->
    Path = filename:join("_build", "ambiguous_gs_tag_fixture.erl"),
    ok = filelib:ensure_dir(Path),
    Source = <<
        "-module(ambiguous_gs_tag_fixture).\n"
        "-hls_data(state).\n"
        "-hls_tags([message]).\n"
        "-record(message, {\n"
        "  value = hls_type:zero() :: hls_nums:u32()\n"
        "}).\n"
        "-record(state, {\n"
        "  value = hls_type:zero() :: hls_nums:u32()\n"
        "}).\n"
        "init([]) -> #state{}.\n"
        "handle_call(#message{}, State) ->\n"
        "  {reply, #message{}, State}.\n"
        "handle_cast(#message{}, State) ->\n"
        "  {noreply, State}.\n"
    >>,
    ok = file:write_file(Path, Source),
    try
        ?assertError(
            {ambiguous_hls_gs_callback_tags, [message]},
            xls_parse:to_xls(Path)
        )
    after
        ok = file:delete(Path)
    end.

boolean_case_preserves_branch_badmatches_test() ->
    Clause = parse_clause(
        "probe(Condition, Value) -> "
        "case Condition of true -> true = Value, 1; false -> 2 end."
    ),
    {Body, Result} = xls_parse:branch_from_clause(
        Clause,
        ["condition", "value"],
        state,
        fun(R) -> R end,
        "failure",
        #{}
    ),
    XLS = iolist_to_binary(xls_parse:print([Body, Result])),
    ?assertNotEqual(
        nomatch,
        binary:match(
            XLS,
            <<"static_match_1_1 != static_match_1_2">>
        )
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"case_match_">>)).

hls_type_as_preserves_the_host_value_and_emits_a_dslx_cast_test() ->
    ?assertEqual(0, hls_type:as(hls_nums:u32(), 0)),
    Clause = parse_clause(
        "probe() -> hls_type:as(hls_nums:u32(), 0)."
    ),
    {Body, Result} = xls_parse:branch_from_clause(
        Clause,
        [],
        state,
        fun(R) -> R end,
        "failure",
        #{}
    ),
    XLS = iolist_to_binary(xls_parse:print([Body, Result])),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"(0 as u32)">>)).

boolean_case_bindings_are_local_to_each_arm_test() ->
    Clause = parse_clause(
        "probe(Condition) -> "
        "case Condition of true -> X = 1, X; false -> X = 2, X end."
    ),
    {Body, Result} = xls_parse:branch_from_clause(
        Clause,
        ["condition"],
        state,
        fun(R) -> R end,
        "failure",
        #{}
    ),
    XLS = iolist_to_binary(xls_parse:print([Body, Result])),
    ?assertEqual(nomatch, binary:match(XLS, <<"X_2">>)).

ordered_integer_case_uses_guards_then_falls_through_test() ->
    XLS = lower_expression_clause(
        "probe(Value) -> case Value of "
        "0 -> 10; "
        "Selected when Selected < 3 -> 20; "
        "_ -> 30 end.",
        ["value"]
    ),
    {Literal, _} = binary:match(XLS, <<"== 0">>),
    {Guard, _} = binary:match(XLS, <<"Selected_1 < 3">>),
    ?assert(Literal < Guard),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"else {">>)).

general_case_evaluates_its_scrutinee_once_test() ->
    XLS = lower_expression_clause(
        "probe(Value) -> case Value + 1 of "
        "0 -> 10; "
        "_ -> 20 end.",
        ["value"]
    ),
    ?assertEqual(1, length(binary:matches(XLS, <<"Value_1 + 1">>))).

tuple_case_projects_and_compares_repeated_variables_test() ->
    XLS = lower_expression_clause(
        "probe(Pair) -> case Pair of "
        "{Same, Same} -> Same; "
        "{_, Right} -> Right; "
        "_ -> 0 end.",
        ["pair"]
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<".0">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<".1">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Same_1 ==">>)).

case_pattern_compares_an_outer_binding_instead_of_rebinding_test() ->
    XLS = lower_expression_clause(
        "probe(Value, Outer) -> case Value of "
        "Outer -> 1; "
        "_ -> 2 end.",
        ["value", "outer"]
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Outer_1 ==">>)),
    ?assertEqual(nomatch, binary:match(XLS, <<"let Outer_2">>)).

case_alias_binds_the_whole_value_and_its_fields_test() ->
    XLS = lower_expression_clause(
        "probe(Pair) -> case Pair of "
        "Whole = {Left, _} when Left > 0 -> Whole; "
        "_ -> {0, 0} end.",
        ["pair"]
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"let Whole_1">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"let Left_1">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Left_1 > 0">>)).

selected_general_case_body_badmatch_does_not_fall_through_test() ->
    XLS = lower_expression_clause(
        "probe(Value) -> case Value of "
        "0 -> true = false, 1; "
        "_ -> 2 end.",
        ["value"]
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"static_match_">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"case_match_">>)),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<
            "(1, (static_match_1_1 != static_match_1_2) || bool:false)\n"
            "  } else {\n"
            "    (2, bool:false)"
        >>)
    ).

general_case_bindings_are_local_to_each_arm_test() ->
    XLS = lower_expression_clause(
        "probe(Value) -> case Value of "
        "0 -> Choice = 1, Choice; "
        "_ -> Choice = 2, Choice end.",
        ["value"]
    ),
    ?assertEqual(2, length(binary:matches(XLS, <<"let Choice_1">>))),
    ?assertEqual(nomatch, binary:match(XLS, <<"Choice_2">>)).

case_alias_catchall_is_exhaustive_test() ->
    XLS = lower_expression_clause(
        "probe(Value) -> case Value of "
        "0 -> 1; "
        "Whole = _ -> Whole end.",
        ["value"]
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"let Whole_1">>)).

homogeneous_record_case_supports_aliases_fields_and_guards_test() ->
    XLS = lower_callback_clauses(
        "probe(Message = #message{}, State) -> "
        "Result = case Message of "
        "Whole = #message{value = 0} -> Whole; "
        "#message{value = Value} when Value < 4 -> Message; "
        "_ -> Message end, "
        "{Result, State}."
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Tag::MESSAGE">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<".1.value == 0">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Value_1 < 4">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Whole_1">>)).

general_case_without_fallback_is_rejected_test() ->
    Clause = parse_clause(
        "probe(Value) -> case Value of 0 -> 1; 1 -> 2 end."
    ),
    ?assertException(
        error,
        {missing_xls_case_fallback, _},
        xls_parse:branch_from_clause(
            Clause,
            ["value"],
            state,
            fun(R) -> R end,
            "failure",
            #{}
        )
    ).

guarded_general_case_fallback_is_rejected_test() ->
    Clause = parse_clause(
        "probe(Value) -> case Value of 0 -> 1; "
        "Fallback when Fallback >= 0 -> 2 end."
    ),
    ?assertException(
        error,
        {guarded_xls_case_fallback, _},
        xls_parse:branch_from_clause(
            Clause,
            ["value"],
            state,
            fun(R) -> R end,
            "failure",
            #{}
        )
    ).

nonfinal_general_case_fallback_is_rejected_test() ->
    Clause = parse_clause(
        "probe(Value) -> case Value of _ -> 0; 1 -> 1; _ -> 2 end."
    ),
    ?assertException(
        error,
        {nonfinal_xls_case_fallback, _},
        xls_parse:branch_from_clause(
            Clause,
            ["value"],
            state,
            fun(R) -> R end,
            "failure",
            #{}
        )
    ).

nonfinal_alias_case_fallback_is_rejected_test() ->
    Clause = parse_clause(
        "probe(Value) -> case Value of Whole = _ -> Whole; _ -> 2 end."
    ),
    ?assertException(
        error,
        {nonfinal_xls_case_fallback, _},
        xls_parse:branch_from_clause(
            Clause,
            ["value"],
            state,
            fun(R) -> R end,
            "failure",
            #{}
        )
    ).

general_case_rejects_incompatible_pattern_shapes_test() ->
    Clause = parse_clause(
        "probe(Value) -> case Value of {0, _} -> 1; 0 -> 2; _ -> 3 end."
    ),
    ?assertException(
        error,
        {incompatible_xls_case_pattern_shapes, _, _},
        xls_parse:branch_from_clause(
            Clause,
            ["value"],
            state,
            fun(R) -> R end,
            "failure",
            #{}
        )
    ).

general_case_rejects_heterogeneous_record_patterns_test() ->
    Clause = parse_clause(
        "probe(Value) -> case Value of #left{} -> 1; #right{} -> 2; _ -> 3 end."
    ),
    ?assertException(
        error,
        {incompatible_xls_case_pattern_shapes, _, _},
        xls_parse:branch_from_clause(
            Clause,
            ["value"],
            state,
            fun(R) -> R end,
            "failure",
            #{}
        )
    ).

duplicate_boolean_case_arm_is_rejected_test() ->
    Clause = parse_clause(
        "probe(Condition) -> "
        "case Condition of true -> 1; true -> 2; false -> 3 end."
    ),
    ?assertException(
        error,
        {duplicate_xls_boolean_case_branch, _, true},
        xls_parse:branch_from_clause(
            Clause,
            ["condition"],
            state,
            fun(R) -> R end,
            "failure",
            #{}
        )
    ).

case_preservation_keeps_bookkeeping_names_distinct_test() ->
    Clause = parse_clause(
        "probe(Condition, Case_match_1) -> "
        "case Condition of true -> 1; false -> 2 end."
    ),
    {Body, Result} = xls_parse:branch_from_clause(
        Clause,
        ["condition", "case_match_1"],
        state,
        fun(R) -> R end,
        "failure",
        #{}
    ),
    XLS = iolist_to_binary(xls_parse:print([Body, Result])),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Case_match_1_1">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"case_match_1_1">>)).

if_clauses_preserve_source_order_and_comma_guards_test() ->
    XLS = lower_expression_clause(
        "probe(Value) -> if "
        "Value >= 10 -> Value + 1; "
        "Value >= 0, Value < 20 -> Value + 2; "
        "true -> Value + 3 end.",
        ["value"]
    ),
    {First, _} = binary:match(XLS, <<"Value_1 >= 10">>),
    {Second, _} = binary:match(XLS, <<"Value_1 >= 0">>),
    {Third, _} = binary:match(XLS, <<"Value_1 < 20">>),
    ?assert(First < Second),
    ?assert(Second < Third),
    ?assertEqual(nomatch, binary:match(XLS, <<" && ">>)).

if_branch_bindings_are_local_test() ->
    XLS = lower_expression_clause(
        "probe(Value) -> if "
        "Value > 0 -> Choice = Value + 1, Choice; "
        "true -> Choice = Value - 1, Choice end.",
        ["value"]
    ),
    ?assertEqual(2, length(binary:matches(XLS, <<"let Choice_1">>))),
    ?assertEqual(nomatch, binary:match(XLS, <<"Choice_2">>)).

selected_if_body_badmatch_reaches_body_failure_test() ->
    XLS = lower_callback_clauses(
        "probe(#message{value = Value}, State) -> "
        "Result = if "
        "Value =:= 0 -> true = false, Value; "
        "true -> Value + 1 end, "
        "{Result, State}."
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"static_match_">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"case_match_">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"body_failure">>)).

if_without_true_fallback_is_rejected_test() ->
    Clause = parse_clause(
        "probe(Value) -> if Value =:= 0 -> Value end."
    ),
    ?assertException(
        error,
        {missing_xls_if_fallback, _},
        xls_parse:branch_from_clause(
            Clause,
            ["value"],
            state,
            fun(R) -> R end,
            "failure",
            #{}
        )
    ).

if_guard_alternatives_are_rejected_test() ->
    Clause = parse_clause(
        "probe(Value) -> if "
        "Value =:= 0; Value =:= 1 -> Value; true -> 2 end."
    ),
    ?assertException(
        error,
        {unsupported_xls_guard_sequences, _, _},
        xls_parse:branch_from_clause(
            Clause,
            ["value"],
            state,
            fun(R) -> R end,
            "failure",
            #{}
        )
    ).

hls_gs_callback_body_accepts_if_test() ->
    Path = filename:join("_build", "gs_if_fixture.erl"),
    ok = filelib:ensure_dir(Path),
    Source = <<
        "-module(gs_if_fixture).\n"
        "-hls_data(state).\n"
        "-hls_tags([message, query]).\n"
        "-record(message, {\n"
        "  value = hls_type:zero() :: hls_nums:u32()\n"
        "}).\n"
        "-record(query, {\n"
        "  value = hls_type:zero() :: hls_nums:u32()\n"
        "}).\n"
        "-record(state, {\n"
        "  value = hls_type:zero() :: hls_nums:u32()\n"
        "}).\n"
        "init([]) -> #state{}.\n"
        "handle_cast(#message{value = Value}, State) ->\n"
        "  Next = if Value > 0 -> Value; true -> State#state.value end,\n"
        "  {noreply, State#state{value = Next}}.\n"
        "handle_call(#query{value = Value}, State) ->\n"
        "  Reply = if\n"
        "    Value > 0 -> #message{value = Value};\n"
        "    true -> #message{value = State#state.value}\n"
        "  end,\n"
        "  {reply, Reply, State}.\n"
    >>,
    ok = file:write_file(Path, Source),
    try
        XLS = iolist_to_binary(xls_parse:to_xls(Path)),
        ?assertNotEqual(nomatch, binary:match(XLS, <<"Tag::MESSAGE =>">>)),
        ?assertNotEqual(nomatch, binary:match(XLS, <<"Tag::QUERY =>">>)),
        ?assertNotEqual(nomatch, binary:match(XLS, <<"Value_1 > 0">>))
    after
        ok = file:delete(Path)
    end.

hls_gs_callback_bodies_accept_general_case_test() ->
    XLS = iolist_to_binary(xls_parse:to_xls(
        "test_data/xls_case_fixture.erl"
    )),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Tag::QUERY =>">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Tag::UPDATE =>">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Choice_1 < 8">>)),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"Request_1.0 == Tag::QUERY">>)
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Original_1 < 8">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"case_match_">>)).

state_machine_init_argument_is_rejected_test() ->
    assert_bad_init_head(
        "statem_init_argument_fixture",
        "init(Arg) -> {ok, waiting, #cell{value = Arg}}.\n"
    ).

state_machine_init_guard_is_rejected_test() ->
    assert_bad_init_head(
        "statem_init_guard_fixture",
        "init([]) when false -> {ok, waiting, #cell{}}.\n"
    ).

state_machine_entry_action_accepts_record_update_test() ->
    EnterSource =
        "handle_enter(_OldPhase, waiting, Cell) ->\n"
        "  Message = #message{},\n"
        "  {Cell, [{cast, out, Message#message{"
        "value = Cell#cell.value}}]}.\n",
    CastSource =
        "handle_cast(#message{}, waiting, Cell) ->\n"
        "  {waiting, Cell, consume}.\n",
    with_statem_fixture(
        "statem_entry_record_update_fixture",
        "[waiting]",
        EnterSource,
        CastSource,
        fun(XLS) ->
            ?assertNotEqual(
                nomatch,
                binary:match(XLS, <<"..(Message_1).1">>)
            )
        end
    ).

repeat_phase_lowering_creates_an_explicit_boundary_test() ->
    CastSource =
        "handle_cast(#message{value = 0}, waiting, Cell) ->\n"
        "  {waiting, Cell, consume};\n"
        "handle_cast(#message{}, waiting, Cell) ->\n"
        "  {repeat_phase, Cell, consume}.\n",
    with_statem_fixture(
        "repeat_phase_lowering_fixture",
        "[waiting]",
        CastSource,
        fun(XLS) ->
            ?assertNotEqual(
                nomatch,
                binary:match(
                    XLS,
                    <<"Directive::CONSUME, bool:0">>
                )
            ),
            ?assertNotEqual(
                nomatch,
                binary:match(
                    XLS,
                    <<"Directive::CONSUME, bool:1">>
                )
            ),
            ?assertNotEqual(
                nomatch,
                binary:match(XLS, <<"let invalid_repeat =">>)
            ),
            ?assertNotEqual(
                nomatch,
                binary:match(XLS, <<"let phase_boundary =">>)
            ),
            ?assertNotEqual(
                nomatch,
                binary:match(
                    XLS,
                    <<"enter_pending: effective && phase_boundary">>
                )
            ),
            ?assertEqual(nomatch, binary:match(XLS, <<"blocked_phase">>)),
            ?assertNotEqual(
                nomatch,
                binary:match(
                    XLS,
                    <<"!admitted_slots[0].postponed;">>
                )
            )
        end
    ).

state_machine_final_if_normalizes_repeat_phase_test() ->
    CastSource =
        "handle_cast(#message{value = Value}, waiting, Cell) ->\n"
        "  if\n"
        "    Value =:= 0 -> {repeat_phase, Cell, consume};\n"
        "    true -> {waiting, Cell, consume}\n"
        "  end.\n",
    with_statem_fixture(
        "statem_final_if_fixture",
        "[waiting]",
        CastSource,
        fun(XLS) ->
            ?assertNotEqual(
                nomatch,
                binary:match(XLS, <<"Directive::CONSUME, bool:1">>)
            ),
            ?assertNotEqual(
                nomatch,
                binary:match(XLS, <<"Directive::CONSUME, bool:0">>)
            )
        end
    ).

state_machine_final_general_case_normalizes_each_conclusion_test() ->
    CastSource =
        "handle_cast(#message{value = Value}, waiting, Cell) ->\n"
        "  case Value of\n"
        "    0 -> {repeat_phase, Cell, consume};\n"
        "    1 -> {waiting, Cell, consume};\n"
        "    _ -> {waiting, Cell, fail}\n"
        "  end.\n",
    with_statem_fixture(
        "statem_final_case_fixture",
        "[waiting]",
        CastSource,
        fun(XLS) ->
            ?assertNotEqual(
                nomatch,
                binary:match(XLS, <<"Directive::CONSUME, bool:1">>)
            ),
            ?assertNotEqual(
                nomatch,
                binary:match(XLS, <<"Directive::CONSUME, bool:0">>)
            ),
            ?assertNotEqual(
                nomatch,
                binary:match(XLS, <<"Directive::FAIL, bool:0">>)
            )
        end
    ).

state_machine_indirect_if_result_is_rejected_test() ->
    CastSource =
        "handle_cast(#message{value = Value}, waiting, Cell) ->\n"
        "  Result = if\n"
        "    Value =:= 0 -> {repeat_phase, Cell, consume};\n"
        "    true -> {waiting, Cell, consume}\n"
        "  end,\n"
        "  Result.\n",
    ?assertException(
        error,
        {unsupported_hls_statem_cast_result, {var, _, 'Result'}},
        with_statem_fixture(
            "statem_indirect_if_fixture",
            "[waiting]",
            CastSource,
            fun(_XLS) -> ok end
        )
    ).

repeat_phase_rejects_nonconsume_directives_test_() ->
    [
        ?_test(repeat_phase_rejects_directive(Directive))
        || Directive <- [postpone, fail]
    ].

repeat_phase_is_not_a_declarable_phase_test() ->
    CastSource =
        "handle_cast(#message{}, waiting, Cell) ->\n"
        "  {waiting, Cell, consume}.\n",
    ?assertError(
        {reserved_hls_statem_phase, repeat_phase},
        with_statem_fixture(
            "reserved_repeat_phase_fixture",
            "[repeat_phase]",
            CastSource,
            fun(_XLS) -> ok end
        )
    ).

non_word_aligned_state_machine_message_is_rejected_test() ->
    Path = filename:join("_build", "non_word_statem_fixture.erl"),
    ok = filelib:ensure_dir(Path),
    Source = <<
        "-module(non_word_statem_fixture).\n"
        "-hls_data(cell).\n"
        "-hls_phases([waiting]).\n"
        "-hls_outputs([out]).\n"
        "-hls_mailbox_capacity(1).\n"
        "-hls_tags([message]).\n"
        "-record(message, {\n"
        "  value = hls_type:zero() :: hls_nums:u8()\n"
        "}).\n"
        "-record(cell, {\n"
        "  value = hls_type:zero() :: hls_nums:u32()\n"
        "}).\n"
    >>,
    ok = file:write_file(Path, Source),
    try
        ?assertError(
            {xls_message_not_word_aligned, message, 8, 32},
            xls_parse:to_xls(Path)
        )
    after
        ok = file:delete(Path)
    end.

with_statem_fixture(ModuleName, Phases, CastSource, Test) ->
    EnterSource =
        "handle_enter(_OldPhase, waiting, Cell) ->\n"
        "  Message = #message{value = Cell#cell.value},\n"
        "  {Cell, [{cast, out, Message}]}.\n",
    with_statem_fixture(
        ModuleName,
        Phases,
        EnterSource,
        CastSource,
        Test
    ).

with_statem_fixture(ModuleName, Phases, EnterSource, CastSource, Test) ->
    Path = filename:join("_build", ModuleName ++ ".erl"),
    ok = filelib:ensure_dir(Path),
    Source = iolist_to_binary([
        "-module(", ModuleName, ").\n",
        "-hls_data(cell).\n",
        "-hls_phases(", Phases, ").\n",
        "-hls_outputs([out]).\n",
        "-hls_mailbox_capacity(2).\n",
        "-hls_tags([message]).\n",
        "-record(message, {\n",
        "  value = hls_type:zero() :: hls_nums:u32()\n",
        "}).\n",
        "-record(cell, {\n",
        "  value = hls_type:zero() :: hls_nums:u32()\n",
        "}).\n",
        "init([]) -> {ok, waiting, #cell{}}.\n",
        EnterSource,
        CastSource
    ]),
    ok = file:write_file(Path, Source),
    try
        Test(iolist_to_binary(xls_parse:to_xls(Path)))
    after
        ok = file:delete(Path)
    end.

repeat_phase_rejects_directive(Directive) ->
    CastSource = io_lib:format(
        "handle_cast(#message{}, waiting, Cell) ->~n"
        "  {repeat_phase, Cell, ~p}.~n",
        [Directive]
    ),
    ?assertException(
        error,
        {bad_hls_statem_repeat_result, _, _},
        with_statem_fixture(
            "repeat_phase_directive_fixture",
            "[waiting]",
            CastSource,
            fun(_XLS) -> ok end
        )
    ).

assert_bad_init_head(ModuleName, InitSource) ->
    Path = filename:join("_build", ModuleName ++ ".erl"),
    ok = filelib:ensure_dir(Path),
    Source = iolist_to_binary([
        "-module(", ModuleName, ").\n",
        "-hls_data(cell).\n",
        "-hls_phases([waiting]).\n",
        "-hls_outputs([out]).\n",
        "-hls_mailbox_capacity(1).\n",
        "-hls_tags([message]).\n",
        "-record(message, {\n",
        "  value = hls_type:zero() :: hls_nums:u32()\n",
        "}).\n",
        "-record(cell, {\n",
        "  value = hls_type:zero() :: hls_nums:u32()\n",
        "}).\n",
        InitSource
    ]),
    ok = file:write_file(Path, Source),
    try
        ?assertException(
            error,
            {unsupported_hls_statem_init_head, _, _, _},
            xls_parse:to_xls(Path)
        )
    after
        ok = file:delete(Path)
    end.

parse_clause(Source) ->
    [Clause] = parse_clauses(Source),
    Clause.

parse_clauses(Source) ->
    {ok, Tokens, _EndLine} = erl_scan:string(Source),
    {ok, {function, _Line, probe, _Arity, Clauses}} =
        erl_parse:parse_form(Tokens),
    Clauses.

callback_arguments() ->
    [
        xls_pattern_lower:record_argument(
            message,
            "message",
            "(Tag::MESSAGE, message, bits)"
        ),
        xls_pattern_lower:record_argument(
            state,
            "data",
            "(Tag::STATE, data)"
        )
    ].

lower_callback_clauses(Source) ->
    {Body, Result} = xls_callback_lower:lower(
        parse_clauses(Source),
        callback_arguments(),
        state,
        fun(R) -> R end,
        "no_clause",
        "body_failure",
        #{}
    ),
    iolist_to_binary(xls_parse:print([Body, Result])).

lower_expression_clause(Source, Arguments) ->
    {Body, Result} = xls_parse:branch_from_clause(
        parse_clause(Source),
        Arguments,
        state,
        fun(R) -> R end,
        "failure",
        #{}
    ),
    iolist_to_binary(xls_parse:print([Body, Result])).
