-module(hls_actor_pid_live).
-export([run/1, cast_many/2]).

%% Every observation uses the production debug transport. reports.log contains
%% accepted frames at the public topology output, recorded by the testbench.
-doc "Exercises stalled RTL through the host debug transport and checks recovery.".
-spec run(atom() | binary() | [atom() | [any()] | char()]) -> 'ok'.
run(Stage) ->
    hls_test_nodes:distribution(),
    {ok, _} = application:ensure_all_started(crypto),
    {Plan, Specs, Endpoints} = hls_actor_pid_dslx:fixture(),
    Deployment = hls_node_topology:normalize(Plan, Specs, Endpoints),
    {ok, App} = hls_fabric:start_link(filename:join(Stage, "app_tx"), filename:join(Stage, "app_rx")),
    {ok, Debug} = hls_fabric:start_link(filename:join(Stage, "debug_tx"), filename:join(Stage, "debug_rx")),
    Brokers = #{application => App, debug => Debug},
    [_Own, Host] = string:split(atom_to_list(node()), "@"),
    Name = list_to_atom("actor_fixture_" ++ filename:basename(Stage) ++ "@" ++ Host),
    {ok, Device} = hls_node:start_link(Name, Brokers,
        [#{name => workers, topology => Deployment, debug_endpoint => 2}], #{tick_ms => 1000}),
    unlink(Device),
    try
        #{workers := #{actors := Pids, debug := D}} = hls_node:services(Device),
        4 = map_size(Pids),
        true = lists:all(fun(P) -> node(P) =:= Name end, maps:values(Pids)),
        {ok, Bytes} = file:read_file(filename:join(Stage, "manifest.json")),
        Manifest = json:decode(Bytes),
        {ok, Catalog} = hls_node_topology:bind_debug(Plan, Specs, D, Manifest),
        {ok, Session} = hls_shared_observation:open(D, Manifest),
        Ids = hls_debug_catalog:actors(Catalog),
        [await_phase(Catalog, Id, ready) || Id <- Ids],
        Initial = observations(Catalog),
        [{First, _} | _] = Pairs = lists:zip(Ids, [101, 202, 303, 404]),
        ok = gen_server:cast(maps:get(First, Pids), {work, 101}),
        await_phase(Catalog, First, odd),
        %% The first actor's state transition must not affect its slot neighbor
        %% or the same local slot in the other interleaved scheduler.
        [ready = phase(Catalog, Id) || Id <- Ids, Id =/= First],
        [begin
            ok = gen_server:cast(maps:get(Id, Pids), {work, Value}),
            await_phase(Catalog, Id, odd)
        end || {Id, Value} <- tl(Pairs)],
        await(fun() -> filelib:is_file(filename:join(Stage, "app_held")) end),
        Burst = lists:seq(1001, 1032),
        Prefix = [101, 202, 303, 404] ++ Burst,
        {ProducerPeer, _ProducerNode} = hls_test_nodes:start_peer(),
        {Blocked, Waits} = try
            %% Application traffic and inspection deliberately use separate
            %% distribution connections: a paused stream can otherwise hold
            %% later debug requests behind the application messages.
            ok = peer:call(ProducerPeer, ?MODULE, cast_many, [maps:get(First, Pids), Burst]),
            {ok, FirstActor} = hls_debug_catalog:actor(Catalog, First),
            %% Backpressure can retain work in the pipeline before retirement
            %% exposes an egress wait. Diagnose the sink through inspect_waits
            %% below instead of requiring one implementation's holding point.
            await(fun() ->
                case hls_debug:info(FirstActor,
                        [message_queue_len, free_slots, waiting_for_egress, in_flight], 10000) of
                    [{message_queue_len, 2}, {free_slots, 0},
                            {waiting_for_egress, Waiting}, {in_flight, InFlight}] ->
                        Waiting orelse InFlight;
                    _ -> false
                end
            end),
            Blocked0 = observations(Catalog),
            %% Previously accepted work in the other scheduler remains visible
            %% while the producer's actor has a full mailbox and blocked effect.
            [odd = phase(Catalog, Id) || Id <- Ids, Id =/= First],
            Seeds = blocked_outputs(Session, Manifest),
            true = Seeds =/= [],
            {ok, Waits0} = hls_topology_debug:inspect_waits(Session, Seeds, #{max_queries => 256}),
            true = lists:any(fun(#{kind := Kind}) -> Kind =:= external_sink end, maps:get(edges, Waits0)),
            ok = file:write_file(filename:join(Stage, "release_app"), <<>>),
            await_reports(Stage, Prefix),
            Burst = [V || V <- reports(Stage), V >= 1000],
            await_phase(Catalog, First, odd),
            {Blocked0, Waits0}
        after peer:stop(ProducerPeer) end,
        ok = gen_server:cast(maps:get(First, Pids), {work, 505}),
        await_phase(Catalog, First, even),
        await_reports(Stage, Prefix ++ [505]),
        malformed_casts(App),
        ok = gen_server:cast(maps:get(First, Pids), {work, 606}),
        await_phase(Catalog, First, odd),
        await_reports(Stage, Prefix ++ [505, 606]),
        [odd = phase(Catalog, Id) || Id <- Ids, Id =/= First],
        {Peer, _Remote} = hls_test_nodes:start_peer(),
        Last = lists:last(Ids),
        try
            ok = peer:call(Peer, gen_server, cast, [maps:get(Last, Pids), {work, 707}]),
            await_phase(Catalog, Last, even),
            await_reports(Stage, Prefix ++ [505, 606, 707])
        after peer:stop(Peer) end,
        FirstPid = maps:get(First, Pids),
        Ref = monitor(process, FirstPid),
        %% Distribution disconnect does not restart scheduler state or change
        %% the node incarnation's PIDs. Reacquire the debug session afterward.
        true = erlang:disconnect_node(Name),
        receive {'DOWN', Ref, process, FirstPid, noconnection} -> ok
        after 5000 -> error(no_noconnection) end,
        pong = net_adm:ping(Name),
        {ok, Reconnected} = hls_node_topology:bind_debug(Plan, Specs, D, Manifest),
        odd = phase(Reconnected, First),
        #{workers := #{actors := Pids}} = hls_node:services(Device),
        ok = gen_server:cast(FirstPid, {work, 808}),
        await_phase(Reconnected, First, even),
        await_reports(Stage, Prefix ++ [505, 606, 707, 808]),
        save(Stage, #{initial => Initial, blocked => Blocked, waits => Waits,
            recovered => observations(Reconnected), reports => reports(Stage)}),
        ok = hls_node:stop(Device),
        Leases = [begin #{io := #{lease := Lease}} = hls_fabric:info(B), Lease end
            || B <- maps:values(Brokers)],
        [ok = hls_fabric:stop(B) || B <- maps:values(Brokers)],
        ok = file:write_file(filename:join(Stage, "done"), <<>>),
        [ok = hls_fabric:await_closed(Lease, 5000) || Lease <- Leases],
        io:format("PASS: four actor PIDs, interleaved scheduler slots, cast isolation, public stall diagnosis, remote peer and reconnect against generated RTL~n")
    after
        catch hls_node:stop(Device),
        [catch hls_fabric:stop(B) || B <- maps:values(Brokers)]
    end.

cast_many(Pid, Values) ->
    [ok = gen_server:cast(Pid, {work, Value}) || Value <- Values],
    ok.

phase(Catalog, Id) ->
    {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
    {phase, Phase} = hls_debug:info(Actor, phase, 10000),
    Phase.

await_phase(Catalog, Id, Expected) -> await(fun() -> phase(Catalog, Id) =:= Expected end).

observations(Catalog) ->
    maps:from_list([begin
        {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
        {Id, hls_debug:info(Actor, [identity, placement, phase, failure,
            message_queue_len, postponed, free_slots, in_flight, waiting_for_egress, cycle], 10000)}
    end || Id <- hls_debug_catalog:actors(Catalog)]).

blocked_outputs(Session, #{<<"probes">> := Probes}) ->
    [Id || #{<<"id">> := Id, <<"endpoints">> := Endpoints} <- Probes,
        lists:any(fun(E) -> maps:get(<<"external">>, E, false) andalso
            maps:get(<<"role">>, E) =:= <<"consumer">> end, Endpoints),
        {ok, #{value := 1}} <- [hls_topology_debug:query(Session, Id)]].

malformed_casts(App) ->
    ok = hls_fabric:register_route(App, {7, 60000}, self()),
    ok = hls_fabric:register_route(App, {99, 60000}, self()),
    Tag = hls_actor_pid_fixture:pack_tag(work),
    [begin
        Req = hls_fabric:send_request(App, {60000, Endpoint}, Header, Payload, infinity),
        {reply, ok} = gen_server:receive_response(Req, 10000)
    end || {Endpoint, Header, Payload} <- [
        {7, {Tag, 255, 1}, <<99:32/little, 999:32/little>>},
        {7, {Tag, 255, 0}, <<0:32/little, 998:32/little>>},
        {7, {Tag, 0, 1}, <<0:32/little, 997:32/little>>},
        {7, {0, 255, 1}, <<0:32/little, 996:32/little>>},
        {99, {Tag, 255, 1}, <<0:32/little, 995:32/little>>},
        {7, {Tag, 255, 1}, <<0:32/little>>},
        {7, {Tag, 255, 1}, <<0:32/little, 994:32/little, 0:32/little>>},
        {7, {Tag, 255, 1}, <<>>}]],
    ok.

await_reports(Stage, Expected) ->
    Sorted = lists:sort(Expected),
    await(fun() ->
        Values = reports(Stage),
        case length(Values) > length(Expected) of
            true -> error({extra_reports, Values, Expected});
            false -> lists:sort(Values) =:= Sorted
        end
    end).

reports(Stage) ->
    case file:read_file(filename:join(Stage, "reports.log")) of
        {ok, Bytes} ->
            [begin
                Raw = binary_to_integer(Line, 16),
                Tag = hls_actor_pid_fixture:pack_tag(report),
                Header = Raw bsr 96,
                Tag = Header band 255,
                1 = Header bsr 24,
                0 = (Header bsr 8) band 65535,
                Raw band ((1 bsl 96) - 1)
            end || Line <- binary:split(Bytes, <<"\n">>, [global]), Line =/= <<>>];
        {error, enoent} -> []
    end.

await(Fun) -> await(Fun, erlang:monotonic_time(millisecond) + 15000).
await(Fun, Deadline) ->
    case Fun() of
        true -> ok;
        false ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> timer:sleep(5), await(Fun, Deadline);
                false -> error({condition_timeout, Fun})
            end
    end.

save(Stage, Term) ->
    file:write_file(filename:join(Stage, "observations.term"), io_lib:format("~p.~n", [Term])).
