-module(hls_phi_debug_live).
-export([run/1]).

-define(TIMEOUT, 600000).

run(Stage) ->
    {ok, Bytes} = file:read_file(filename:join(Stage, "manifest.json")),
    Manifest = json:decode(Bytes),
    {ok, DebugFabric} = fabric(Stage, "debug"),
    {ok, BoundaryClient} = hls_debug:start_link(undefined, {fabric, DebugFabric, 1}),
    {ok, QueryClient} = hls_debug:start_link(undefined, {fabric, DebugFabric, 2}),
    {ok, AppFabric} = fabric(Stage, "app"),
    Boundary = {boundary, BoundaryClient, {phi_memory_gateway, host_stream}},
    try
        {ok, Session} = hls_topology_debug:open(QueryClient, Manifest),
        {error, _} = hls_debug:query(QueryClient, 16#77, <<>>, ?TIMEOUT),
        {error, _} = hls_debug:query(BoundaryClient, 16#77, <<>>, ?TIMEOUT),
        {ok, FixtureBytes} = file:read_file(filename:join(Stage, "fixture.json")),
        #{<<"shards">> := Shards} = json:decode(FixtureBytes),
        {Plan, Profile} = hls_phi_debug_dslx:fixture(Shards),
        Catalog = hls_debug_catalog:hardware(Plan, maps:get(scheduler_groups, Profile), [Boundary], Session),
        #{options := Options} = phi_memory_demo:fixture(),
        Expected = phi_memory_demo:run_cpu(),
        ok = phi_memory_demo:verify(Expected),
        {ok, Runner} = phi_memory_runner:start_link(AppFabric, Options, ?TIMEOUT),
        try
            RunnerWorker = async(fun() ->
                Result = phi_memory_runner:await(Runner),
                Expected = Result,
                ok = phi_memory_demo:verify(Result),
                command(Stage, "application_complete"),
                Result
            end),
            command(Stage, "block"),
            ok = await_file(Stage, "blocked"),
            %% All callers share a real broker/stream. No actor-local meaning
            %% is assigned to this whole-gateway monitor's counters or events.
            [BlockedCounters, Actors] = parallel([
                fun() -> counters(Boundary) end,
                fun() -> inspect_actors(Catalog) end]),
            true = maps:get(app_rx_frames, BlockedCounters) > 0,
            true = maps:get(app_tx_stall_cycles, BlockedCounters) > 0,
            0 = maps:get(app_tx_beats, BlockedCounters),
            Sink = sink(Manifest),
            {ok, #{value := 1}} = hls_topology_debug:query(Session, Sink),
            Full = full_queues(Session, Manifest),
            true = Full =/= [],
            {ok, Blocked} = hls_topology_debug:inspect_waits(Session, Full, #{max_queries => 2048}),
            true = lists:member(Sink, maps:get(reobserved_blocked, Blocked)),
            true = lists:any(fun(#{kind := Kind, channel := Id}) -> Kind =:= external_sink andalso Id =:= Sink end,
                maps:get(edges, Blocked)),
            write_json(Stage, "blocked.json", Blocked),
            write_term(Stage, "actors-blocked.term", Actors),
            %% Pause the host-facing debug sink, begin a trace drain, and let
            %% the application recover while both services have queued calls.
            command(Stage, "hold_debug"),
            ok = await_file(Stage, "debug_held"),
            TraceWorker = async(fun() -> trace(Boundary) end),
            ok = await_file(Stage, "reply_held"),
            [FirstTrace, DuringCounters, DuringActors] = collect([TraceWorker,
                async(fun() -> counters(Boundary) end),
                async(fun() -> inspect_actors(Catalog) end)]),
            ok = await_file(Stage, "debug_released"),
            [Actual] = collect([RunnerWorker]),
            FinalCounters = counters(Boundary),
            LaterTrace = trace(Boundary),
            true = maps:get(dropped, LaterTrace) > 0,
            Events = maps:get(events, FirstTrace) ++ maps:get(events, LaterTrace),
            true = lists:any(fun(#{kind := Kind}) -> Kind =:= application_rx end, Events),
            true = lists:any(fun(#{kind := Kind}) -> Kind =:= application_tx end, Events),
            lists:foreach(fun(#{observation_gap := false, tx_id := 0}) -> ok end, Events),
            {ok, Recovered} = hls_topology_debug:inspect_waits(Session, [Sink], #{max_queries => 32}),
            false = lists:member(Sink, maps:get(reobserved_blocked, Recovered)),
            true = maps:get(app_tx_beats, FinalCounters) > 0,
            write_json(Stage, "recovered.json", Recovered),
            write_term(Stage, "debug.term", #{blocked => BlockedCounters, during => DuringCounters,
                final => FinalCounters, first_trace => FirstTrace, later_trace => LaterTrace,
                actors_during => DuringActors, witness => Actual}),
            io:format("PASS: all debug services, ~p actors, ~p full queues; D3 witness matches ERTS~n",
                [length(Actors), length(Full)])
        after
            phi_memory_runner:stop(Runner)
        end
    after
        hls_debug:stop(BoundaryClient), hls_debug:stop(QueryClient),
        hls_fabric:stop(DebugFabric), hls_fabric:stop(AppFabric)
    end,
    command(Stage, "done").

fabric(Stage, Prefix) ->
    hls_fabric:start_link(filename:join(Stage, Prefix ++ "_tx"), filename:join(Stage, Prefix ++ "_rx")).

counters(Boundary) ->
    {ok, Counters = #{observation_drops := 0}} = hls_debug:get_counters(Boundary, ?TIMEOUT),
    Counters.
trace(Boundary) ->
    {ok, Trace = #{observation_drops := 0}} = hls_debug:get_trace(Boundary, ?TIMEOUT),
    Trace.

inspect_actors(Catalog) ->
    [begin
        {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
        Values = maps:from_list(hls_debug:info(Actor,
            [identity, boundaries, initialized, mailbox_initialized, failed, failure, phase,
                message_queue_len, free_slots, postponed, in_flight, waiting_for_egress, cycle], ?TIMEOUT)),
        #{initialized := true, mailbox_initialized := true, failed := false, failure := none,
            message_queue_len := Count, free_slots := Free, postponed := Postponed} = Values,
        {mailbox_capacity, Capacity} = hls_debug:info(Actor, mailbox_capacity),
        true = Count + Free =:= Capacity,
        true = Postponed =< Count,
        Boundaries = hls_debug_catalog:boundaries(Catalog),
        Boundaries = maps:get(boundaries, Values),
        %% Persist scopes, not live client PIDs, so reports remain consultable.
        Values#{boundaries := [Scope || Boundary <- Boundaries,
            {scope, Scope} <- [hls_debug:info(Boundary, scope)]]}
    end || Id <- hls_debug_catalog:actors(Catalog)].

sink(#{<<"probes">> := Probes}) ->
    [Id] = [Id || #{<<"id">> := Id, <<"endpoints">> := Endpoints} <- Probes,
        lists:any(fun(E) -> maps:get(<<"external">>, E, false) andalso
            maps:get(<<"port">>, E) =:= <<"m_axis">> end, Endpoints)],
    Id.

full_queues(Session, #{<<"resources">> := Resources}) ->
    [Id || #{<<"kind">> := <<"fifo">>, <<"id">> := Id, <<"capacity">> := Capacity} <- Resources,
        begin
            {ok, Target} = hls_topology_debug:resource(Session, Id),
            [{occupancy, Count}, {free_slots, Free}] = hls_debug:info(Target, [occupancy, free_slots], ?TIMEOUT),
            true = Count + Free =:= Capacity,
            Count =:= Capacity
        end].

parallel(Functions) -> collect([async(Fun) || Fun <- Functions]).
async(Fun) ->
    Parent = self(),
    spawn_monitor(fun() -> Parent ! {self(), Fun()} end).
collect(Workers) ->
    [receive
        {Pid, Result} -> erlang:demonitor(Ref, [flush]), Result;
        {'DOWN', Ref, process, Pid, Reason} -> error({debug_worker, Reason})
    after ?TIMEOUT -> error(debug_workers_timeout) end || {Pid, Ref} <- Workers].

command(Stage, Name) -> file:write_file(filename:join(Stage, Name), <<>>).
await_file(Stage, Name) -> await_path(filename:join(Stage, Name), 18000).
await_path(_, 0) -> error(simulator_control_timeout);
await_path(Path, N) ->
    case file:read_file(Path) of
        {ok, _} -> ok;
        {error, enoent} -> timer:sleep(10), await_path(Path, N-1)
    end.
write_json(Stage, Name, Value) -> file:write_file(filename:join(Stage, Name), json:encode(Value)).
write_term(Stage, Name, Value) -> file:write_file(filename:join(Stage, Name), io_lib:format("~p.~n", [Value])).
