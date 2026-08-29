-module(xls_parse_tests).

-include_lib("eunit/include/eunit.hrl").

passive_state_observation_is_not_emitted_test() ->
    Xls = iolist_to_binary(xls_parse:to_xls("src/examples/regsvc.erl")),

    %% State serialization remains part of the generated API, but the live
    %% Service recurrence carries only the tagged struct and never packs it.
    ?assertMatch({_, _}, binary:match(Xls, <<"fn bits_from_state(s: State)">>)),
    ?assertEqual(1, length(binary:matches(Xls, <<"bits_from_state">>))),
    ?assertMatch({_, _}, binary:match(Xls, <<"let state_record = (Tag::STATE, state);">>)),
    ?assertMatch({_, _}, binary:match(Xls, <<"new_state.1">>)),

    ?assertEqual(nomatch, binary:match(Xls, <<"state_out">>)),
    ?assertEqual(nomatch, binary:match(Xls, <<"ext_state">>)).

ordered_gs_clauses_share_one_tag_arm_test() ->
    Xls = iolist_to_binary(xls_parse:to_xls("src/examples/regsvc.erl")),

    %% Multiple cast and call clauses each share one wire-tag dispatch arm.
    ?assertEqual(1, length(binary:matches(Xls, <<"Tag::SET =>">>))),
    ?assertEqual(1, length(binary:matches(Xls, <<"Tag::BULK_GET =>">>))).

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
        "-xls_data(state).\n"
        "-xls_tags([message]).\n"
        "-record(message, {\n"
        "  value = xls_type:zero() :: xls_nums:u32()\n"
        "}).\n"
        "-record(state, {\n"
        "  value = xls_type:zero() :: xls_nums:u32()\n"
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
            {ambiguous_xls_gs_callback_tags, [message]},
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

non_word_aligned_state_machine_message_is_rejected_test() ->
    Path = filename:join("_build", "non_word_statem_fixture.erl"),
    ok = filelib:ensure_dir(Path),
    Source = <<
        "-module(non_word_statem_fixture).\n"
        "-xls_data(cell).\n"
        "-xls_phases([waiting]).\n"
        "-xls_outputs([out]).\n"
        "-xls_mailbox_capacity(1).\n"
        "-xls_tags([message]).\n"
        "-record(message, {\n"
        "  value = xls_type:zero() :: xls_nums:u8()\n"
        "}).\n"
        "-record(cell, {\n"
        "  value = xls_type:zero() :: xls_nums:u32()\n"
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

assert_bad_init_head(ModuleName, InitSource) ->
    Path = filename:join("_build", ModuleName ++ ".erl"),
    ok = filelib:ensure_dir(Path),
    Source = iolist_to_binary([
        "-module(", ModuleName, ").\n",
        "-xls_data(cell).\n",
        "-xls_phases([waiting]).\n",
        "-xls_outputs([out]).\n",
        "-xls_mailbox_capacity(1).\n",
        "-xls_tags([message]).\n",
        "-record(message, {\n",
        "  value = xls_type:zero() :: xls_nums:u32()\n",
        "}).\n",
        "-record(cell, {\n",
        "  value = xls_type:zero() :: xls_nums:u32()\n",
        "}).\n",
        InitSource
    ]),
    ok = file:write_file(Path, Source),
    try
        ?assertException(
            error,
            {unsupported_xls_statem_init_head, _, _, _},
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
        xls_callback_lower:record_argument(
            message,
            "message",
            "(Tag::MESSAGE, message, bits)"
        ),
        xls_callback_lower:record_argument(
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
