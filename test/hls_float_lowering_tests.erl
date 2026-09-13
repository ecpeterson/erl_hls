-module(hls_float_lowering_tests).
-include_lib("eunit/include/eunit.hrl").

typed_literal_test() ->
    lists:foreach(fun({Expression, Pattern}) ->
        Text = rendered(Expression),
        ?assertNotEqual(nomatch, binary:match(Text, Pattern))
    end, [{"hls_float:literal(hls_nums:float16(), -0.0)", <<"uN[16]:32768">>},
        {"hls_float:literal(hls_nums:float32(), +0.0)", <<"uN[32]:0">>},
        {"hls_float:literal(hls_nums:float64(), 1)", <<"uN[64]:4607182418800017408">>}]),
    ?assertError({untyped_float_literal, 1.5, {use, hls_float, literal, 2}}, rendered("1.5")),
    ?assertError(nonconstant_float_literal,
        rendered("hls_float:literal(hls_nums:float32(), X)")),
    ?assertError(badarg, rendered("hls_float:literal(hls_nums:float16(), 65520.0)")).

float_failure_codebook_test() ->
    Source = "test/hls_float_fixture.erl",
    {ok, Forms} = xls_parse:parse_file(Source),
    {_, Origins} = xls_failure_sites:prepare(Forms),
    Dslx = xls_parse:to_xls(Source),
    Sites = xls_failure_sites:from_artifact(Origins, Dslx),
    Arithmetic = [S || S = #{kind := badarith} <- Sites],
    ?assertEqual(7, length(Arithmetic)),
    lists:foreach(fun(#{code := C, file := F, line := L}) ->
        ?assertEqual(13, C band 15),
        ?assertEqual(<<"hls_float_fixture.erl">>, F),
        ?assert(L > 0)
    end, Arithmetic).

rendered(Expression) ->
    {ok, Tokens, _} = erl_scan:string("probe(X) -> " ++ Expression ++ "."),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    #{body := Body, result := Result} = xls_parse:clause_outcome(Clause, ["x"], state, #{}),
    iolist_to_binary(xls_parse:print([Body, Result])).
