-module(xls_pattern_totality_tests).
-include_lib("eunit/include/eunit.hrl").

bounded_list_totality_test_() ->
    Shape = {array, unknown, 2},
    [{Pattern, fun() ->
        ?assertEqual(Total, xls_pattern_totality:prove(pattern(Pattern), Shape) =/= none)
    end} || {Pattern, Total} <- [
        {"[A, B]", true}, {"[A | _]", true}, {"[A | Tail]", true},
        {"[A, B | _]", true}, {"[A, B | Tail]", false},
        {"[A = Alias, B]", true}, {"[A | Tail = [B]]", true},
        {"[]", false}, {"[A]", false}, {"[A, B, C]", false},
        {"[A, A]", false}, {"[A | A]", false}, {"[0, B]", false},
        {"[A, B | atom]", false}
    ]].

nested_arrays_keep_separate_dimension_obligations_test() ->
    Shape = {record, message, #{values => {array, {array, unknown, 2}, 3}}},
    Pattern = pattern("#message{values = [[A, B], [C, D] | _]}"),
    ?assertEqual([
        {[{field, values}], 3},
        {[{field, values}, {index, 0}], 2},
        {[{field, values}, {index, 1}], 2}
    ], xls_pattern_totality:prove(Pattern, Shape)),
    ?assertEqual(none, xls_pattern_totality:prove(
        pattern("#message{values = [[A, B], [C, A] | _]}"), Shape)).

opaque_elements_are_not_given_a_structure_test() ->
    ?assertEqual(none, xls_pattern_totality:prove(pattern("[[A, B], C]"),
        {array, unknown, 2})),
    ?assertEqual(none, xls_pattern_totality:prove(pattern("[A, B]"), unknown)).

pattern(Text) ->
    {ok, Tokens, _} = erl_scan:string(Text ++ "."),
    {ok, [Pattern]} = erl_parse:parse_exprs(Tokens),
    Pattern.
