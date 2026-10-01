-module(hls_float_arithmetic_tests).
-include_lib("eunit/include/eunit.hrl").

formats() -> [hls_nums:float16(), hls_nums:float32(), hls_nums:float64()].

arithmetic_test() ->
    lists:foreach(fun(T) ->
        ?assertEqual(3.75, hls_float:add(T, 1.5, 2.25)),
        ?assertEqual(-0.75, hls_float:sub(T, 1.5, 2.25)),
        ?assertEqual(-3.375, hls_float:mul(T, -1.5, 2.25)),
        ?assert(hls_float:eq(T, -0.0, 0.0)),
        ?assert(hls_float:lt(T, -1.0, 0.0))
    end, formats()).

rounding_schedule_test() ->
    T = hls_nums:float32(),
    ?assertEqual(0.0, hls_float:sub(T, hls_float:add(T, 16777216.0, 1.0), 16777216.0)),
    ?assertEqual(1.0, (16777216.0 + 1.0) - 16777216.0).

zeros_underflow_and_overflow_test() ->
    lists:foreach(fun(T) ->
        {E, F} = hls_float:format(T),
        W = 1 + E + F,
        Min = decoded(T, 1 bsl F),
        Tiny = decoded(T, 1),
        Max = decoded(T, (((1 bsl E) - 1) bsl F) - 1),
        Zero = fun(Sign, V) -> ?assertEqual(<<(Sign bsl (W - 1)):W/little>>, hls_type:pack(V, T)) end,
        Zero(1, hls_float:add(T, -0.0, -0.0)),
        Zero(0, hls_float:add(T, -1.0, 1.0)),
        Zero(1, hls_float:sub(T, -0.0, 0.0)),
        Zero(0, hls_float:sub(T, -0.0, -0.0)),
        Zero(1, hls_float:mul(T, -1.0, Tiny)),
        Zero(1, hls_float:mul(T, -Min, 0.5)),
        ?assertEqual(Min, hls_float:add(T, Min, Tiny)),
        ?assert(hls_float:eq(T, Tiny, -Tiny)),
        ?assertNot(hls_float:lt(T, -Tiny, 0.0)),
        ?assertError(badarith, hls_float:add(T, Max, Max)),
        ?assertError(badarith, hls_float:mul(T, Max, 2.0))
    end, formats()).

decoded(T, Bits) ->
    W = hls_type:width(T),
    {V, <<>>} = hls_type:unpack(<<Bits:W/little>>, T), V.
