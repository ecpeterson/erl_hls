-module(xls_nums_tests).

-include_lib("eunit/include/eunit.hrl").

unsigned_literal_uses_canonical_dslx_type_test() ->
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
