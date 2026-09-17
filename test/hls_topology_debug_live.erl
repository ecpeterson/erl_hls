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
        ok = hls_actor_debug_live:inspect(Session, Stage, blocked),
        %% Discovery scan chooses genuinely full hardware queues. The follow-up
        %% inspection itself is adaptive and must reach the injected external sink.
        Queues = [Q || Q = #{<<"kind">> := <<"fifo">>} <- maps:get(<<"resources">>, Manifest)],
        Full = [Id || #{<<"id">> := Id, <<"capacity">> := Capacity} <- Queues,
            begin
                {ok, Target} = hls_topology_debug:resource(Session, Id),
                [{occupancy, Occupancy}, {free_slots, Free}, {cycle, _}] =
                    hls_debug:info(Target, [occupancy, free_slots, cycle], 10000),
                true = Occupancy + Free =:= Capacity,
                Occupancy =:= Capacity
            end],
        %% A single blocked frame may remain in an XLS output register without
        %% filling a FIFO. Its external ready/valid boundary is still observable.
        Seeds = case Full of
            [] -> [Id || #{<<"id">> := Id, <<"endpoints">> := Endpoints} <- maps:get(<<"probes">>, Manifest),
                lists:any(fun(E) -> maps:get(<<"external">>, E, false) andalso
                    maps:get(<<"role">>, E) =:= <<"consumer">> end, Endpoints),
                {ok, #{value := 1}} <- [hls_topology_debug:query(Session, Id)]];
            _ -> Full
        end,
        {Withheld, Direct} = case file:read_file(filename:join(Stage, "actor-test")) of
            {ok, <<"reduction">>} -> {true, false};
            {ok, <<"direct_reduction">>} -> {true, true};
            {ok, <<"aggregate">>} -> {true, false};
            _ -> {false, false}
        end,
        case Withheld of
            true ->
                %% No actor has completed yet, so there is no output stall to
                %% follow. Repeat the public inspection before releasing peers.
                ok = hls_actor_debug_live:inspect(Session, Stage, blocked);
            false ->
                {ok, FirstQueue} = hls_topology_debug:resource(Session, hd(Seeds)),
                {ok, #{schema := 1}} = hls_debug:inspect_waits(FirstQueue, #{max_queries => 32})
        end,
        {ok, Report} = hls_topology_debug:inspect_waits(Session, Seeds, #{max_queries => 2048}),
        HasSink = lists:any(fun(#{kind := K, channel := Id}) ->
            K =:= external_sink andalso lists:member(Id, maps:get(reobserved_blocked, Report))
        end, maps:get(edges, Report)),
        true = Withheld orelse HasSink,
        ok = file:write_file(filename:join(Stage, "blocked.json"), json:encode(Report)),
        RecoverySeeds = case Direct of
            true ->
                %% Release missing contributors independently of the report
                %% sink. Inspect committed failure while the healthy peer's
                %% output is backpressured, entirely through public queries.
                ok = file:write_file(filename:join(Stage, "contributions"), <<>>),
                ok = await_file(Stage, "contributions_released", 1000),
                ok = hls_actor_debug_live:await_completed(Session, direct_reduction),
                ok = hls_actor_debug_live:inspect(Session, Stage, completed),
                OutputSeeds = [Id || #{<<"id">> := Id, <<"endpoints">> := Endpoints} <- maps:get(<<"probes">>, Manifest),
                    lists:any(fun(E) -> maps:get(<<"external">>, E, false) andalso
                        maps:get(<<"role">>, E) =:= <<"consumer">> end, Endpoints),
                    {ok, #{value := 1}} <- [hls_topology_debug:query(Session, Id)]],
                [_ | _] = OutputSeeds,
                {ok, Completed} = hls_topology_debug:inspect_waits(Session, OutputSeeds, #{max_queries => 2048}),
                true = lists:any(fun(#{kind := K, channel := Id}) ->
                    K =:= external_sink andalso lists:member(Id, maps:get(reobserved_blocked, Completed))
                end, maps:get(edges, Completed)),
                ok = file:write_file(filename:join(Stage, "completed.json"), json:encode(Completed)),
                OutputSeeds;
            false -> Seeds
        end,
        ok = file:write_file(filename:join(Stage, "release"), <<>>),
        ok = await_file(Stage, "released", 1000),
        {ok, Recovered} = hls_topology_debug:inspect_waits(Session, RecoverySeeds, #{max_queries => 2048}),
        ok = file:write_file(filename:join(Stage, "recovered.json"), json:encode(Recovered)),
        false = lists:any(fun(#{kind := K, channel := Id}) ->
            K =:= external_sink andalso lists:member(Id, maps:get(reobserved_blocked, Recovered))
        end, maps:get(edges, Recovered)),
        ok = hls_actor_debug_live:inspect(Session, Stage, released),
        Diagnosis = case {Withheld, Direct} of
            {true, true} -> "pending and terminal reductions inspected; healthy output stall found and released";
            {true, false} -> "partial reductions inspected and withheld participants released";
            {false, false} -> "external stall found and release observed"
        end,
        io:format("PASS: ~p initially blocked seeds, ~p initial adaptive queries; ~s~n",
            [length(Seeds), length(maps:get(observations, Report)), Diagnosis]),
        ok
    after
        hls_debug:stop(Client),
        hls_fabric:stop(Fabric)
    end,
    file:write_file(filename:join(Stage, "done"), <<>>).

await_file(_Stage, Name, 0) -> error({release_timeout, Name});
await_file(Stage, Name, Attempts) ->
    case file:read_file(filename:join(Stage, Name)) of
        {ok, _} -> ok;
        {error, enoent} -> timer:sleep(1), await_file(Stage, Name, Attempts-1)
    end.
