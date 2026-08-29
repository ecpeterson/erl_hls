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
    ?assertEqual(nomatch, binary:match(XLS, <<"x_2">>)).

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

case_match_bookkeeping_rejects_colliding_user_variable_test() ->
    Clause = parse_clause(
        "probe(Condition, Case_match_1) -> "
        "case Condition of true -> 1; false -> 2 end."
    ),
    ?assertError(
        {reserved_xls_variable, 'Case_match_1', case_match},
        xls_parse:branch_from_clause(
            Clause,
            ["condition", "case_match_1"],
            state,
            fun(R) -> R end,
            "failure",
            #{}
        )
    ).

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
    {ok, Tokens, _EndLine} = erl_scan:string(Source),
    {ok, {function, _Line, probe, _Arity, [Clause]}} =
        erl_parse:parse_form(Tokens),
    Clause.
