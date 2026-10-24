-module(xls_named_bits_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% Nominal spelling changes the DSLX type, while the encoded integer follows ordinary provider laws.
-spec unsigned_encoding_test() -> ok.
unsigned_encoding_test() ->
    Types = [{xls_named_bits:local('Status', 2), 2, <<"Status">>},
        {xls_named_bits:local('Members', 9), 9, <<"Members">>},
        {xls_named_bits:qualified(hls_failure, 'Code', 16), 16, <<"hls_failure::Code">>}],
    lists:foreach(fun({Type, Width, Name}) ->
        ?assertEqual(Name, iolist_to_binary(hls_type:print_type(Type))),
        ?assertEqual(Width, hls_type:width(Type)),
        ?assertEqual(Width, hls_type:value_width(Type)),
        ?assertEqual(0, hls_type:zero(Type)),
        ?assertEqual(bit_cast, hls_type:dslx_codec(Type)),
        lists:foreach(fun(Value) ->
            Packed = <<Value:Width/little>>,
            ?assertEqual(Packed, hls_type:pack_exact(Value, Type)),
            ?assertEqual({Value, <<5:3>>}, hls_type:unpack(<<Packed/bitstring, 5:3>>, Type))
        end, [0, 1, (1 bsl Width) - 1]),
        ?assertError(badarg, hls_type:pack(-1, Type)),
        ?assertError(badarg, hls_type:pack(1 bsl Width, Type))
    end, Types),
    ok.
