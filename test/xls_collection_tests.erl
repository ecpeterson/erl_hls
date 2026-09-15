-module(xls_collection_tests).
-include_lib("eunit/include/eunit.hrl").

unsupported_shapes_fail_before_xls_test() ->
    lists:foreach(fun(Expression) ->
        ?assertError(empty_xls_collection, lower(Expression))
    end, ["hls_lists:new(hls_nums:u32(), 0)",
        "hls_lists:array_slice(hls_lists:list(hls_nums:u32(), 3), V, 1, 0)"]),
    ?assertError({invalid_array_slice_length, {static, integer, -1}},
        lower("hls_lists:array_slice(hls_lists:list(hls_nums:u32(), 3), V, 1, -1)")),
    ?assertError({invalid_array_slice_length, _},
        lower("hls_lists:array_slice(hls_lists:list(hls_nums:u32(), 3), V, 1, Count)")),
    Empty = hls_lists:list(hls_nums:u8(), 0),
    ?assertEqual(<<>>, hls_type:pack([], Empty)),
    ?assertError(empty_xls_collection, hls_type:print_type(Empty)).

lower(Expression) ->
    {ok, Tokens, _} = erl_scan:string("probe(V, Count) -> " ++ Expression ++ "."),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    xls_parse:clause_outcome(Clause, ["values", "count"], state, #{}).
