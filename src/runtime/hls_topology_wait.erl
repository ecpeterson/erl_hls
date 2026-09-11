-module(hls_topology_wait).
-moduledoc "Bounded host-side exploration of candidate backpressure dependencies.".
-export([inspect_waits/4]).

%% Query is injected so simulation, live hardware and deterministic fixtures
%% exercise the same adaptive walk. All maps come from a verified manifest.
inspect_waits(Manifest = #{<<"probes">> := Probes, <<"resources">> := Resources}, Query, Seeds, Options) ->
    #{max_queries := Max} = maps:merge(#{max_queries => 1024}, Options),
    case maps:keys(Options) -- [max_queries] of [] -> ok; Keys -> error({options, Keys}) end,
    true = is_integer(Max) andalso Max >= 2,
    Catalog = maps:from_list([{maps:get(<<"id">>, R), R} || R <- Resources]),
    Unknown = Seeds -- maps:keys(Catalog),
    case Unknown of
        [] ->
            Channels = maps:from_list([{maps:get(<<"id">>, P), P} || P <- Probes]),
            Queues = maps:from_list([{maps:get(<<"path">>, Q), Q} ||
                Q = #{<<"kind">> := <<"fifo">>} <- Resources]),
            State = #{query => Query, catalog => Catalog, channels => Channels, queues => Queues,
                seen => #{}, edges => [], samples => [], remaining => Max div 2},
            try
                Walk = walk(Seeds, State),
                finish(Manifest, Walk)
            catch throw:{query_error, Reason} -> {error, Reason} end;
        _ -> {error, {unknown_resources, Unknown}}
    end.

walk([], State) -> State;
walk([Id | Rest], State = #{seen := Seen}) when is_map_key(Id, Seen) -> walk(Rest, State);
walk(_Pending, State = #{remaining := 0}) -> State#{truncated => true};
walk([Id | Rest], State = #{catalog := Catalog}) ->
    {Sample, NextState} = observe(Id, State),
    case maps:get(Id, Catalog) of
        #{<<"kind">> := <<"fifo">>, <<"push">> := Push, <<"pop">> := Pop} ->
            walk(Rest ++ [Push, Pop], NextState);
        #{<<"kind">> := <<"channel">>} ->
            case Sample of
                #{value := 1} ->
                    {Edge, Next} = dependencies(Id, NextState),
                    #{edges := Edges} = NextState,
                    walk(Rest ++ Next, NextState#{edges := [Edge | Edges]});
                _ -> walk(Rest, NextState)
            end
    end.

observe(Id, State = #{query := Query, samples := Samples, seen := Seen, remaining := Remaining}) ->
    case Query(Id) of
        {ok, Sample = #{id := Id, cycle := Cycle}} ->
            case Samples of
                [#{cycle := Previous} | _] when Cycle =< Previous ->
                    throw({query_error, observation_clock_regressed});
                _ -> ok
            end,
            {Sample, State#{samples := [Sample | Samples], seen := Seen#{Id => Sample},
                remaining := Remaining-1}};
        {error, Reason} -> throw({query_error, Reason});
        _ -> throw({query_error, invalid_query_reply})
    end.

dependencies(Id, #{channels := Channels, queues := Queues}) ->
    Probe = maps:get(Id, Channels),
    Edge = #{channel => Id, next => []},
    case Probe of
        #{<<"constant_handshake">> := true} ->
            {Edge#{kind => ambiguous}, []};
        #{<<"endpoints">> := Endpoints} ->
            Consumers = [E || E = #{<<"role">> := <<"consumer">>} <- Endpoints],
            case Consumers of
                [#{<<"external">> := true, <<"port">> := Port}] ->
                    {Edge#{kind => external_sink, endpoint => Port}, []};
                [#{<<"path">> := Path}] ->
                    Next = outgoing(Path, Channels),
                    case maps:find(Path, Queues) of
                        {ok, #{<<"id">> := QueueId, <<"pop">> := Pop}} ->
                            {Edge#{kind => fifo, next := [Pop], queue => QueueId}, [QueueId, Pop]};
                        error ->
                            {Edge#{kind => component, endpoint => Path, next := Next}, Next}
                    end;
                _ -> {Edge#{kind => ambiguous}, []}
            end
    end.

outgoing(Path, Channels) ->
    lists:sort([Id || {Id, #{<<"endpoints">> := Endpoints}} <- maps:to_list(Channels),
        lists:any(fun
            (#{<<"role">> := <<"producer">>, <<"path">> := P} = E) ->
                P =:= Path andalso not maps:get(<<"external">>, E, false);
            (_) -> false
        end, Endpoints)]).

finish(#{<<"fingerprint">> := Hash}, State = #{samples := ReverseFirst, seen := First,
        edges := ReverseEdges}) ->
    Ids = [Id || #{id := Id} <- lists:reverse(ReverseFirst)],
    %% Budget reserves one recheck for every first observation, even on a
    %% truncated walk. Rechecking all explored outputs can expose moving waits.
    Rechecked = lists:foldl(fun(Id, S) -> element(2, observe(Id, S)) end, State, Ids),
    #{seen := Last, samples := ReverseSamples} = Rechecked,
    Changed = [Id || Id <- Ids, maps:get(value, maps:get(Id, First)) =/=
                                maps:get(value, maps:get(Id, Last))],
    Stable = [Id || Id <- Ids, maps:get(value, maps:get(Id, First)) =:= 1,
        maps:get(value, maps:get(Id, Last)) =:= 1,
        maps:is_key(Id, maps:get(channels, State))],
    Edges = lists:reverse(ReverseEdges),
    {ok, #{schema => 1, fingerprint => Hash, observations => lists:reverse(ReverseSamples),
        edges => Edges, changed_resources => Changed, reobserved_blocked => Stable,
        candidate_cycles => cycles(Edges, Stable), truncated => maps:get(truncated, State, false)}}.

cycles(Edges, Stable) ->
    Graph = digraph:new(),
    try
        [digraph:add_vertex(Graph, Id) || Id <- Stable],
        [digraph:add_edge(Graph, Id, Next) || #{channel := Id, next := Targets} <- Edges,
            lists:member(Id, Stable), Next <- Targets, lists:member(Next, Stable)],
        lists:sort([lists:sort(Component) || Component <- digraph_utils:cyclic_strong_components(Graph)])
    after digraph:delete(Graph) end.
