-module(hls_type_tests).
-include_lib("eunit/include/eunit.hrl").
-export([pack/3, width/2]).

%% An intentionally unchecked provider exercises the descriptor-level contract.
pack(Value, passthrough, [_Width]) -> Value.
width(passthrough, [Width]) -> Width.

provider_must_return_declared_binary_width_test() ->
    Type = {hls_type, ?MODULE, passthrough, [16]},
    ?assertEqual(<<1, 2>>, hls_type:pack(<<1, 2>>, Type)),
    lists:foreach(fun(Bytes) ->
        ActualWidth = bit_size(Bytes),
        ?assertError({invalid_packed_width, Type, 16, ActualWidth},
            hls_type:pack(Bytes, Type))
    end, [<<>>, <<1>>, <<1, 2, 3>>]),
    lists:foreach(fun(Value) ->
        ?assertError({invalid_packed_value, Type}, hls_type:pack(Value, Type))
    end, [<<1:1>>, [<<1, 2>>], 0, invalid]).

nested_provider_width_errors_cannot_cancel_test() ->
    Element = {hls_type, ?MODULE, passthrough, [16]},
    Type = hls_lists:list(Element, 2),
    ?assertError({invalid_packed_width, Element, 16, 8},
        hls_type:pack([<<1>>, <<2, 3, 4>>], Type)).
