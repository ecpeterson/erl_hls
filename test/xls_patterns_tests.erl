-module(xls_patterns_tests).
-include_lib("eunit/include/eunit.hrl").
-include("../src/backend/xls/xls_parse.hrl").

assignment_preserves_existing_binding_test() ->
    State = #clause_state{bindings = #{'Existing' => "original"}},
    Next = xls_pattern_lower:match(pattern("[Existing, New]"), "values", State),
    ?assertEqual("original", maps:get('Existing', Next#clause_state.bindings)),
    ?assert(is_map_key('New', Next#clause_state.bindings)),
    ?assertEqual("values", xls_parse:reference(Next)),
    ?assertNotEqual([], Next#clause_state.failures).

clause_mismatch_does_not_raise_body_failure_test() ->
    {Next, Conditions} = xls_pattern_lower:lower([pattern("[1, X, X]")],
        [xls_pattern_lower:value_argument("values")], #clause_state{}),
    ?assertEqual([], Next#clause_state.failures),
    ?assertEqual(3, length(Conditions)),
    ?assert(is_map_key('X', Next#clause_state.bindings)).

list_shape_mismatch_remains_a_predicate_test() ->
    lists:foreach(fun({Source, Test}) ->
        {_, Conditions} = xls_pattern_lower:lower([pattern(Source)],
            [xls_pattern_lower:value_argument("values")], #clause_state{}),
        ?assert(lists:member(Test, [iolist_to_binary(C) || C <- Conditions]))
    end, [{"[]", <<"array_size(values) == u32:0">>},
        {"[_, _]", <<"array_size(values) == u32:2">>},
        {"[_, _ | _]", <<"array_size(values) >= u32:2">>}]).

improper_list_patterns_have_a_diagnostic_test_() ->
    [?_assertException(error, {unsupported_xls_list_tail_pattern, _},
        xls_pattern_lower:lower([pattern(Source)],
            [xls_pattern_lower:value_argument("values")], #clause_state{}))
        || Source <- ["[X | 7]", "[X | bad_tail]", "[X | {A, B}]"]].

list_pattern_origins_cover_length_and_element_failures_test() ->
    Forms = [form("-file(\"pattern_fixture.erl\", 1)."),
        form("-module(pattern_fixture)."),
        form("f(V) ->\n [0, _] = V,\n [] = V,\n V.")],
    {Annotated, Sites} = xls_failure_sites:prepare(Forms),
    [Clause] = xls_parse:find_function(Annotated, f, 1),
    Outcome = xls_parse:clause_outcome(Clause, ["values"], cell, #{}),
    Body = xls_parse:print([maps:get(body, Outcome), maps:get(failure, Outcome)]),
    Retained = xls_failure_sites:allocate(Sites, Body),
    ?assertEqual([{2, match_failure}, {3, match_failure}],
        [{Line, Kind} || #{line := Line, kind := Kind} <- Retained]).

pattern(Source) ->
    {function, _, f, _, [{clause, _, [Pattern], _, _}]} =
        form("f(" ++ Source ++ ") -> ok."),
    Pattern.

form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.
