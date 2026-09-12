-module(xls_helpers_tests).
-include_lib("eunit/include/eunit.hrl").

reachable_graph_test() ->
    {Forms, Helpers} = prepare([
        "root() -> outer(1) + outer(2).",
        "-spec outer(hls_nums:u32()) -> hls_nums:u32().",
        "outer(X) -> helper_fixture:inner(X).",
        "-spec inner(hls_nums:u32()) -> hls_nums:u32().",
        "inner(X) -> X + 1.",
        "unused() -> io:format(\"host only\"), arbitrary()."
    ]),
    ?assertEqual(["hls_local_inner__1", "hls_local_outer__1"],
        [Name || #{name := Name} <- Helpers]),
    [{clause, _, _, _, [{op, _, '+',
        {xls_helper_call, _, "hls_local_outer__1", _},
        {xls_helper_call, _, "hls_local_outer__1", _}}]}] =
        xls_parse:find_function(Forms, root, 0),
    Emitted = iolist_to_binary(xls_helpers:emit(Helpers, cell, #{})),
    ?assertNotEqual(nomatch, binary:match(Emitted, <<"{  // L1\n">>)),
    ?assertEqual(nomatch, binary:match(Emitted, <<"unused">>)).

cycle_has_a_finite_diagnostic_test() ->
    ?assertError({recursive_xls_helpers, [{left, 1}, {right, 1}, {left, 1}]}, prepare([
        "root() -> left(1).",
        "-spec left(hls_nums:u32()) -> hls_nums:u32().",
        "left(X) -> right(X).",
        "-spec right(hls_nums:u32()) -> hls_nums:u32().",
        "right(X) -> left(X)."
    ])).

callee_precedes_caller_test() ->
    {_, Helpers} = prepare([
        "root() -> aaa(1).",
        "-spec aaa(hls_nums:u32()) -> hls_nums:u32().", "aaa(X) -> zzz(X).",
        "-spec zzz(hls_nums:u32()) -> hls_nums:u32().", "zzz(X) -> X."
    ]),
    ?assertEqual(["hls_local_zzz__1", "hls_local_aaa__1"],
        [Name || #{name := Name} <- Helpers]).

self_recursion_test() ->
    ?assertError({recursive_xls_helpers, [{helper, 1}, {helper, 1}]}, prepare([
        "root() -> helper(1).",
        "-spec helper(hls_nums:u32()) -> hls_nums:u32().", "helper(X) -> helper(X)."
    ])).

overloaded_arities_have_distinct_names_test() ->
    {_, Helpers} = prepare([
        "root() -> value() + value(1).",
        "-spec value() -> hls_nums:u32().",
        "value() -> 1.",
        "-spec value(hls_nums:u32()) -> hls_nums:u32().",
        "value(X) -> X."
    ]),
    ?assertEqual(["hls_local_value__0", "hls_local_value__1"],
        [Name || #{name := Name} <- Helpers]).

invalid_helper_head_test_() ->
    [?_assertException(error, {unsupported_xls_helper_head, _}, prepare([
        "root() -> helper(1, 2).",
        "-spec helper(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().", Source
    ])) || Source <- [
        "helper(X, X) -> X.",
        "helper({X, Y}, _) -> X + Y.",
        "helper(X, _) when X > 0 -> X.",
        "helper(0, _) -> 0; helper(X, _) -> X."
    ]].

missing_or_unbounded_spec_test_() ->
    [?_assertException(error, {missing_xls_helper_spec, _},
        prepare(["root() -> helper(1).", "helper(X) -> X."])),
     ?_assertException(error, {unsupported_xls_helper_type, _, _},
        prepare(["root() -> helper(1).",
            "-spec helper(integer()) -> integer().", "helper(X) -> X."])),
     ?_assertException(error, {unsupported_xls_helper_spec, _},
        prepare(["root() -> helper(1).",
            "-spec helper(hls_nums:u32()) -> hls_nums:u32(); (boolean()) -> boolean().",
            "helper(X) -> X."]))].

undefined_helper_test() ->
    ?assertError({undefined_xls_helper, 1, {missing, 1}},
        prepare(["root() -> missing(1)."])).

callback_is_not_a_helper_test() ->
    ?assertError({xls_helper_calls_callback, 1, {root, 0}},
        prepare(["root() -> root()."])).

include_origin_diagnostic_test() ->
    ?assertError({missing_xls_helper_spec, {"helpers.hrl", 1, {helper, 0}}},
        prepare(["root() -> helper().", "-file(\"helpers.hrl\", 1).",
            "helper() -> 0."])).

typed_composite_helper_test() ->
    {_, [#{arguments := [Input], result := Output}]} = prepare([
        "root() -> helper({true, #cell{}}).",
        "-spec helper({boolean(), #cell{}}) -> #report{}.",
        "helper(Pair) -> {_, Cell} = Pair, #report{value = Cell#cell.value}."
    ]),
    ?assertEqual(<<"(bool, (Tag, Cell), )">>, iolist_to_binary(Input)),
    ?assertEqual(<<"(Tag, Report, bits[32])">>, iolist_to_binary(Output)).

prepare(Sources) ->
    Forms = [form(S) || S <- [
        "-module(helper_fixture).", "-hls_data(cell).", "-hls_tags([report]).",
        "-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).",
        "-record(report, {value = hls_type:zero() :: hls_nums:u32()})." | Sources]],
    xls_helpers:prepare(Forms, [{root, 0}]).

form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.
