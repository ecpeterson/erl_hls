-module(xls_parse_tests).

-include_lib("eunit/include/eunit.hrl").

passive_state_observation_is_not_emitted_test() ->
    Xls = iolist_to_binary(xls_parse:to_xls("src/examples/regsvc.erl")),

    %% State serialization remains part of the generated API, but the live
    %% Service recurrence carries only the tagged struct and never packs it.
    ?assertMatch({_, _}, binary:match(Xls, <<"fn bits_from_state(s: State)">>)),
    ?assertEqual(1, length(binary:matches(Xls, <<"bits_from_state">>))),
    ?assertMatch({_, _}, binary:match(Xls, <<"let state_record = (Tag::STATE, state);">>)),
    ?assertMatch({_, _}, binary:match(Xls, <<"new_state.1">>)),

    ?assertEqual(nomatch, binary:match(Xls, <<"state_out">>)),
    ?assertEqual(nomatch, binary:match(Xls, <<"ext_state">>)).
