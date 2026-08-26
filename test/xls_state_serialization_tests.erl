-module(xls_state_serialization_tests).

-include_lib("eunit/include/eunit.hrl").

state_roundtrip_test() ->
    Registers = lists:seq(1, 16),
    Packed = regsvc:pack({state, Registers}),
    Expected = iolist_to_binary([
        <<Value:32/little-unsigned-integer>>
        || Value <- lists:reverse(Registers)
    ]),
    ?assertEqual(Expected, Packed),
    ?assertEqual({{state, Registers}, <<>>}, regsvc:unpack(state, Packed)).
