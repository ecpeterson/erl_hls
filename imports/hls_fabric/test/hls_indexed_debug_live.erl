-module(hls_indexed_debug_live).
-moduledoc "Queries partial and retired indexed progress through the real framed RTL debug transport.".
-export([run/1]).

-doc "Checks current-key progress, hidden provisional state, stalled completion and query noninterference.".
-spec run(file:filename()) -> ok.
run(Stage) ->
    {ok, Bytes} = file:read_file(filename:join(Stage, "manifest.json")),
    Manifest = json:decode(Bytes),
    {ok, Fabric} = hls_fabric:start_link(filename:join(Stage, "debug_tx"), filename:join(Stage, "debug_rx")),
    {ok, Client} = hls_debug:start_link(undefined, {fabric, Fabric, 2}),
    try
        {ok, Session} = hls_shared_observation:open(Client, Manifest),
        {Plan, Groups} = hls_indexed_debug_dslx:fixture(),
        Catalog = hls_shared_debug_catalog:hardware(Plan, Groups, [], Session),
        {ok, Actor} = hls_debug_catalog:actor(Catalog, {family, cell, [0, 0]}),
        ok = await_file(Stage, "provisional_written", 3000),
        Partial = await(Actor, partial, 100),
        %% Repeat the same live query: observing must neither consume a member nor expose the successor.
        Partial = snapshot(Actor),
        ok = save(Stage, "actors-partial.term", Partial),
        {ok, Initial} = hls_topology_debug:inspect_waits(Session, [], #{max_queries => 64}),
        ok = file:write_file(filename:join(Stage, "blocked.json"), json:encode(Initial)),
        ok = file:write_file(filename:join(Stage, "contributions"), <<>>),
        Completed = await(Actor, completed, 200),
        ok = save(Stage, "actors-completed.term", Completed),
        Seeds = [Id || #{<<"id">> := Id, <<"endpoints">> := Endpoints} <- maps:get(<<"probes">>, Manifest),
            lists:any(fun(E) -> maps:get(<<"external">>, E, false) andalso
                maps:get(<<"role">>, E) =:= <<"consumer">> end, Endpoints),
            {ok, #{value := 1}} <- [hls_topology_debug:query(Session, Id)]],
        [_ | _] = Seeds,
        {ok, Stalled} = hls_topology_debug:inspect_waits(Session, Seeds, #{max_queries => 128}),
        true = stalled_sink(Stalled),
        ok = file:write_file(filename:join(Stage, "completed.json"), json:encode(Stalled)),
        Completed = snapshot(Actor),
        ok = file:write_file(filename:join(Stage, "release"), <<>>),
        ok = await_file(Stage, "application_complete", 3000),
        {ok, Recovered} = hls_topology_debug:inspect_waits(Session, Seeds, #{max_queries => 128}),
        false = stalled_sink(Recovered),
        ok = file:write_file(filename:join(Stage, "recovered.json"), json:encode(Recovered)),
        Completed = snapshot(Actor),
        io:format("PASS: current partial gather queried twice; unopened successor hidden; four ordered/padded reports survive output stall~n")
    after
        hls_debug:stop(Client), hls_fabric:stop(Fabric)
    end,
    file:write_file(filename:join(Stage, "done"), <<>>).

%% Snapshot only stable public metadata; the cycle counter is deliberately excluded from equality.
-spec snapshot(term()) -> map().
snapshot(Actor) -> maps:from_list(hls_debug:info(Actor,
    [phase, initialized, enter_pending, failed, failure, reduction, gather], 10000)).

%% Bounded public polling waits for callback commits without reading simulator internals.
-spec await(term(), partial | completed, non_neg_integer()) -> map().
await(Actor, Moment, Attempts) ->
    Value = snapshot(Actor),
    case {Moment, Value} of
        {partial, #{phase := collecting, initialized := true, enter_pending := false,
            failed := false, failure := none, reduction := idle,
            gather := Progress = #{name := items, key := 0, status := open, population := {members, [0, 1]},
                arrived_members := [1], remaining := 1, received := 1, missing_members := [0]}}} ->
            false = maps:is_key(values, Progress), Value;
        {completed, #{phase := reporting, initialized := true, enter_pending := false,
            failed := false, failure := none, reduction := idle, gather := idle}} -> Value;
        _ when Attempts > 0 -> await(Actor, Moment, Attempts - 1);
        _ -> error({indexed_debug_timeout, Moment, Value})
    end.

%% The existing wait analyzer must identify a still-blocked external sink.
-spec stalled_sink(map()) -> boolean().
stalled_sink(Report) -> lists:any(fun(#{kind := Kind, channel := Id}) ->
    Kind =:= external_sink andalso lists:member(Id, maps:get(reobserved_blocked, Report))
end, maps:get(edges, Report)).

%% Retain public observations alongside the framed transport witness.
-spec save(file:filename(), string(), term()) -> ok.
save(Stage, Name, Value) -> file:write_file(filename:join(Stage, Name), io_lib:format("~p.~n", [Value])).

%% Wait for the scoreboard's public output transfers, with a finite wall-clock retry budget.
-spec await_file(file:filename(), string(), non_neg_integer()) -> ok.
await_file(_Stage, Name, 0) -> error({indexed_debug_release_timeout, Name});
await_file(Stage, Name, Attempts) ->
    case file:read_file(filename:join(Stage, Name)) of
        {ok, _} -> ok;
        {error, enoent} -> timer:sleep(10), await_file(Stage, Name, Attempts - 1)
    end.
