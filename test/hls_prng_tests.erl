-module(hls_prng_tests).

-include_lib("eunit/include/eunit.hrl").

xorshift32_known_sequence_test() ->
    State1 = hls_prng:xorshift32(16#12345678),
    State2 = hls_prng:xorshift32(State1),
    State3 = hls_prng:xorshift32(State2),
    ?assertEqual(16#87985aa5, State1),
    ?assertEqual(16#155b24a3, State2),
    ?assertEqual(16#4820f4c4, State3).

xorshift32_has_fixed_width_beam_semantics_test() ->
    ?assertEqual(16#00042021, hls_prng:xorshift32(1)),
    ?assertEqual(16#0003e01f, hls_prng:xorshift32(16#ffffffff)),
    ?assertEqual(0, hls_prng:xorshift32(0)).

xorshift32_rejects_out_of_range_values_test() ->
    lists:foreach(
        fun(Value) ->
            ?assertError(badarg, hls_prng:xorshift32(Value))
        end,
        [-1, 16#100000000]
    ).

xorshift32_transpiles_to_sequential_fixed_width_steps_test() ->
    Clause = parse_clause(
        "probe(Value) -> hls_prng:xorshift32(Value)."
    ),
    {Body, Result} = xls_parse:branch_from_clause(
        Clause,
        ["value"],
        state,
        fun(R) -> R end,
        "failure",
        #{}
    ),
    XLS = iolist_to_binary(xls_parse:print([Body, Result])),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<
            "let _0 = (Value_1 ^ (Value_1 << u32:13)) & "
            "u32:0xffffffff;"
        >>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<
            "let _1 = (_0 ^ (_0 >> u32:17)) & u32:0xffffffff;"
        >>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<
            "let _2 = (_1 ^ (_1 << u32:5)) & u32:0xffffffff;"
        >>)
    ).

parse_clause(Source) ->
    {ok, Tokens, _EndLocation} = erl_scan:string(Source),
    {ok, {function, _Line, probe, 1, [Clause]}} =
        erl_parse:parse_form(Tokens),
    Clause.
