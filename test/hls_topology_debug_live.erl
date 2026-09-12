-module(hls_topology_debug_live).
-export([run/1]).

%% Integration runner used by tools/test_topology_debug_integration.py. The
%% application is held at an external sink, then released through a test-only
%% file control. All observations travel through the production debug client.
run(Stage) ->
    {ok, Bytes} = file:read_file(filename:join(Stage, "manifest.json")),
    Manifest = json:decode(Bytes),
    {ok, Fabric} = hls_fabric:start_link(filename:join(Stage, "debug_tx"), filename:join(Stage, "debug_rx")),
    {ok, Client} = hls_debug:start_link(undefined, {fabric, Fabric, 2}),
    try
        {ok, Session} = hls_topology_debug:open(Client, Manifest),
        {error, topology_manifest_mismatch} = hls_topology_debug:open(Client,
            Manifest#{<<"fingerprint">> := <<"wrong build">>}),
        %% Discovery scan chooses genuinely full hardware queues. The follow-up
        %% inspection itself is adaptive and must reach the injected external sink.
        Queues = [Q || Q = #{<<"kind">> := <<"fifo">>} <- maps:get(<<"resources">>, Manifest)],
        Seeds = [Id || #{<<"id">> := Id, <<"capacity">> := Capacity} <- Queues,
            begin {ok, #{value := Occupancy}} = hls_topology_debug:query(Session, Id), Occupancy =:= Capacity end],
        true = Seeds =/= [],
        {ok, Report} = hls_topology_debug:inspect_waits(Session, Seeds, #{max_queries => 2048}),
        true = lists:any(fun(#{kind := K, channel := Id}) ->
            K =:= external_sink andalso lists:member(Id, maps:get(reobserved_blocked, Report))
        end, maps:get(edges, Report)),
        ok = file:write_file(filename:join(Stage, "blocked.json"), json:encode(Report)),
        ok = file:write_file(filename:join(Stage, "release"), <<>>),
        ok = await_release(Stage, 1000),
        {ok, Recovered} = hls_topology_debug:inspect_waits(Session, Seeds, #{max_queries => 2048}),
        ok = file:write_file(filename:join(Stage, "recovered.json"), json:encode(Recovered)),
        false = lists:any(fun(#{kind := K, channel := Id}) ->
            K =:= external_sink andalso lists:member(Id, maps:get(reobserved_blocked, Recovered))
        end, maps:get(edges, Recovered)),
        io:format("PASS: ~p full FIFO seeds, ~p adaptive queries; external stall found and release observed~n",
            [length(Seeds), length(maps:get(observations, Report))]),
        ok
    after
        hls_debug:stop(Client),
        hls_fabric:stop(Fabric)
    end,
    file:write_file(filename:join(Stage, "done"), <<>>).

await_release(_Stage, 0) -> error(sink_release_timeout);
await_release(Stage, Attempts) ->
    case file:read_file(filename:join(Stage, "released")) of
        {ok, _} -> ok;
        {error, enoent} -> timer:sleep(1), await_release(Stage, Attempts-1)
    end.
