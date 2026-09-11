-module(hls_fixed_tests).
-include_lib("eunit/include/eunit.hrl").

formats_and_conversion_test() ->
    lists:foreach(fun({Width, Fraction}) ->
        Type = hls_fixed:signed(Width, Fraction),
        Scale = 1 bsl Fraction,
        ?assertEqual(Width, hls_type:width(Type)),
        ?assertEqual(0, hls_type:zero(Type)),
        ?assertEqual(-Scale, hls_fixed:from_integer(Type, -1)),
        ?assertEqual(-1.0, hls_fixed:to_float(Type, -Scale)),
        ?assertEqual((Scale + 1) div 3, hls_fixed:from_ratio(Type, 1, 3)),
        ?assertEqual(-((Scale + 1) div 3), hls_fixed:from_ratio(Type, -1, 3))
    end, [{8, 0}, {8, 7}, {16, 8}, {24, 12}, {32, 16}]).

checked_boundaries_and_explicit_saturation_test() ->
    Type = hls_fixed:signed(8, 4),
    ?assertEqual(127, hls_fixed:from_ratio(Type, 127, 16)),
    ?assertEqual(-128, hls_fixed:from_integer(Type, -8)),
    ?assertError(badarg, hls_fixed:from_integer(Type, 8)),
    ?assertError(badarg, hls_fixed:from_ratio(Type, -129, 16)),
    ?assertError(badarg, hls_type:pack(128, Type)),
    ?assertError(badarg, hls_type:pack(-129, Type)),
    ?assertEqual(127, hls_fixed:saturate(Type, 128)),
    ?assertEqual(-128, hls_fixed:saturate(Type, -129)),
    ?assertEqual(7, hls_fixed:saturate(Type, 7)),
    ?assertEqual(<<128>>, hls_type:pack(-128, Type)),
    ?assertEqual({-128, <<42>>}, hls_type:unpack(<<128, 42>>, Type)).

ties_and_invalid_formats_test() ->
    ?assertEqual(-1, hls_fixed:round_ratio(-6, 12)),
    ?assertEqual(1, hls_fixed:round_ratio(6, 12)),
    ?assertEqual(0, hls_fixed:round_ratio(-5, 12)),
    ?assertError(badarg, hls_fixed:round_ratio(1, 0)),
    lists:foreach(fun({Width, Fraction}) ->
        ?assertError(function_clause, hls_fixed:signed(Width, Fraction)),
        ?assertError(function_clause,
            hls_type:width({hls_type, hls_fixed, signed, [Width, Fraction]}))
    end, [{0, 0}, {7, 2}, {16, -1}, {16, 16}, {16, 1.5}]).
