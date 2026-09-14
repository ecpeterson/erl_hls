-module(hls_fabric_backpressure_tests).
-include_lib("eunit/include/eunit.hrl").

queued_expiry_and_quotas_test() ->
    with_peer(filled, #{tx_limit => 3, tx_route_limit => 2}, fun(Fabric, Peer, Filled) ->
        A = send(Fabric, 1, 11, 2000),
        await(Fabric, fun(#{tx := #{active := Active}}) -> Active =/= none end),
        B = send(Fabric, 1, 22, 50),
        RejectedRoute = send(Fabric, 1, 99, 2000),
        ?assertEqual({reply, {error, {not_sent, {route_tx_limit, {0, 1}}}}}, response(RejectedRoute)),
        C = send(Fabric, 2, 33, 2000),
        RejectedGlobal = send(Fabric, 3, 99, 2000),
        ?assertEqual({reply, {error, {not_sent, tx_limit}}}, response(RejectedGlobal)),
        ?assertEqual({reply, {error, {not_sent, timeout}}}, response(B)),
        ?assertMatch(#{tx := #{queued := 1}}, hls_fabric:info(Fabric)),
        D = send(Fabric, 1, 44, 2000),
        ?assertEqual(<<"ok">>, peer(Peer, ["discard ", integer_to_list(Filled)])),
        [?assertEqual({reply, ok}, response(Request)) || Request <- [A, C, D]],
        ?assertEqual(iolist_to_binary([frame(1, 11), frame(2, 33), frame(1, 44)]), take(Peer, 36)),
        ?assertMatch(#{tx := #{queued := 0, active := none},
            counts := #{written := 3, expired := 1, rejected := 2}}, hls_fabric:info(Fabric))
    end).

active_write_timeout_closes_transport_test() ->
    with_peer(filled, #{}, fun(Fabric, Peer, Filled) ->
        BrokerMonitor = monitor(process, Fabric),
        A = send(Fabric, 1, 11, 50),
        B = send(Fabric, 2, 22, infinity),
        ?assertEqual({reply, {error, {write_timeout, {0, 1}}}}, response(A)),
        ?assertEqual({reply, {error, {not_sent, {transport_down, {write_timeout, {0, 1}}}}}}, response(B)),
        receive {'DOWN', BrokerMonitor, process, Fabric, {write_timeout, {0, 1}}} -> ok
        after 1000 -> error(broker_stayed_alive) end,
        %% An already executing OS write may finish after the broker dies.
        %% The queued frame must never be appended behind it.
        peer(Peer, ["discard ", integer_to_list(Filled)]),
        Bytes = binary:decode_hex(peer(Peer, "drain")),
        ?assert(Bytes =:= <<>> orelse Bytes =:= frame(1, 11))
    end).

blocked_open_keeps_admission_and_stop_responsive_test() ->
    with_peer(closed, #{}, fun(Fabric, Peer, _Filled) ->
        A = send(Fabric, 1, 11, 30),
        ?assertEqual({reply, {error, {not_sent, timeout}}}, response(A)),
        ?assertMatch(#{tx := #{writer_ready := false, queued := 0, active := none}},
            hls_fabric:info(Fabric)),
        ok = hls_fabric:stop(Fabric),
        %% Release an OS open that may still be unwinding in the killed worker.
        ?assertEqual(<<"ok">>, peer(Peer, "open")),
        ?assertEqual(<<>>, binary:decode_hex(peer(Peer, "drain")))
    end).

owner_death_removes_only_unwritten_commands_test() ->
    with_peer(filled, #{}, fun(Fabric, Peer, Filled) ->
        A = send(Fabric, 1, 11, 2000),
        Parent = self(),
        Owner = spawn(fun() ->
            ok = hls_fabric:register_route(Fabric, {2, 0}, self()),
            send(Fabric, 2, 22, infinity),
            Parent ! submitted,
            receive stop -> ok end
        end),
        receive submitted -> ok after 1000 -> error(no_submission) end,
        await(Fabric, fun(#{tx := #{queued := N}}) -> N =:= 1 end),
        exit(Owner, kill),
        await(Fabric, fun(#{tx := #{queued := N}, routes := Routes}) ->
            N =:= 0 andalso maps:get({2, 0}, Routes) =:= retired
        end),
        C = send(Fabric, 3, 33, 2000),
        peer(Peer, ["discard ", integer_to_list(Filled)]),
        [?assertEqual({reply, ok}, response(Request)) || Request <- [A, C]],
        ?assertEqual(<< (frame(1, 11))/binary, (frame(3, 33))/binary >>, take(Peer, 24))
    end).

receive_receipts_bound_slow_owners_test() ->
    with_peer(empty, #{rx_limit => 3, rx_route_limit => 1}, fun(Fabric, Peer, _Filled) ->
        ok = hls_fabric:register_route(Fabric, {1, 0}, self()),
        ok = hls_fabric:register_route(Fabric, {2, 0}, self()),
        emit(Peer, [reply_frame(1, 11), reply_frame(1, 22), reply_frame(2, 33)]),
        {First, {1, 0}, _, <<11:32/little>>} = event(),
        await(Fabric, fun(#{rx := #{outstanding := N, buffered := R}}) -> N =:= 1 andalso R =:= {1, 0} end),
        receive {'$gen_cast', _} -> error(delivered_without_credit) after 0 -> ok end,
        Parent = self(),
        spawn(fun() -> hls_fabric:ack(Fabric, First), Parent ! wrong_ack end),
        receive wrong_ack -> ok end,
        await(Fabric, fun(#{counts := #{ignored_acks := N}}) -> N =:= 1 end),
        ?assertMatch(#{rx := #{outstanding := 1, buffered := {1, 0}}}, hls_fabric:info(Fabric)),
        hls_fabric:ack(Fabric, First),
        {Second, {1, 0}, _, <<22:32/little>>} = event(),
        {Third, {2, 0}, _, <<33:32/little>>} = event(),
        hls_fabric:ack(Fabric, First), % duplicate must not release a new receipt
        ?assertMatch(#{rx := #{outstanding := 2}, counts := #{ignored_acks := 2}}, hls_fabric:info(Fabric)),
        hls_fabric:ack(Fabric, Second),
        hls_fabric:ack(Fabric, Third),
        ?assertMatch(#{rx := #{outstanding := 0}}, hls_fabric:info(Fabric))
    end).

receive_global_credit_and_owner_death_test() ->
    with_peer(empty, #{rx_limit => 1}, fun(Fabric, Peer, _Filled) ->
        Owner = spawn(fun() -> receive stop -> ok end end),
        ok = hls_fabric:register_route(Fabric, {1, 0}, Owner),
        ok = hls_fabric:register_route(Fabric, {2, 0}, self()),
        emit(Peer, [reply_frame(1, 11), reply_frame(1, 22), reply_frame(2, 33)]),
        await(Fabric, fun(#{rx := #{outstanding := N, reading := Reading}}) -> N =:= 1 andalso not Reading end),
        ?assertEqual({message_queue_len, 1}, process_info(Owner, message_queue_len)),
        exit(Owner, kill),
        {Receipt, {2, 0}, _, <<33:32/little>>} = event(),
        ?assertMatch(#{routes := #{{1, 0} := retired}, counts := #{discarded := 1}}, hls_fabric:info(Fabric)),
        hls_fabric:ack(Fabric, Receipt)
    end).

proxy_processes_replies_during_write_stall_test() ->
    with_peer(empty, #{tx_limit => 1}, fun(Fabric, Peer, _Filled) ->
        {ok, Client} = hls_debug:start_link(undefined, {fabric, Fabric, 1}),
        try
            First = gen_server:send_request(Client, {query, 1, <<11:32/little>>}),
            ?assertEqual(frame(1, 11), take(Peer, 12)),
            Filled = binary_to_integer(peer(Peer, "fill")),
            Second = gen_server:send_request(Client, {query, 1, <<22:32/little>>}),
            await(Fabric, fun(#{tx := #{active := Active}}) -> Active =/= none end),
            ?assertMatch(#{status := up, pending := 2}, hls_fabric:client_info(Client)),
            Rejected = gen_server:send_request(Client, {query, 1, <<99:32/little>>}),
            ?assertEqual({reply, {error, {not_sent, tx_limit}}}, response(Rejected)),
            emit(Peer, reply_frame(1, 11)),
            ?assertEqual({reply, {ok, <<11:32/little>>}}, response(First)),
            ?assertMatch(#{status := up, pending := 1, transmitting := 1, rejected_requests := 1},
                hls_fabric:client_info(Client)),
            peer(Peer, ["discard ", integer_to_list(Filled)]),
            ?assertEqual(frame({0, 1}, {1, 1, 0}, <<22:32/little>>), take(Peer, 12)),
            emit(Peer, frame({1, 0}, {129, 1, 0}, <<22:32/little>>)),
            ?assertEqual({reply, {ok, <<22:32/little>>}}, response(Second)),
            ?assertMatch(#{status := up, pending := 0}, hls_fabric:client_info(Client))
        after hls_debug:stop(Client) end
    end).

runner_initial_write_does_not_hide_deadline_test() ->
    with_peer(filled, #{}, fun(Fabric, _Peer, _Filled) ->
        Options = #{distance => 1, first_quiet_step => 0, line_y => 0,
            measurement => z, request_id => 7},
        {ok, Runner} = phi_memory_runner:start_link(Fabric, Options, 30),
        try ?assertEqual({error, timeout}, phi_memory_runner:await(Runner))
        after phi_memory_runner:stop(Runner) end
    end).

send(Fabric, Endpoint, Value, Timeout) ->
    hls_fabric:send_request(Fabric, {0, Endpoint}, {1, 0, 0}, <<Value:32/little>>, Timeout).
response(Request) -> gen_server:receive_response(Request, 1000).
frame(Endpoint, Value) -> frame({0, Endpoint}, {1, 0, 0}, <<Value:32/little>>).
reply_frame(Endpoint, Value) -> frame({Endpoint, 0}, {129, 0, 0}, <<Value:32/little>>).
frame({Source, Destination}, {Tag, TxID, Flags}, Payload) ->
    <<Destination:16/little, Source:16/little, (byte_size(Payload) div 4):8,
        TxID:8, Flags:8, Tag:8, Payload/binary>>.
event() ->
    receive {'$gen_cast', {'$hls_fabric_frame', Receipt, Route, Header, Payload}} ->
        {Receipt, Route, Header, Payload}
    after 1000 -> error(no_frame) end.
emit(Peer, Bytes) -> ?assertEqual(<<"ok">>, peer(Peer, ["emit ", binary:encode_hex(iolist_to_binary(Bytes))])).
take(Peer, Bytes) -> binary:decode_hex(peer(Peer, ["take ", integer_to_list(Bytes)])).

await(Fabric, Predicate) -> await(Fabric, Predicate, 1000).
await(Fabric, _Predicate, 0) -> error({condition_timeout, hls_fabric:info(Fabric)});
await(Fabric, Predicate, Tries) ->
    Info = hls_fabric:info(Fabric),
    case Predicate(Info) of
        true -> Info;
        false -> receive after 1 -> ok end, await(Fabric, Predicate, Tries - 1)
    end.

with_peer(Mode, Options, Run) ->
    Root = filename:absname(filename:join(["_build", "fabric-pressure-tests",
        integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
            integer_to_list(erlang:unique_integer([positive]))])),
    Tx = filename:join(Root, "tx"),
    Rx = filename:join(Root, "rx"),
    ok = filelib:ensure_dir(Tx),
    Mkfifo = open_port({spawn_executable, os:find_executable("mkfifo")}, [{args, [Tx, Rx]}, exit_status]),
    receive {Mkfifo, {exit_status, 0}} -> ok after 1000 -> error(mkfifo_failed) end,
    Args = [filename:absname("test/fabric_peer.py"), Tx, Rx] ++ case Mode of closed -> ["defer"]; _ -> [] end,
    Peer = open_port({spawn_executable, os:find_executable("python3")},
        [{args, Args}, binary, {line, 65536}, exit_status, stderr_to_stdout]),
    ?assertEqual(<<"ready">>, peer_reply(Peer)),
    Filled = case Mode of filled -> binary_to_integer(peer(Peer, "fill")); _ -> 0 end,
    {ok, Fabric} = hls_fabric:start_link(Tx, Rx, Options),
    unlink(Fabric),
    try Run(Fabric, Peer, Filled)
    after
        Monitor = monitor(process, Fabric),
        catch hls_fabric:stop(Fabric),
        receive {'DOWN', Monitor, process, Fabric, _} -> ok
        after 1000 -> error(broker_cleanup_timeout) end,
        catch port_close(Peer),
        file:del_dir_r(Root)
    end.

peer(Peer, Command) -> port_command(Peer, [Command, "\n"]), peer_reply(Peer).
peer_reply(Peer) ->
    receive
        {Peer, {data, {eol, Line}}} -> Line;
        {Peer, {exit_status, Status}} -> error({peer_exit, Status})
    after 4000 -> error(peer_timeout) end.
