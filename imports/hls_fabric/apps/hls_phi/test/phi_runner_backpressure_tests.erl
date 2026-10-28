-module(phi_runner_backpressure_tests).
-moduledoc "The Phi coordinator deadline includes its first blocked transport write.".
-include_lib("eunit/include/eunit.hrl").

%% The runner and its write share an absolute deadline. Either timer, or the
%% resulting broker DOWN, can arrive first; all must terminate a blocked start.
-spec runner_initial_write_does_not_hide_deadline_test() -> ok.
runner_initial_write_does_not_hide_deadline_test() ->
    with_peer(filled, #{}, fun(Fabric, _Peer, _Filled) ->
        Options = #{distance => 1, first_quiet_step => 0, line_y => 0,
            measurement => z, request_id => 7},
        {ok, Runner} = phi_memory_runner:start_link(Fabric, Options, 30),
        try
            Request = gen_server:send_request(Runner, await),
            %% response/1 bounds this wait to one second even if both deadline
            %% paths regress; unrelated failures and an absent reply still fail.
            ?assert(lists:member(response(Request), [
                {reply, {error, timeout}},
                {reply, {error, {send, {not_sent, timeout}}}},
                {reply, {error, {send, {write_timeout, {0, 1}}}}},
                {reply, {error, {fabric_down, {write_timeout, {0, 1}}}}}
            ]))
        after phi_memory_runner:stop(Runner) end
    end).

%% Bounds each asynchronous response independently of the runner deadline.
-spec response(gen_server:request_id()) -> gen_server:response(term()).
response(Request) -> gen_server:receive_response(Request, 1000).

%% Runs the witness against a controlled bounded FIFO transport.
-spec with_peer(filled, map(), fun((pid(), port(), non_neg_integer()) -> ok)) -> ok.
with_peer(Mode, Options, Run) ->
    with_peer_paths(Mode, Options, fun(Fabric, Peer, Filled, _Tx, _Rx) ->
        Run(Fabric, Peer, Filled)
    end).

%% Owns the FIFOs, peer process, broker and their verified descriptor cleanup.
-spec with_peer_paths(filled, map(), fun((pid(), port(), non_neg_integer(), file:filename(), file:filename()) -> ok)) -> ok.
with_peer_paths(Mode, Options, Run) ->
    Root = filename:absname(filename:join(["_build", "fabric-pressure-tests",
        integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
            integer_to_list(erlang:unique_integer([positive]))])),
    Tx = filename:join(Root, "tx"),
    Rx = filename:join(Root, "rx"),
    ok = filelib:ensure_dir(Tx),
    Mkfifo = open_port({spawn_executable, os:find_executable("mkfifo")}, [{args, [Tx, Rx]}, exit_status]),
    receive {Mkfifo, {exit_status, 0}} -> ok after 1000 -> error(mkfifo_failed) end,
    Args = [filename:absname("apps/hls_phi/test/fabric_peer.py"), Tx, Rx] ++ case Mode of closed -> ["defer"]; _ -> [] end,
    Peer = open_port({spawn_executable, os:find_executable("python3")},
        [{args, Args}, binary, {line, 65536}, exit_status, stderr_to_stdout]),
    ?assertEqual(<<"ready">>, peer_reply(Peer)),
    Filled = case Mode of filled -> binary_to_integer(peer(Peer, "fill")); _ -> 0 end,
    {ok, Fabric} = hls_fabric:start_link(Tx, Rx, Options),
    unlink(Fabric),
    #{io := #{lease := Lease}} = hls_fabric:info(Fabric),
    try Run(Fabric, Peer, Filled, Tx, Rx)
    after
        Monitor = monitor(process, Fabric),
        catch hls_fabric:stop(Fabric),
        receive {'DOWN', Monitor, process, Fabric, _} -> ok
        after 1000 -> error(broker_cleanup_timeout) end,
        catch port_close(Peer),
        case hls_fabric:await_closed(Lease, 1000) of
            ok -> file:del_dir_r(Root);
            {error, _} -> ok % retain quarantined paths until this VM exits
        end
    end.

%% Exchanges one line with the fixture peer.
-spec peer(port(), iodata()) -> binary().
peer(Peer, Command) -> port_command(Peer, [Command, "\n"]), peer_reply(Peer).
%% Reads one bounded peer response, rejecting crashes and missing responses.
-spec peer_reply(port()) -> binary().
peer_reply(Peer) ->
    receive
        {Peer, {data, {eol, Line}}} -> Line;
        {Peer, {exit_status, Status}} -> error({peer_exit, Status})
    after 4000 -> error(peer_timeout) end.
