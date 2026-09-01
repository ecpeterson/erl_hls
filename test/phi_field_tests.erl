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
    ThreeQuarters = phi_field:from_ratio(3, 4),
    ?assertEqual(
        ThreeQuarters,
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
        phi_field:from_ratio(1, 24),
        phi_field:relax_center(0, 0, 0, One)
    ).

terminal_bulk_recurrence_test() ->
    One = phi_field:from_integer(1),
    ?assertEqual(
        phi_field:from_integer(1),
        phi_field:relax_bulk(One, One, 4 * One)
    ),
    ?assertEqual(
        phi_field:from_ratio(3, 4),
        phi_field:relax_bulk(0, One, 0)
    ),
    ?assertEqual(
        phi_field:from_ratio(-1, 20),
        phi_field:relax_bulk(0, 0, -One)
    ).

negative_rounding_test() ->
    ?assertEqual(0, phi_field:relax_bulk(0, 0, -9)),
    ?assertEqual(-1, phi_field:relax_bulk(0, 0, -10)),
    ?assertEqual(-1, phi_field:relax_bulk(0, 0, -11)).

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
