-module(phi_field_tests).

-include_lib("eunit/include/eunit.hrl").

type_and_conversion_test() ->
    Type = phi_field:field(),
    ?assertEqual(32, hls_type:width(Type)),
    ?assertEqual("s32", hls_type:print_type(Type)),
    ?assertEqual(0, hls_type:zero(Type)),
    ?assertEqual(65536, phi_field:from_integer(1)),
    ?assertEqual(-32768, phi_field:from_ratio(-1, 2)),
    ?assertEqual(0.5, phi_field:to_float(32768)),
    ?assertError(badarg, phi_field:from_integer(32768)).

signed_wire_round_trip_test() ->
    Type = phi_field:field(),
    Packed = hls_type:pack(-16#1234567, Type),
    ?assertEqual(<<16#f_edcba99:32/little-unsigned-integer>>, Packed),
    ?assertEqual({-16#1234567, <<>>}, hls_type:unpack(Packed, Type)).

center_recurrence_test() ->
    One = phi_field:from_integer(1),
    OneHalf = phi_field:from_ratio(1, 2),
    ?assertEqual(
        OneHalf,
        phi_field:relax_center(0, One, 0, 0)
    ),
    ?assertEqual(
        phi_field:from_integer(1),
        phi_field:relax_center(0, One, One, 4 * One)
    ),
    ?assertEqual(
        phi_field:from_integer(2),
        phi_field:relax_center(1, One, One, 4 * One)
    ),
    ?assertEqual(
        phi_field:from_ratio(1, 12),
        phi_field:relax_center(0, 0, 0, One)
    ).

terminal_bulk_recurrence_test() ->
    One = phi_field:from_integer(1),
    ?assertEqual(
        phi_field:from_integer(1),
        phi_field:relax_bulk(One, One, 4 * One)
    ),
    ?assertEqual(
        phi_field:from_ratio(7, 12),
        phi_field:relax_bulk(0, One, 0)
    ),
    ?assertEqual(
        phi_field:from_ratio(-1, 12),
        phi_field:relax_bulk(0, 0, -One)
    ).

negative_rounding_test() ->
    ?assertEqual(0, phi_field:relax_bulk(0, 0, -5)),
    ?assertEqual(-1, phi_field:relax_bulk(0, 0, -6)),
    ?assertEqual(-1, phi_field:relax_bulk(0, 0, -7)).

all_rounding_residues_match_reference_test() ->
    lists:foreach(
        fun(Numerator) ->
            ?assertEqual(
                reference_relax_center(0, 0, 0, Numerator),
                phi_field:relax_center(0, 0, 0, Numerator)
            ),
            ?assertEqual(
                reference_relax_bulk(0, 0, Numerator),
                phi_field:relax_bulk(0, 0, Numerator)
            )
        end,
        lists:seq(-1000, 1000)
    ).

valid_domain_boundaries_match_reference_test() ->
    Minimum = -(1 bsl 31),
    Maximum = (1 bsl 31) - 1,
    Fields = [Minimum, -(1 bsl 30), -1, 0, 1, 1 bsl 30, Maximum],
    NeighborSums = [
        4 * Minimum,
        4 * -(1 bsl 30),
        -4,
        0,
        4,
        4 * (1 bsl 30),
        4 * Maximum
    ],
    lists:foreach(
        fun({Phi0, Phi1, NeighborSum}) ->
            lists:foreach(
                fun(Anyon) ->
                    ?assertEqual(
                        reference_relax_center(
                            Anyon, Phi0, Phi1, NeighborSum
                        ),
                        phi_field:relax_center(
                            Anyon, Phi0, Phi1, NeighborSum
                        )
                    )
                end,
                [0, 1]
            ),
            ?assertEqual(
                reference_relax_bulk(Phi0, Phi1, NeighborSum),
                phi_field:relax_bulk(Phi0, Phi1, NeighborSum)
            )
        end,
        [{Phi0, Phi1, NeighborSum}
            || Phi0 <- Fields,
               Phi1 <- Fields,
               NeighborSum <- NeighborSums]
    ).

saturation_test() ->
    Maximum = (1 bsl 31) - 1,
    Minimum = -(1 bsl 31),
    ?assertEqual(
        Maximum,
        phi_field:relax_center(1, Maximum, Maximum, 4 * Maximum)
    ),
    ?assertEqual(
        Minimum,
        phi_field:relax_bulk(Minimum, Minimum, 4 * Minimum)
    ).

widened_neighbor_accumulator_test() ->
    Maximum = (1 bsl 31) - 1,
    Sum = lists:foldl(fun phi_field:accumulate/2, 0,
        lists:duplicate(4, Maximum)),
    ?assertEqual(4 * Maximum, Sum).

widened_recurrence_preserves_large_uniform_fields_test() ->
    Value = 1 bsl 30,
    ?assertEqual(
        Value,
        phi_field:relax_center(0, Value, Value, 4 * Value)
    ),
    ?assertEqual(
        Value,
        phi_field:relax_bulk(Value, Value, 4 * Value)
    ),
    ?assertEqual(
        -Value,
        phi_field:relax_center(0, -Value, -Value, -4 * Value)
    ).

reference_relax_center(Anyon, Phi0, Phi1, NeighborSum) ->
    saturate_s32(
        (Anyon bsl 16) +
            round_ratio(6 * Phi0 + 2 * Phi1 + NeighborSum, 12)
    ).

reference_relax_bulk(Phi0, Phi1, NeighborSum) ->
    saturate_s32(round_ratio(Phi0 + 7 * Phi1 + NeighborSum, 12)).

round_ratio(Numerator, Denominator) when Numerator >= 0 ->
    (Numerator + Denominator div 2) div Denominator;
round_ratio(Numerator, Denominator) ->
    -round_ratio(-Numerator, Denominator).

saturate_s32(Value) when Value > (1 bsl 31) - 1 -> (1 bsl 31) - 1;
saturate_s32(Value) when Value < -(1 bsl 31) -> -(1 bsl 31);
saturate_s32(Value) -> Value.
