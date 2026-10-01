-module(xls_nums_tests).

-include_lib("eunit/include/eunit.hrl").

unsigned_literal_uses_canonical_dslx_type_test() ->
    ?assertEqual("u3", lists:flatten(xls_nums:unsigned_type(3))),
    ?assertEqual("uN[96]", lists:flatten(xls_nums:unsigned_type(96))),
    ?assertEqual(
        "u32:0x0000002A",
        lists:flatten(xls_nums:unsigned_literal(42, 32))
    ),
    ?assertEqual(
        "uN[96]:0x00000000000000000000002A",
        lists:flatten(xls_nums:unsigned_literal(42, 96))
    ),
    ?assertEqual(
        "u32:0x12345678",
        lists:flatten(xls_nums:packed_unsigned_literal(
            <<16#12345678:32/little>>
        ))
    ).

signed_type_uses_canonical_dslx_type_test() ->
    ?assertEqual("s32", xls_nums:signed_type(32)),
    ?assertEqual("sN[37]", lists:flatten(xls_nums:signed_type(37))).

index_types_cover_singletons_and_power_of_two_boundaries_test() ->
    [?assertEqual(Type, lists:flatten(xls_nums:index_type(Count)))
        || {Count, Type} <- [{1, "u1"}, {2, "u1"}, {3, "u2"}, {4, "u2"},
            {9, "u4"}, {255, "u8"}, {256, "u8"}, {257, "uN[9]"},
            {65536, "u16"}, {65537, "uN[17]"}]].
