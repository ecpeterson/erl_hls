-module(hls_node_actor_tests).
-include_lib("eunit/include/eunit.hrl").

inconsistent_descriptor_rejected_test_() -> {timeout, 30, fun() -> with_node(fun(Ctx) ->
    #{brokers := Brokers, services := Services, register := Register} = Ctx,
    BadServices = [case Service of
        #{topology := D = #{actors := [A | Actors]}} ->
            Service#{topology := D#{actors := [A#{endpoint := 1} | Actors]}};
        _ -> Service
    end || Service <- Services],
    Name = name(),
    Parent = self(),
    {Starter, Ref} = spawn_monitor(fun() ->
        process_flag(trap_exit, true),
        Parent ! {self(), hls_node:start_link(Name, Brokers, BadServices, #{})}
    end),
    receive {Starter, Result} -> ?assertMatch({error, _}, Result)
    after 5000 -> error(no_start_result) end,
    receive {'DOWN', Ref, process, Starter, normal} -> ok
    after 5000 -> error(starter_alive) end,
    ?assertEqual(undefined, hls_node:local_manager(Name)),
    ?assertEqual(41, regsvc:ping(Register, 41))
end) end}.

multiple_deployments_test_() -> {timeout, 30, fun() -> with_node(fun(Ctx) ->
    #{brokers := Brokers, app := App, services := [_, Workers]} = Ctx,
    {Plan, Specs, _} = hls_actor_pid_dslx:fixture(),
    Other = hls_node_topology:normalize(Plan, Specs, #{even => 17, odd => 18}),
    Services = [#{name => registers, module => regsvc, endpoint => 65535}, Workers,
        #{name => workers_again, topology => Other, debug_endpoint => 12}],
    lists:foreach(fun(Ordered) ->
        Name = name(),
        {ok, Device} = hls_node:start_link(Name, Brokers, Ordered, #{}),
        unlink(Device),
        try
            #{creation := Creation} = hls_node:info(Device),
            #{registers := #{application := Register, debug := RegisterDebug},
                workers := #{actors := Left, debug := LeftDebug},
                workers_again := #{actors := Right, debug := RightDebug}} = hls_node:services(Device),
            ?assertEqual(lists:sort(maps:keys(Left)), lists:sort(maps:keys(Right))),
            Pids = maps:values(Left) ++ maps:values(Right) ++
                [Register, RegisterDebug, LeftDebug, RightDebug],
            ?assertEqual(12, length(lists:usort(Pids))),
            %% The highest standalone endpoint borders the actor PID domain.
            ?assertEqual(hls_node_wire:pid(Name, Creation, 16#1ffff), Register),
            ?assertEqual(hls_node_wire:pid(Name, Creation, 16#20000), RegisterDebug),
            First = {family, cells, [0, 0]},
            ?assertEqual(hls_node_wire:pid(Name, Creation, 16#20001), maps:get(First, Left)),
            ?assertEqual(hls_node_wire:pid(Name, Creation, 16#20005), maps:get(First, Right)),
            ?assertEqual(31, regsvc:ping(Register, 31)),
            Before = length(casts(App)),
            gen_server:cast(maps:get(First, Left), {work, 32}),
            gen_server:cast(maps:get(First, Right), {work, 33}),
            await(fun() -> length(casts(App)) =:= Before + 2 end),
            ?assertEqual([{7, 0, 32}, {17, 0, 33}], lists:nthtail(Before, casts(App))),
            ?assertEqual({ok, <<34:32/little>>}, hls_debug:query(LeftDebug, 16#11, <<34:32/little>>, 5000)),
            ?assertEqual({ok, <<35:32/little>>}, hls_debug:query(RightDebug, 16#11, <<35:32/little>>, 5000))
        after hls_node:stop(Device) end
    end, [Services, lists:reverse(Services)])
end) end}.

actor_destinations_and_order_test_() -> {timeout, 30, fun() -> with_node(fun(Ctx) ->
    #{node := Node, actors := Actors, app := App, register := Register} = Ctx,
    A = maps:get({family, cells, [0, 0]}, Actors),
    B = maps:get({family, cells, [1, 0]}, Actors),
    ?assertNotEqual(A, B),
    ?assertNotEqual(A, Register),
    ?assertEqual(node(A), node(Register)),
    Sequence = [{A, 1}, {B, 2}, {A, 3}, {B, 4}],
    [gen_server:cast(Pid, {work, Value}) || {Pid, Value} <- Sequence],
    await(fun() -> length(casts(App)) =:= 4 end),
    %% These coordinates share one scheduler but retain distinct RAM slots.
    ?assertEqual([{7, 0, 1}, {7, 1, 2}, {7, 0, 3}, {7, 1, 4}], casts(App)),
    ?assertEqual({error, unsupported_call}, gen_server:call(A, {work, 99})),
    ?assertEqual({error, unsupported_call}, gen_server:call(B, inspect)),
    ?assertEqual(42, regsvc:ping(Register, 42)),
    ?assertEqual(4, length(casts(App))),
    #{pending := 0, queued := 0, route := {Source, 7}} = hls_fabric:client_info(A),
    ?assertMatch(#{route := {Source, 7}}, hls_fabric:client_info(B)),
    #{routes := Routes} = hls_actor_broker_fixture:stats(App),
    ?assertEqual([{1, Source}, {7, Source}, {8, Source}], lists:sort(maps:keys(Routes))),
    ?assertEqual(1, map_size(maps:get(connections, hls_node:info(Node))))
end) end}.

shared_debug_transaction_wrap_test_() -> {timeout, 30, fun() -> with_node(fun(Ctx) ->
    #{debug := Debug, debug_broker := Broker, actors := Actors, app := App,
        register := Register} = Ctx,
    ok = hls_actor_broker_fixture:hold(Broker),
    Requests = [{V, gen_server:send_request(Debug, {query, 16#11, <<V:32/little>>})}
        || V <- lists:seq(1, 257)],
    await(fun() -> maps:get(held, hls_actor_broker_fixture:stats(Broker)) =:= 256 end),
    ?assertMatch(#{pending := 256, queued := 1}, hls_fabric:client_info(Debug)),
    ?assertEqual(51, regsvc:ping(Register, 51)),
    [gen_server:cast(Pid, {work, 52}) || Pid <- maps:values(Actors)],
    await(fun() -> length(casts(App)) =:= 4 end),
    ok = hls_actor_broker_fixture:release(Broker),
    [?assertEqual({reply, {ok, <<V:32/little>>}}, gen_server:receive_response(Id, 5000))
        || {V, Id} <- Requests],
    #{events := Events} = hls_actor_broker_fixture:stats(Broker),
    ?assertEqual(lists:seq(0, 255) ++ [0], [Tx || {_, {16#11, Tx, 0}, _} <- Events]),
    ?assertMatch(#{pending := 0, queued := 0}, hls_fabric:client_info(Debug))
end) end}.

endpoint_admission_retry_test_() -> {timeout, 30, fun() -> with_node(fun(Ctx) ->
    #{actors := Actors, app := App, debug := Debug} = Ctx,
    A = maps:get({family, cells, [0, 0]}, Actors),
    B = maps:get({family, cells, [1, 0]}, Actors),
    Other = maps:get({family, cells, [0, 1]}, Actors),
    ok = hls_actor_broker_fixture:reject(App, 7, true),
    [gen_server:cast(Pid, {work, V}) || {Pid, V} <- [{A, 1}, {B, 2}, {A, 3}, {B, 4}]],
    await(fun() -> maps:get(rejected, hls_actor_broker_fixture:stats(App)) >= 2 end),
    gen_server:cast(Other, {work, 70}),
    ?assertEqual({ok, <<71:32/little>>}, hls_debug:query(Debug, 16#11, <<71:32/little>>, 5000)),
    await(fun() -> casts(App) =:= [{8, 0, 70}] end),
    ok = hls_actor_broker_fixture:reject(App, 7, false),
    await(fun() -> length(casts(App)) =:= 5 end),
    ?assertEqual([{8, 0, 70}, {7, 0, 1}, {7, 1, 2}, {7, 0, 3}, {7, 1, 4}], casts(App))
end) end}.

remote_sender_test_() -> {timeout, 30, fun() -> with_node(fun(Ctx) ->
    #{node := Node, actors := Actors, app := App, register := Register} = Ctx,
    A = maps:get({family, cells, [0, 0]}, Actors),
    {Peer, Remote} = hls_test_nodes:start_peer(),
    try
        ?assertEqual(ok, erpc:call(Remote, gen_server, cast, [A, {work, 81}])),
        ?assertEqual({error, unsupported_call}, erpc:call(Remote, gen_server, call, [A, read])),
        ?assertEqual(82, erpc:call(Remote, regsvc, ping, [Register, 82])),
        await(fun() -> casts(App) =:= [{7, 0, 81}] end),
        #{connections := Connections} = hls_node:info(Node),
        ?assertMatch([#{carrier := tcp}], [C || C = #{peer := P} <- maps:values(Connections), P =:= Remote]),
        ?assertEqual(83, regsvc:ping(Register, 83)),
        gen_server:cast(A, {work, 84}),
        await(fun() -> length(casts(App)) =:= 2 end),
        ?assertEqual([{7, 0, 81}, {7, 0, 84}], casts(App))
    after peer:stop(Peer) end
end) end}.

reconnect_and_incarnation_test_() -> {timeout, 30, fun() -> with_node(fun(Ctx) ->
    #{node := Node, name := Name, actors := Actors, debug := Debug, debug_broker := DB,
        app := App, brokers := Brokers, services := Services} = Ctx,
    A = maps:get({family, cells, [0, 0]}, Actors),
    ?assertEqual({error, unsupported_call}, gen_server:call(A, read)),
    ok = hls_actor_broker_fixture:hold(DB),
    OldRequest = gen_server:send_request(Debug, {query, 16#11, <<91:32/little>>}),
    await(fun() -> maps:get(held, hls_actor_broker_fixture:stats(DB)) =:= 1 end),
    #{connections := Before, creation := Creation} = hls_node:info(Node),
    [#{source := OldSource}] = maps:values(Before),
    Ref = monitor(process, A),
    true = erlang:disconnect_node(Name),
    receive {'DOWN', Ref, process, A, noconnection} -> ok after 5000 -> error(no_disconnect) end,
    ?assertMatch({error, _}, gen_server:receive_response(OldRequest, 5000)),
    await(fun() -> maps:get(connections, hls_node:info(Node)) =:= #{} end),
    NewRequest = gen_server:send_request(Debug, {query, 16#11, <<92:32/little>>}),
    await(fun() -> maps:get(held, hls_actor_broker_fixture:stats(DB)) =:= 2 end),
    [#{source := NewSource}] = maps:values(maps:get(connections, hls_node:info(Node))),
    ?assert(NewSource > OldSource),
    ?assertEqual(Actors, maps:get(actors, maps:get(workers, hls_node:services(Node)))),
    ok = hls_actor_broker_fixture:release(DB),
    ?assertEqual({reply, {ok, <<92:32/little>>}}, gen_server:receive_response(NewRequest, 5000)),
    ?assertMatch(#{discarded := 1}, hls_actor_broker_fixture:stats(DB)),
    gen_server:cast(A, {work, 93}),
    await(fun() -> casts(App) =:= [{7, 0, 93}] end),
    ok = hls_node:stop(Node),
    {ok, Replacement} = hls_node:start_link(Name, Brokers, Services, #{}),
    unlink(Replacement),
    try
        ?assertNotEqual(Creation, maps:get(creation, hls_node:info(Replacement))),
        #{workers := #{actors := NextActors}} = hls_node:services(Replacement),
        NextA = maps:get({family, cells, [0, 0]}, NextActors),
        ?assertNotEqual(A, NextA),
        ?assertEqual({error, unsupported_call}, gen_server:call(NextA, read)),
        OldRef = monitor(process, A),
        receive {'DOWN', OldRef, process, A, noproc} -> ok after 5000 -> error(stale_actor_alive) end,
        gen_server:cast(A, {work, 94}),
        gen_server:cast(NextA, {work, 95}),
        await(fun() -> length(casts(App)) =:= 2 end),
        ?assertEqual([{7, 0, 93}, {7, 0, 95}], casts(App))
    after hls_node:stop(Replacement) end
end) end}.

with_node(Fun) ->
    hls_test_nodes:distribution(),
    {ok, _} = application:ensure_all_started(crypto),
    {Plan, Specs, Endpoints} = hls_actor_pid_dslx:fixture(),
    Deployment = hls_node_topology:normalize(Plan, Specs, Endpoints),
    {ok, App} = hls_actor_broker_fixture:start(application),
    {ok, DebugBroker} = hls_actor_broker_fixture:start(debug),
    Brokers = #{application => App, debug => DebugBroker},
    Name = name(),
    Services = [#{name => registers, module => regsvc, endpoint => 1},
        #{name => workers, topology => Deployment, debug_endpoint => 2}],
    {ok, Node} = hls_node:start_link(Name, Brokers, Services, #{}),
    unlink(Node),
    #{workers := #{actors := Actors, debug := Debug}, registers := #{application := Register}} = hls_node:services(Node),
    try Fun(#{node => Node, name => Name, actors => Actors, debug => Debug,
        register => Register, app => App, debug_broker => DebugBroker,
        brokers => Brokers, services => Services})
    after catch hls_node:stop(Node), hls_actor_broker_fixture:stop(App), hls_actor_broker_fixture:stop(DebugBroker) end.

name() ->
    [_LocalName, Host] = string:split(atom_to_list(node()), "@"),
    list_to_atom("actor_fpga_" ++ integer_to_list(erlang:unique_integer([positive])) ++ "@" ++ Host).

casts(App) ->
    #{events := Events} = hls_actor_broker_fixture:stats(App),
    [{Endpoint, Slot, Value} || {{_, Endpoint}, {_, 255, 1}, <<Slot:32/little, Value:32/little>>} <- Events].

await(Fun) -> await(Fun, erlang:monotonic_time(millisecond) + 5000).
await(Fun, Deadline) ->
    case Fun() of
        true -> ok;
        false ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            timer:sleep(5), await(Fun, Deadline)
    end.
