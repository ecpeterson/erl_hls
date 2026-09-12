-module(xls_control_failure_tests).
-include_lib("eunit/include/eunit.hrl").

first_failure_oracle_test_() ->
    [?_assertEqual({Code, 0}, xls_control_failure_dslx:oracle(Mode, X, Y))
        || {Mode, X, Y, Code} <- [
            {8, 1, 1, 4}, {9, 1, 1, 5}, {10, 1, 1, 2}, {11, 1, 1, 4},
            {12, 1, 1, 4}, {12, 0, 1, 2}, {13, 1, 1, 5}, {13, 0, 1, 2},
            {20, 1, 1, 4}, {21, 1, 1, 5}, {22, 1, 1, 4}, {16, 1, 1, 4}, {16, 0, 1, 4}, {19, 0, 0, 4}]].

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
        end, [{1, 2, match_failure}, {2, 4, case_clause}, {3, 5, if_clause}])
    after
        hls_gs:stop(Proxy),
        phi_memory_fabric_fixture:stop(Fabric)
    end.
