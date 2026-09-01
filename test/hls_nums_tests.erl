-module(hls_nums_tests).

-include_lib("eunit/include/eunit.hrl").

variable_unsigned_type_test() ->
    Type = hls_nums:uN(96),
    ?assertEqual(96, hls_type:width(Type)),
    ?assertEqual("uN[96]", lists:flatten(hls_type:print_type(Type))),
    ?assertEqual(0, hls_type:zero(Type)).

variable_unsigned_round_trip_test() ->
    Type = hls_nums:uN(24),
    Packed = hls_type:pack(16#abcdef, Type),
    ?assertEqual(<<16#abcdef:24/little>>, Packed),
    ?assertEqual({16#abcdef, <<>>}, hls_type:unpack(Packed, Type)),
    ?assertError(function_clause, hls_nums:uN(0)),
    ?assertError(function_clause, hls_nums:uN(3)).

variable_unsigned_type_transpiles_test() ->
    {ok, Tokens, _EndLine} = erl_scan:string(
        "probe() -> hls_type:as(hls_nums:uN(24), 0)."
    ),
    {ok, {function, _Line, probe, 0, [Clause]}} =
        erl_parse:parse_form(Tokens),
    {Body, Result} = xls_parse:branch_from_clause(
        Clause,
        [],
        state,
        fun(Reference) -> Reference end,
        "failure",
        #{}
    ),
    DSLX = iolist_to_binary(xls_parse:print([Body, Result])),
    ?assertNotEqual(nomatch, binary:match(DSLX, <<"(0 as uN[24])">>)).

transformed_record_supports_variable_width_fields_and_lists_test() ->
    Message = {message, 16#abcdef, [1, 16#654321], 16#ab, 16#1020304050},
    Packed = hls_variable_width_pack_fixture:pack(Message),
    ?assertEqual(120, hls_variable_width_pack_fixture:pack_width(message)),
    ?assertEqual(24, hls_variable_width_pack_fixture:pack_width(state)),
    ?assertEqual(
        hls_variable_width_pack_fixture:pack_width(message),
        bit_size(Packed)
    ),
    ?assertEqual(
        <<16#abcdef:24/little,
          16#654321:24/little,
          1:24/little,
          16#ab:8/little,
          16#1020304050:40/little>>,
        Packed
    ),
    ?assertEqual(
        {Message, <<>>},
        hls_variable_width_pack_fixture:unpack(message, Packed)
    ).
