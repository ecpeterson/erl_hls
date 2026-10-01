-module(hls_device_rtl).
-export([run/2]).

run(StageA, StageB) ->
    hls_test_nodes:distribution(),
    application:ensure_all_started(crypto),
    {DeviceA, BrokersA} = attach(StageA),
    #{application := BrokerA} = BrokersA,
    {DeviceB, BrokersB} = attach(StageB),
    {Peer, _PeerNode} = hls_test_nodes:start_peer(),
    try
        #{registers := #{application := A, debug := DA}} = hls_node:services(DeviceA),
        #{registers := #{application := B, debug := DB}} = hls_node:services(DeviceB),
        true = node(A) =/= node(B), true = node(A) =/= node(),
        Held = gen_server:send_request(A, {ping, 111}),
        await_file(filename:join(StageA, "app_held")),
        %% Public debug queries diagnose the physical output stall. Both virtual
        %% nodes and all brokers live in this BEAM; the peer is another caller.
        Counters = await_stall(DA, 100),
        #{pending := 1} = hls_fabric:client_info(A),
        222 = regsvc:ping(B, 222),
        _RemoteCaller = peer:call(Peer, hls_test_nodes, request, [A, {ping, 112}, self()]),
        await_connections(DeviceA, 2),
        true = erlang:disconnect_node(node(A)),
        {error, _} = gen_server:receive_response(Held, 5000),
        await_connections(DeviceA, 1),
        Pending = gen_server:send_request(A, {ping, 333}),
        await_connections(DeviceA, 2),
        ok = file:write_file(filename:join(StageA, "release_app"), <<>>),
        receive {remote_reply, {ack, 112}} -> ok after 10000 -> error(no_concurrent_reply) end,
        {reply, {ack, 333}} = gen_server:receive_response(Pending, 10000),
        [begin
            ok = regsvc:set(Client, 1, Value, 16#ffffffff),
            [0, Value, 0] = regsvc:bulk_get(Client, 0, 3)
        end || {Client, Value} <- [{A, 1001}, {B, 2002}]],
        [begin
            Requests = [{V, gen_server:send_request(Client, {ping, V})}
                || V <- lists:seq(Round*10, Round*10+9), Client <- [A, B]],
            [{reply, {ack, V}} = gen_server:receive_response(R, 10000) || {V, R} <- Requests]
        end || Round <- lists:seq(1, 10)],
        {ok, FinalA = #{observation_drops := 0}} = hls_debug:get_counters(DA),
        {ok, FinalB = #{observation_drops := 0}} = hls_debug:get_counters(DB),
        {ok, TraceA = #{count := 64, events := EventsA, observation_drops := 0}} = hls_debug:get_trace(DA),
        {ok, TraceB = #{count := 64, events := EventsB, observation_drops := 0}} = hls_debug:get_trace(DB),
        true = EventsA =/= [], true = EventsB =/= [],
        #{pending := 0} = hls_fabric:client_info(A),
        #{counts := #{discarded := 1}} = Transport = hls_fabric:info(BrokerA),
        save(StageA, #{blocked => Counters, recovered => FinalA, trace => TraceA, transport => Transport,
            node => hls_node:info(DeviceA)}),
        save(StageB, #{recovered => FinalB, trace => TraceB, node => hls_node:info(DeviceB)}),
        %% Request physical closure before terminating the simulators; their
        %% final FIFO closure releases any blocked raw readers.
        ok = hls_node:stop(DeviceA), ok = hls_node:stop(DeviceB),
        Brokers = maps:values(BrokersA) ++ maps:values(BrokersB),
        Leases = [begin
            #{io := #{lease := Lease}} = hls_fabric:info(Broker), Lease
        end || Broker <- Brokers],
        [ok = hls_fabric:stop(Broker) || Broker <- Brokers],
        ok = file:write_file(filename:join(StageA, "done"), <<>>),
        ok = file:write_file(filename:join(StageB, "done"), <<>>),
        [ok = hls_fabric:await_closed(Lease, 5000) || Lease <- Leases],
        io:format("PASS: two virtual FPGA nodes in one BEAM; external PIDs, independent state, 200 pings, public stall diagnosis and stale-reply exclusion~n")
    after
        peer:stop(Peer), catch hls_node:stop(DeviceA), catch hls_node:stop(DeviceB)
    end.

attach(Stage) ->
    {ok, App} = hls_fabric:start_link(filename:join(Stage, "app_tx"), filename:join(Stage, "app_rx")),
    {ok, Debug} = hls_fabric:start_link(filename:join(Stage, "debug_tx"), filename:join(Stage, "debug_rx")),
    [_Own, Host] = string:split(atom_to_list(node()), "@"),
    Name = list_to_atom("fpga_" ++ filename:basename(Stage) ++ "@" ++ Host),
    {ok, Device} = hls_node:start_link(Name, #{application => App, debug => Debug},
        [#{name => registers, module => regsvc, endpoint => 2}], #{tick_ms => 1000}),
    unlink(Device),
    {Device, #{application => App, debug => Debug}}.

await_connections(Device, Count) -> await_connections(Device, Count, 500).
await_connections(_Device, _Count, 0) -> error(connection_timeout);
await_connections(Device, Count, Tries) ->
    #{connections := Connections} = hls_node:info(Device),
    case map_size(Connections) =:= Count of
        true -> ok;
        false -> timer:sleep(10), await_connections(Device, Count, Tries - 1)
    end.

await_file(Path) -> await_file(Path, 1000).
await_file(_Path, 0) -> error(no_hardware_stall);
await_file(Path, Tries) ->
    case file:read_file(Path) of
        {ok, _} -> ok;
        _ -> timer:sleep(10), await_file(Path, Tries-1)
    end.
await_stall(_Debug, 0) -> error(no_stall_counter);
await_stall(Debug, Tries) ->
    {ok, #{app_tx_stall_cycles := Cycles} = Counters} = hls_debug:get_counters(Debug),
    case Cycles > 0 of true -> Counters; false -> await_stall(Debug, Tries-1) end.
save(Stage, Term) -> file:write_file(filename:join(Stage, "observations.term"), io_lib:format("~p.~n", [Term])).
