-module(hls_numeric_lowering_tests).
-include_lib("eunit/include/eunit.hrl").

wrapping_literals_are_normalized_before_dslx_typechecking_test() ->
    Generated = iolist_to_binary(hls_numeric_dslx:to_dslx()),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"u8:255">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"s8:-127">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"s8:-128">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<" as uN[24])">>)).

host_only_operations_fail_explicitly_during_lowering_test() ->
    lists:foreach(fun(Operation) ->
        ?assertError({host_only_type_operation, Operation},
            hls_type:transpile(Operation, [], unused_state))
    end, [normalize, pack_exact]).
