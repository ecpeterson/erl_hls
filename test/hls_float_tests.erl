-module(hls_float_tests).
-include_lib("eunit/include/eunit.hrl").

binary16_exhaustive_wire_round_trip_test() ->
    Type = hls_nums:float16(),
    lists:foreach(fun(Bits) ->
        Bytes = <<Bits:16/little>>,
        case Bits band 16#7c00 of
            16#7c00 -> ?assertError(function_clause, hls_type:unpack(Bytes, Type));
            _ ->
                {Value, <<42>>} = hls_type:unpack(<<Bytes/binary, 42>>, Type),
                ?assertEqual(Bytes, hls_type:pack(Value, Type)),
                ?assertEqual(Bytes, hls_type:pack_exact(Value, Type)),
                ?assertEqual(Value, hls_type:normalize(Type, Value))
        end
    end, lists:seq(0, 65535)).

wide_formats_wire_round_trip_test_() ->
    [wire_patterns(hls_nums:float32(), 32, 8, 23),
        wire_patterns(hls_nums:float64(), 64, 11, 52)].

wire_patterns(Type, Width, ExponentBits, FractionBits) ->
    {lists:flatten(hls_type:print_type(Type)), fun() ->
        %% Visit every exponent, both signs, and fraction boundaries. A fixed
        %% pattern generator supplements those boundaries without flaky seeds.
        MaxExponent = (1 bsl ExponentBits) - 1,
        FractionMask = (1 bsl FractionBits) - 1,
        Patterns = [(Sign bsl (Width - 1)) bor (Exponent bsl FractionBits) bor Fraction
            || Sign <- [0, 1], Exponent <- lists:seq(0, MaxExponent),
                Fraction <- [0, 1, FractionMask div 2, FractionMask]],
        Random = [(N * 16#9e3779b97f4a7c15) band ((1 bsl Width) - 1)
            || N <- lists:seq(1, 1000)],
        lists:foreach(fun(Bits) ->
            Bytes = <<Bits:Width/little>>,
            case (Bits bsr FractionBits) band MaxExponent of
                MaxExponent ->
                    ?assertError(function_clause, hls_type:unpack(Bytes, Type));
                _ ->
                    {Value, <<42>>} = hls_type:unpack(<<Bytes/binary, 42>>, Type),
                    ?assertEqual(Bytes, hls_type:pack_exact(Value, Type)),
                    ?assertEqual(Value, hls_type:normalize(Type, Value))
            end
        end, Patterns ++ Random)
    end}.

rounding_and_underflow_test_() ->
    [rounding(hls_nums:float16(), 10, -14, 0.0999755859375),
        rounding(hls_nums:float32(), 23, -126, 0.10000000149011612)].

rounding(Type, FractionBits, MinimumExponent, Tenth) ->
    {lists:flatten(hls_type:print_type(Type)), fun() ->
        Step = math:pow(2, -FractionBits),
        Halfway = 1.0 + Step / 2,
        JustAbove = Halfway + math:pow(2, -52),
        Smallest = math:pow(2, MinimumExponent - FractionBits),
        Cases = [{0.1, Tenth}, {-0.1, -Tenth},
            {Halfway, 1.0}, {JustAbove, 1.0 + Step},
            {1.0 + 3 * Step / 2, 1.0 + 2 * Step},
            {-Halfway, -1.0}, {-JustAbove, -1.0 - Step},
            {Smallest, Smallest}, {Smallest / 2, +0.0},
            {-Smallest / 2, -0.0}, {3 * Smallest / 2, 2 * Smallest}],
        lists:foreach(fun({Input, Expected}) ->
            Normalized = hls_type:normalize(Type, Input),
            ?assertEqual(Expected, Normalized),
            ?assertEqual(Normalized, hls_type:normalize(Type, Normalized)),
            ?assertEqual(hls_type:pack(Input, Type), hls_type:pack(Normalized, Type))
        end, Cases),
        ?assertError({inexact_packing, Type}, hls_type:pack_exact(0.1, Type)),
        ?assertError({inexact_packing, Type}, hls_type:pack_exact(Smallest / 2, Type))
    end}.

finite_overflow_boundary_test() ->
    lists:foreach(fun({Type, Maximum, BelowOverflow, Overflow}) ->
        lists:foreach(fun(Sign) ->
            ?assertEqual(Sign * Maximum, hls_type:normalize(Type, Sign * Maximum)),
            %% Rounding to a finite maximum is permitted even just above it.
            ?assertEqual(Sign * Maximum, hls_type:normalize(Type, Sign * BelowOverflow)),
            ?assertError(badarg, hls_type:pack(Sign * Overflow, Type)),
            ?assertError(badarg, hls_type:normalize(Type, Sign * Overflow))
        end, [-1, 1])
    end, [{hls_nums:float16(), 65504.0, 65519.0, 65520.0},
        {hls_nums:float32(), (2.0 - math:pow(2, -23)) * math:pow(2, 127),
            (2.0 - 3 * math:pow(2, -25)) * math:pow(2, 127),
            (2.0 - math:pow(2, -24)) * math:pow(2, 127)}]),
    ?assertError(badarg, hls_type:pack(1.0e100, hls_nums:float16())),
    ?assertError(badarg, hls_type:pack(1.0e300, hls_nums:float32())).

numeric_coercion_and_exact_packing_test() ->
    lists:foreach(fun(Type) ->
        ?assertEqual(1.0, hls_type:normalize(Type, 1)),
        ?assertError({inexact_packing, Type}, hls_type:pack_exact(1, Type)),
        lists:foreach(fun(Value) ->
            ?assertError(badarg, hls_type:pack(Value, Type))
        end, [invalid, <<0>>, [0], 1 bsl 2000])
    end, [hls_nums:float16(), hls_nums:float32(), hls_nums:float64()]),
    ?assertEqual(0.1, hls_type:normalize(hls_nums:float64(), 0.1)),
    ?assertEqual(float(1 bsl 53), hls_type:normalize(hls_nums:float64(), (1 bsl 53) + 1)).

composed_float_normalization_test() ->
    Type = hls_vec:vector(hls_nums:float16(), 2),
    Input = [0.1, -0.0],
    Canonical = [0.0999755859375, -0.0],
    ?assertEqual(Canonical, hls_type:normalize(Type, Input)),
    ?assertEqual(<<0, 128, 102, 46>>, hls_type:pack(Input, Type)),
    ?assertEqual(hls_type:pack(Input, Type), hls_type:pack_exact(Canonical, Type)),
    ?assertError({inexact_packing, Type}, hls_type:pack_exact(Input, Type)),
    ?assertError(badarg, hls_type:pack([65520.0, 0.0], Type)).

rounding_schedule_changes_cancellation_test() ->
    Type = hls_nums:float32(),
    X = 16777216.0,
    ?assertEqual(1.0, hls_type:normalize(Type, (X + 1.0) - X)),
    ?assertEqual(+0.0, hls_type:normalize(Type, hls_type:normalize(Type, X + 1.0) - X)).
