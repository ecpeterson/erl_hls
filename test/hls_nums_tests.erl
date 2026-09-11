-module(hls_nums_tests).

-include_lib("eunit/include/eunit.hrl").

integer_boundaries_test_() ->
    Unsigned = [{hls_nums:u8(), 8}, {hls_nums:u16(), 16},
        {hls_nums:u32(), 32}, {hls_nums:u64(), 64}] ++
        [{hls_nums:uN(Width), Width} || Width <- [24, 40, 96]],
    Signed = [{hls_nums:s8(), 8}, {hls_nums:s16(), 16},
        {hls_nums:s32(), 32}, {hls_nums:s64(), 64}],
    [integer_boundaries(Type, Width, 0, (1 bsl Width) - 1)
        || {Type, Width} <- Unsigned] ++
    [integer_boundaries(Type, Width, -(1 bsl (Width - 1)),
        (1 bsl (Width - 1)) - 1) || {Type, Width} <- Signed].

integer_boundaries(Type, Width, Minimum, Maximum) ->
    {lists:flatten(hls_type:print_type(Type)), fun() ->
        lists:foreach(fun(Value) ->
            Packed = hls_type:pack(Value, Type),
            ?assertEqual(Width, bit_size(Packed)),
            ?assertEqual({Value, <<42>>},
                hls_type:unpack(<<Packed/binary, 42>>, Type))
        end, [Minimum, Maximum, 0, 1]),
        lists:foreach(fun(Value) ->
            ?assertError(badarg, hls_type:pack(Value, Type))
        end, [Minimum - 1, Maximum + 1, 1 bsl (Width + 1),
            0.0, 1.0, invalid, <<0>>, [0]])
    end}.

numeric_wire_bytes_test() ->
    ?assertEqual(<<255>>, hls_type:pack(255, hls_nums:u8())),
    ?assertEqual(<<254, 255>>, hls_type:pack(-2, hls_nums:s16())),
    ?assertEqual(<<0, 60>>, hls_type:pack(1.0, hls_nums:float16())),
    ?assertEqual(<<0, 0, 128, 63>>, hls_type:pack(1.0, hls_nums:float32())),
    ?assertEqual(<<0, 0, 0, 0, 0, 0, 240, 63>>,
        hls_type:pack(1.0, hls_nums:float64())).

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

transformed_record_rejects_invalid_fields_test() ->
    Valid = {message, 16#abcdef, [1, 16#654321], 16#ab, 16#1020304050},
    lists:foreach(fun(Message) ->
        ?assertError(badarg, hls_variable_width_pack_fixture:pack(Message))
    end, [
        setelement(2, Valid, 1 bsl 24),
        setelement(2, Valid, -1),
        setelement(3, Valid, [1]),
        setelement(3, Valid, [1, 2, 3]),
        setelement(3, Valid, [1, 1 bsl 24]),
        setelement(4, Valid, 256),
        setelement(5, Valid, 1 bsl 40)
    ]).

transformed_record_rejects_invalid_shapes_test() ->
    lists:foreach(fun(Message) ->
        ?assertError(function_clause,
            hls_variable_width_pack_fixture:pack(Message))
    end, [not_a_record, {}, {unknown, 0, [0, 0], 0, 0},
        {message, 0, [0, 0], 0}, {message, 0, [0, 0], 0, 0, extra}]).
