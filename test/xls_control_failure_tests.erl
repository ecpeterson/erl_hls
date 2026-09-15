-module(xls_control_failure_tests).
-include_lib("eunit/include/eunit.hrl").

first_failure_oracle_test_() ->
    [?_assertEqual({Code, 0}, xls_control_failure_dslx:oracle(Mode, X, Y))
        || {Mode, X, Y, Code} <- [
            {8, 1, 1, 4}, {9, 1, 1, 5}, {10, 1, 1, 2}, {11, 1, 1, 4},
            {12, 1, 1, 4}, {12, 0, 1, 2}, {13, 1, 1, 5}, {13, 0, 1, 2},
            {20, 1, 1, 4}, {21, 1, 1, 5}, {22, 1, 1, 4}, {16, 1, 1, 4}, {16, 0, 1, 4}, {19, 0, 0, 4}]].

arithmetic_selection_oracle_test_() ->
    [?_assertEqual(Expected, xls_control_failure_dslx:oracle(Mode, X, Y))
        || {Mode, X, Y, Expected} <- [
            {25, 7, 2, {0, 3}}, {26, 7, 2, {0, 1}},
            {25, 1, 0, {13, 0}}, {26, 1, 0, {13, 0}},
            {27, 1, 0, {0, 1}}, {28, 1, 0, {0, 0}}, {29, 1, 0, {0, 1}},
            {30, 1, 0, {0, 0}}, {31, 1, 0, {0, 0}},
            {32, 1, 0, {0, 0}}, {33, 1, 0, {0, 1}}, {34, 1, 0, {0, 0}},
            {35, 1, 0, {5, 0}}, {36, 1, 0, {2, 0}}, {37, 1, 0, {13, 0}},
            {38, 0, 1, {13, 0}}, {39, 1, 1, {13, 0}},
            {41, 1, 0, {0, 0}}, {42, 1, 0, {0, 202}}, {43, 1, 0, {13, 0}},
            {44, 1, 0, {0, 1}}, {45, 1, 0, {0, 0}}, {46, 1, 0, {13, 0}}]].

collection_selection_oracle_test_() ->
    [?_assertEqual(Expected, xls_control_failure_dslx:oracle(Mode, X, Y))
        || {Mode, X, Y, Expected} <- [
            {47, 2, 9, {0, 9}}, {47, 0, 0, {14, 0}},
            {48, 4, 0, {14, 0}}, {49, 3, 2, {14, 0}}, {50, 3, 0, {14, 0}},
            {51, 0, 7, {0, 7}}, {52, 0, 7, {0, 0}},
            {53, 0, 1, {14, 0}}, {54, 0, 1, {2, 0}},
            {55, 0, 0, {14, 0}}, {55, 1, 0, {13, 0}},
            {56, 1, 0, {14, 0}}, {57, 1, 0, {14, 0}}, {58, 1, 0, {14, 0}}]].

proxy_decodes_control_failures_test() ->
    {ok, Fabric} = phi_memory_fabric_fixture:start_link(),
    {ok, Proxy} = hls_gs:start_link(xls_control_failure_fixture, [], [{fabric, Fabric, 1}]),
    try
        Parent = self(),
        lists:foreach(fun({Count, Code, Reason}) ->
            spawn_link(fun() -> Parent ! {reply, gen_server:call(Proxy, {probe, 0, 0, 0})} end),
            Sends = phi_memory_fabric_fixture:await_sends(Fabric, Count, 1000),
            {{0, 1}, {_, Tx, 0}, _} = lists:last(Sends),
            ok = phi_memory_fabric_fixture:deliver(Fabric, {1, 0},
                {xls_control_failure_fixture:pack_tag(error), Tx, 0}, <<Code:32/little>>),
            receive {reply, Reply} -> ?assertEqual({error, {remote_error, Reason}}, Reply)
            after 1000 -> error(no_reply) end
        end, [{1, 2, match_failure}, {2, 4, case_clause}, {3, 5, if_clause}, {4, 13, badarith}, {5, 14, badarg}])
    after
        hls_gs:stop(Proxy),
        phi_memory_fabric_fixture:stop(Fabric)
    end.
