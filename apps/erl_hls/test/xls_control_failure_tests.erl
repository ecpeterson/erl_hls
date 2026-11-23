-module(xls_control_failure_tests).
-include_lib("eunit/include/eunit.hrl").

%% Checks first failure oracle.
-spec first_failure_oracle_test_() -> [term()].
first_failure_oracle_test_() ->
    [?_assertEqual({Code, 0}, xls_control_failure_dslx:oracle(Mode, X, Y))
        || {Mode, X, Y, Code} <- [
            {8, 1, 1, 4}, {9, 1, 1, 5}, {10, 1, 1, 2}, {11, 1, 1, 4},
            {12, 1, 1, 4}, {12, 0, 1, 2}, {13, 1, 1, 5}, {13, 0, 1, 2},
            {20, 1, 1, 4}, {21, 1, 1, 5}, {22, 1, 1, 4}, {16, 1, 1, 4}, {16, 0, 1, 4}, {19, 0, 0, 4}]].

%% Checks arithmetic selection oracle.
-spec arithmetic_selection_oracle_test_() -> [term()].
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

%% Checks collection selection oracle.
-spec collection_selection_oracle_test_() -> [term()].
collection_selection_oracle_test_() ->
    [?_assertEqual(Expected, xls_control_failure_dslx:oracle(Mode, X, Y))
        || {Mode, X, Y, Expected} <- [
            {47, 2, 9, {0, 9}}, {47, 0, 0, {14, 0}},
            {48, 4, 0, {14, 0}}, {49, 3, 2, {14, 0}}, {50, 3, 0, {14, 0}},
            {51, 0, 7, {0, 7}}, {52, 0, 7, {0, 0}},
            {53, 0, 1, {14, 0}}, {54, 0, 1, {2, 0}},
            {55, 0, 0, {14, 0}}, {55, 1, 0, {13, 0}},
            {56, 1, 0, {14, 0}}, {57, 1, 0, {14, 0}}, {58, 1, 0, {14, 0}}]].

%% Each terminal source fault retires its proxy and preserves the finite site.
-spec proxy_decodes_control_failures_test_() -> [term()].
proxy_decodes_control_failures_test_() ->
    [{atom_to_list(Reason), fun() ->
        {ok, Fabric} = hls_fabric_test_wire:start_link(),
        {ok, Proxy} = hls_gs:start_link(xls_control_failure_fixture, [], [{fabric, Fabric, 1}]),
        unlink(Proxy),
        Monitor = monitor(process, Proxy),
        try
            Request = gen_server:send_request(Proxy, {probe, 0, 0, 0}),
            [{{0, 1}, {_, Tx, 0}, _}] = hls_fabric_test_wire:await_sends(Fabric, 1, 1000),
            Code = (23 bsl 4) bor Kind,
            Failure = {hls_actor_failure, xls_control_failure_fixture,
                #{reason => Reason, source_code => Code, source_site => 23}},
            ok = hls_fabric_test_wire:deliver(Fabric, {1, 0},
                {xls_control_failure_fixture:pack_tag(error), Tx, 0},
                <<(16#c0000000 bor Code):32/little>>),
            ?assertEqual({error, {Failure, Proxy}}, gen_server:receive_response(Request, 1000)),
            receive {'DOWN', Monitor, process, Proxy, Failure} -> ok
            after 1000 -> error(proxy_survived_terminal_fault) end,
            ?assert(is_process_alive(Fabric))
        after
            catch hls_gs:stop(Proxy),
            hls_fabric_test_wire:stop(Fabric)
        end
    end} || {Kind, Reason} <- [{1, function_clause}, {2, match_failure},
        {4, case_clause}, {5, if_clause}, {6, explicit_fail}, {13, badarith}, {14, badarg}]].

%% Native helper exceptions and marked hardware faults both take the call's exit path.
-spec actor_call_exit_parity_test_() -> [term()].
actor_call_exit_parity_test_() ->
    [{atom_to_list(Backend), fun() ->
        {ok, Fabric} = hls_fabric_test_wire:start_link(),
        Options = case Backend of cpu -> []; hardware -> [{fabric, Fabric, 1}] end,
        {ok, Actor} = hls_gs:start_link(xls_control_failure_fixture, [], Options),
        unlink(Actor),
        Parent = self(),
        try
            Caller = spawn(fun() ->
                Result = try gen_server:call(Actor, {probe, 25, 1, 0}) of
                    Value -> {returned, Value}
                catch exit:Why -> {exit, Why} end,
                Parent ! {call_outcome, self(), Result}
            end),
            case Backend of
                cpu -> ok;
                hardware ->
                    [{_, {_, Tx, _}, _}] = hls_fabric_test_wire:await_sends(Fabric, 1, 1000),
                    ok = hls_fabric_test_wire:deliver(Fabric, {1, 0},
                        {xls_control_failure_fixture:pack_tag(error), Tx, 0}, <<16#c000001d:32/little>>)
            end,
            receive
                {call_outcome, Caller, {exit, {Failure, {gen_server, call, _}}}} ->
                    case Backend of
                        cpu ->
                            {badarith, Stack} = Failure,
                            ?assert(lists:any(fun
                                ({xls_control_failure_fixture, _, _, _}) -> true;
                                (_) -> false
                            end, Stack));
                        hardware ->
                            ?assertMatch({hls_actor_failure, xls_control_failure_fixture,
                                #{reason := badarith, source_code := 29, source_site := 1}}, Failure)
                    end;
                {call_outcome, Caller, Other} -> error({callback_fault_was_not_exit, Other})
            after 1000 -> error(no_actor_failure) end,
            ?assertNot(is_process_alive(Actor))
        after
            catch hls_gs:stop(Actor),
            hls_fabric_test_wire:stop(Fabric)
        end
    end} || Backend <- [cpu, hardware]].
