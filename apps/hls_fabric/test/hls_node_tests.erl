-module(hls_node_tests).
-include_lib("eunit/include/eunit.hrl").

registered_bystander_test_() -> {timeout, 30, fun() ->
    hls_test_nodes:distribution(),
    {Peer, Remote} = hls_test_nodes:start_peer(),
    %% This strict server has no local_connection handler. Sending it our
    %% private request would crash it, not merely fail the connection attempt.
    {ok, Bystander} = gen_server:start({local, Remote}, hls_carrier_bench, [], []),
    Qualified = "hls_node:" ++ atom_to_list(Remote),
    try
        ?assertError(badarg, list_to_existing_atom(Qualified)),
        ?assertEqual(pong, net_adm:ping(Remote)),
        ?assertEqual(Remote, erpc:call(Remote, erlang, node, [])),
        ?assertEqual(#{routes => #{}}, gen_server:call(Bystander, info)),
        ?assertError(badarg, list_to_existing_atom(Qualified))
    after catch gen_server:stop(Bystander), peer:stop(Peer) end
end}.

local_name_collision_test_() -> {timeout, 30, fun() -> with_node(#{}, fun(_Model, Node, Name, A, _D) ->
    {ok, Bystander} = gen_server:start({local, Name}, hls_carrier_bench, [], []),
    try
        ?assertEqual(42, regsvc:ping(A, 42)),
        [#{carrier := Carrier}] = maps:values(maps:get(connections, hls_node:info(Node))),
        ?assertEqual(expected_carrier(), Carrier),
        ?assertEqual(#{routes => #{}}, gen_server:call(Bystander, info)),
        hls_node:stop(Node),
        ?assertEqual(undefined, hls_node:local_manager(Name)),
        ?assertEqual(Bystander, whereis(Name)),
        ?assertEqual(#{routes => #{}}, gen_server:call(Bystander, info))
    after catch gen_server:stop(Bystander) end
end) end}.

native_pid_test_() -> {timeout, 30, fun() -> with_node(#{}, fun(Model, Node, Name, A, D) ->
    ?assertEqual(Name, node(A)),
    ?assertNotEqual(node(), node(A)),
    ?assertEqual(pong, net_adm:ping(Name)),
    #{connections := Connections} = hls_node:info(Node),
    [#{carrier := Carrier}] = maps:values(Connections),
    ?assertEqual(expected_carrier(), Carrier),
    ?assertEqual(42, regsvc:ping(A, 42)),
    ok = regsvc:set(A, 0, 123, 16#ffffffff),
    ?assertEqual(123, regsvc:get(A, 0)),
    {ok, #{app_rx_frames := 3}} = hls_debug:get_counters(D),
    ?assertEqual({ack, 77}, gen_server:call({registers, Name}, {ping, 77})),
    %% A caller's death must not close the actor or another caller's access.
    Parent = self(),
    {_, Ref} = spawn_monitor(fun() -> Parent ! {value, regsvc:ping(A, 99)} end),
    receive {value, 99} -> ok after 3000 -> error(no_reply) end,
    receive {'DOWN', Ref, _, _, normal} -> ok after 3000 -> error(caller_alive) end,
    ?assertEqual(123, regsvc:get(A, 0)),
    #{creation := Creation} = hls_node:info(Node),
    Missing = hls_node_wire:pid(Name, Creation, 1000000),
    MissingRef = monitor(process, Missing),
    receive {'DOWN', MissingRef, process, Missing, noproc} -> ok after 3000 -> error(no_noproc) end,
    ?assertEqual(101, regsvc:ping(A, 101)),
    ?assertMatch(#{held := 0}, hls_device_fixture:stats(Model))
end) end}.

reconnect_test_() -> {timeout, 30, fun() -> with_node(#{tick_ms => 100}, fun(Model, Node, Name, A, D) ->
    ok = regsvc:set(A, 0, 1234, 16#ffffffff),
    ?assertEqual(1234, regsvc:get(A, 0)),
    #{connections := Before} = hls_node:info(Node),
    [#{source := OldSource}] = maps:values(Before),
    ok = hls_device_fixture:hold(Model),
    Old = gen_server:send_request(A, {ping, 111}),
    await(fun() -> #{held := N} = hls_device_fixture:stats(Model), N =:= 1 end),
    {ok, #{app_tx_frames := 1}} = hls_debug:get_counters(D),
    Ref = monitor(process, A),
    true = erlang:disconnect_node(Name),
    receive {'DOWN', Ref, process, A, noconnection} -> ok after 3000 -> error(no_down) end,
    ?assertMatch({error, _}, gen_server:receive_response(Old, 1000)),
    await(fun() -> maps:size(maps:get(connections, hls_node:info(Node))) =:= 0 end),
    New = gen_server:send_request(A, {ping, 222}),
    await(fun() -> #{held := N} = hls_device_fixture:stats(Model), N =:= 2 end),
    #{connections := After} = hls_node:info(Node),
    [#{source := NewSource}] = maps:values(After),
    ?assert(NewSource > OldSource),
    ok = hls_device_fixture:release(Model),
    ?assertEqual({reply, {ack, 222}}, gen_server:receive_response(New, 1000)),
    ?assertEqual(1234, regsvc:get(A, 0)),
    #{brokers := #{application := Broker}} = hls_device_fixture:stats(Model),
    ?assertMatch(#{counts := #{discarded := 1}}, hls_fabric:info(Broker)),
    ?assertEqual(A, maps:get(application, maps:get(registers, hls_node:services(Node))))
end) end}.

backpressure_test_() -> {timeout, 30, fun() -> with_node(#{queue_limit => 4}, fun(Model, _Node, _Name, A, D) ->
    ?assertEqual(0, regsvc:ping(A, 0)),
    #{brokers := #{application := Broker}} = hls_device_fixture:stats(Model),
    #{io := #{writer := Writer}} = hls_fabric:info(Broker),
    true = erlang:suspend_process(Writer),
    Parent = self(),
    {Producer, Ref} = spawn_monitor(fun() ->
        Requests = [gen_server:send_request(A, {ping, V}) || V <- lists:seq(1, 40)],
        [{reply, {ack, V}} = gen_server:receive_response(R, 3000)
            || {R, V} <- lists:zip(Requests, lists:seq(1, 40))],
        Parent ! producer_done
    end),
    try
        timer:sleep(30),
        receive producer_done -> error(writer_was_not_stalled) after 0 -> ok end,
        erlang:resume_process(Writer),
        receive producer_done -> ok; {'DOWN', Ref, process, Producer, Why} -> error({producer, Why})
        after 5000 -> error(producer_timeout) end,
        {ok, #{app_rx_frames := 41}} = hls_debug:get_counters(D),
        ?assertMatch(#{counts := #{rejected := 0}}, hls_fabric:info(Broker))
    after
        catch erlang:resume_process(Writer), exit(Producer, kill), demonitor(Ref, [flush])
    end
end) end}.

alias_timeout_test_() -> {timeout, 30, fun() -> with_node(#{}, fun(Model, _Node, _Name, A, _D) ->
    ok = hls_device_fixture:hold(Model),
    Request = gen_server:send_request(A, {ping, 88}),
    await(fun() -> #{held := N} = hls_device_fixture:stats(Model), N =:= 1 end),
    ?assertEqual(timeout, gen_server:receive_response(Request, 0)),
    ?assertMatch(#{pending := 1}, hls_fabric:client_info(A)),
    ok = hls_device_fixture:release(Model),
    ?assertEqual(99, regsvc:ping(A, 99)),
    receive {[alias | _], _} = Late -> error({late_reply, Late}) after 30 -> ok end
end) end}.

remote_peer_test_() -> {timeout, 45, fun() -> with_node(#{tick_ms => 100}, fun(_Model, Node, Name, A, _D) ->
    {Peer, Remote} = hls_test_nodes:start_peer(),
    try
        %% The custom carrier must preserve ordinary inbound/outbound TCP
        %% distribution between real ERTS nodes as well as the virtual endpoint.
        ?assertEqual(pong, net_adm:ping(Remote)),
        ?assertEqual(Remote, erpc:call(Remote, erlang, node, [])),
        ?assertEqual(node(), peer:call(Peer, erpc, call, [node(), erlang, node, []])),
        ?assertEqual(55, peer:call(Peer, regsvc, ping, [A, 55])),
        ?assertEqual(Name, peer:call(Peer, erlang, node, [A])),
        ?assertEqual(56, regsvc:ping(A, 56)),
        #{connections := Both} = hls_node:info(Node),
        ?assertEqual(2, maps:size(Both)),
        ?assertEqual([tcp], [C || #{peer := N, carrier := C} <- maps:values(Both), N =:= Remote]),
        peer:stop(Peer),
        await(fun() ->
            Connections = maps:get(connections, hls_node:info(Node)),
            not lists:member(Remote, [P || #{peer := P} <- maps:values(Connections)])
        end),
        ?assertEqual(57, regsvc:ping(A, 57))
    after catch peer:stop(Peer) end
end) end}.

transaction_capacity_test_() -> {timeout, 30, fun() -> with_node(#{}, fun(Model, _Node, _Name, A, D) ->
    ok = hls_device_fixture:hold(Model),
    Requests = [gen_server:send_request(A, {ping, V}) || V <- lists:seq(1, 256)],
    await(fun() -> #{held := N} = hls_device_fixture:stats(Model), N =:= 255 end),
    ?assertMatch(#{pending := 255, queued := 1}, hls_fabric:client_info(A)),
    {ok, #{app_rx_frames := 255}} = hls_debug:get_counters(D),
    ok = hls_device_fixture:release(Model),
    [{reply, {ack, V}} = gen_server:receive_response(R, 3000)
        || {R, V} <- lists:zip(Requests, lists:seq(1, 256))],
    ?assertMatch(#{pending := 0}, hls_fabric:client_info(A))
end) end}.

broker_admission_test_() -> {timeout, 30, fun() -> with_node(#{tx_limit => 1}, #{}, fun(Model, _Node, _Name, A, D) ->
    ?assertEqual(0, regsvc:ping(A, 0)),
    #{brokers := #{application := Broker}} = hls_device_fixture:stats(Model),
    #{io := #{writer := Writer}} = hls_fabric:info(Broker),
    ok = hls_fabric:register_route(Broker, {1, 5000}, self()),
    true = erlang:suspend_process(Writer),
    try
        Blocker = hls_fabric:send_request(Broker, {5000, 1}, {regsvc:pack_tag(ping), 0, 0}, <<17:32/little>>, infinity),
        await(fun() -> #{tx := #{per_route := Routes}} = hls_fabric:info(Broker), maps:is_key({5000, 1}, Routes) end),
        ok = regsvc:set(A, 0, 987, 16#ffffffff),
        Read = gen_server:send_request(A, {get, 0}),
        await(fun() -> #{counts := #{rejected := N}} = hls_fabric:info(Broker), N > 0 end),
        {ok, #{app_rx_frames := 1}} = hls_debug:get_counters(D),
        erlang:resume_process(Writer),
        ?assertEqual({reply, ok}, gen_server:receive_response(Blocker, 3000)),
        ?assertEqual({reply, {read, 987}}, gen_server:receive_response(Read, 3000)),
        receive {'$gen_cast', {'$hls_fabric_frame', Receipt, {1, 5000}, _, _}} ->
            hls_fabric:ack(Broker, Receipt)
        after 3000 -> error(no_blocker_reply) end,
        %% One original ping, one blocker, one cast, one get: no duplicate cast.
        ?assertMatch(#{received := 4}, hls_device_fixture:stats(Model))
    after catch erlang:resume_process(Writer) end
end) end}.

incarnation_test_() -> {timeout, 30, fun() -> with_node(#{}, fun(Model, Node, Name, OldA, _D) ->
    ok = regsvc:set(OldA, 0, 456, 16#ffffffff),
    ?assertEqual(456, regsvc:get(OldA, 0)),
    #{creation := OldCreation} = hls_node:info(Node),
    OldManager = hls_node:local_manager(Name),
    hls_node:stop(Node),
    ?assertEqual(undefined, hls_node:local_manager(Name)),
    #{brokers := Brokers} = hls_device_fixture:stats(Model),
    {ok, Replacement} = hls_node:start_link(Name, Brokers,
        [#{name => registers, module => regsvc, endpoint => 1}], #{}),
    unlink(Replacement),
    try
        NewManager = hls_node:local_manager(Name),
        ?assert(is_pid(NewManager)),
        ?assertNotEqual(OldManager, NewManager),
        #{creation := NewCreation} = hls_node:info(Replacement),
        ?assertNotEqual(OldCreation, NewCreation),
        #{registers := #{application := NewA}} = hls_node:services(Replacement),
        ?assertNotEqual(OldA, NewA),
        ?assertEqual(456, regsvc:get(NewA, 0)),
        Ref = monitor(process, OldA),
        receive {'DOWN', Ref, process, OldA, noproc} -> ok after 3000 -> error(stale_pid_alive) end
    after hls_node:stop(Replacement) end
end) end}.

broker_failure_test_() -> {timeout, 30, fun() -> with_node(#{}, fun(Model, Node, Name, A, _D) ->
    ?assertEqual(0, regsvc:ping(A, 0)),
    Ref = monitor(process, A), NodeRef = monitor(process, Node),
    ok = hls_device_fixture:stop_broker(Model, application),
    receive {'DOWN', Ref, process, A, noconnection} -> ok after 3000 -> error(actor_not_disconnected) end,
    receive {'DOWN', NodeRef, process, Node, _} -> ok after 3000 -> error(node_not_stopped) end,
    ?assertEqual(undefined, hls_node:local_manager(Name)),
    #{brokers := #{debug := Debug}} = hls_device_fixture:stats(Model),
    ?assert(is_process_alive(Debug))
end) end}.

cookie_rejection_test_() -> {timeout, 30, fun() -> with_node(#{}, fun(_Model, Node, Name, A, _D) ->
    Cookie = erlang:get_cookie(Name),
    Wrong = list_to_atom("wrong_test_cookie_" ++ integer_to_list(erlang:unique_integer([positive]))),
    try
        true = erlang:set_cookie(Name, Wrong),
        ?assertEqual(pang, net_adm:ping(Name)),
        ?assertEqual(#{}, maps:get(connections, hls_node:info(Node)))
    after erlang:set_cookie(Name, Cookie) end,
    ?assertEqual(42, regsvc:ping(A, 42)),
    [#{source := Source}] = maps:values(maps:get(connections, hls_node:info(Node))),
    ?assertEqual(1, Source)
end) end}.

local_heartbeat_test_() ->
    case expected_carrier() of
        tcp -> [];
        local -> {timeout, 15, fun() ->
            ?assertEqual(4, net_kernel:get_net_ticktime()),
            with_node(#{queue_limit => 4}, fun(Model, Node, Name, A, _D) ->
            ?assertEqual(0, regsvc:ping(A, 0)),
            #{brokers := #{application := Broker}} = hls_device_fixture:stats(Model),
            #{io := #{writer := Writer}} = hls_fabric:info(Broker),
            [Controller] = maps:keys(maps:get(connections, hls_node:info(Node))),
            true = erlang:suspend_process(Writer),
            try
                [regsvc:set(A, 0, V, 16#ffffffff) || V <- lists:seq(1, 5)],
                await(fun() -> #{queued := N} = gen_server:call(Controller, info), N =:= 4 end),
                %% The runner uses a four-second ERTS net tick timeout. A live
                %% local controller must keep ticking while its device stalls.
                timer:sleep(6000),
                ?assert(lists:member(Name, nodes(hidden))),
                ?assert(is_process_alive(Controller)),
                erlang:resume_process(Writer),
                ?assertEqual(5, regsvc:get(A, 0))
            after catch erlang:resume_process(Writer) end
        end) end}
    end.

%% Use a small +zdbbl in the local-carrier test runner. Device stalls must
%% reach ERTS's own sender admission, not accumulate in a relay mailbox.
local_admission_test_() ->
    case expected_carrier() of
        tcp -> [];
        local -> {timeout, 30, fun() -> with_node(#{queue_limit => 4}, fun(Model, Node, _Name, A, _D) ->
            ?assertEqual(0, regsvc:ping(A, 0)),
            #{brokers := #{application := Broker}} = hls_device_fixture:stats(Model),
            #{io := #{writer := Writer}} = hls_fabric:info(Broker),
            #{connections := Connections} = hls_node:info(Node),
            [Controller] = maps:keys(Connections),
            true = erlang:suspend_process(Writer),
            try
                %% Explicit nosuspend makes refusal observable without creating
                %% an unbounded collection of asynchronous call helper processes.
                Count = fill_distribution(A, 0, erlang:system_info(dist_buf_busy_limit)),
                ?assert(Count > 4),
                await(fun() -> #{queued := N} = gen_server:call(Controller, info), N =:= 4 end),
                #{queued := 4} = gen_server:call(Controller, info),
                {message_queue_len, Length} = process_info(Controller, message_queue_len),
                ?assert(Length < 10),
                erlang:resume_process(Writer),
                %% Ordinary synchronous calls resume when the device can drain;
                %% this read is ordered after all accepted casts.
                ?assertEqual(Count - 1, regsvc:get(A, 0)),
                ?assertEqual(77, regsvc:ping(A, 77)),
                ?assertMatch(#{received := N} when N =:= Count + 3, hls_device_fixture:stats(Model))
            after catch erlang:resume_process(Writer) end
        end) end}
    end.

fill_distribution(_Pid, Count, Count) -> error(no_distribution_backpressure);
fill_distribution(Pid, Count, Limit) ->
    case erlang:send(Pid, {'$gen_cast', {set, 0, Count, 16#ffffffff}}, [nosuspend]) of
        ok -> fill_distribution(Pid, Count + 1, Limit);
        nosuspend -> Count
    end.

expected_carrier() ->
    case init:get_argument(proto_dist) of {ok, [["hls_local"]]} -> local; _ -> tcp end.

with_node(Options, Fun) -> with_node(#{}, Options, Fun).
with_node(BrokerOptions, Options, Fun) ->
    hls_test_nodes:distribution(),
    application:ensure_all_started(crypto),
    [_Own, Host] = string:split(atom_to_list(node()), "@"),
    Name = list_to_atom("fpga_" ++ integer_to_list(erlang:unique_integer([positive])) ++ "@" ++ Host),
    {ok, Model} = hls_device_fixture:start(BrokerOptions),
    #{brokers := Brokers} = hls_device_fixture:stats(Model),
    {ok, Node} = hls_node:start_link(Name, Brokers,
        [#{name => registers, module => regsvc, endpoint => 1}], Options),
    unlink(Node),
    #{registers := #{application := A, debug := D}} = hls_node:services(Node),
    try Fun(Model, Node, Name, A, D)
    after catch hls_node:stop(Node), hls_device_fixture:stop(Model) end.

await(Fun) -> await(Fun, erlang:monotonic_time(millisecond) + 5000).
await(Fun, Deadline) ->
    case Fun() of
        true -> ok;
        false ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> timer:sleep(5), await(Fun, Deadline);
                false -> error(condition_timeout)
            end
    end.
