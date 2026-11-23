-module(hls_protocol_wait_graph).
-moduledoc "Checks generation-ranked finite wait graphs supplied through hls_protocol_model. The result concerns the supplied event model; source refinement, guard agreement and reset marking must be established separately before program admission.".

%% Finite model checking.
-export([check/2]).

-doc "Checks a nonempty finite event graph with zero-lag prerequisite edges and strictly-older-generation edges. Event identities must be unique, every endpoint must exist, and the zero-lag subgraph must be acyclic. Returns an executable topological rank or a diagnostic cycle. A successful result means every wait decreases the lexicographic pair {generation, rank}; it does not prove that source execution refines these nodes, that omitted conditional events are harmless, or that environment fairness holds. Storage edges require an older release and an initially free resource; generation-progress edges require a separately checked source transition. Lag1 is a lower bound, not a claim that every tag increments by exactly1.".
-spec check([term()], [map()]) -> {ok, map()} | {error, term()}.
check(Nodes, Edges) ->
    case validate(Nodes, Edges) of
        ok -> rank(Nodes, Edges);
        Error -> Error
    end.

%% OTP topological sorting can retain a self edge; reject those explicitly before ranking.
-spec rank([term()], [map()]) -> {ok, map()} | {error, term()}.
rank(Nodes, Edges) ->
    Self = lists:usort([W || #{waiter := W, prerequisite := P, lag := 0} <- Edges, W =:= P]),
    case Self of
        [] ->
            Graph = digraph:new(),
            try
                lists:foreach(fun(N) -> digraph:add_vertex(Graph, N) end, Nodes),
                lists:foreach(
                    fun
                        (#{waiter := W, prerequisite := P, lag := 0}) ->
                            digraph:add_edge(Graph, P, W);
                        (#{lag := 1}) ->
                            ok
                    end,
                    Edges
                ),
                case digraph_utils:topsort(Graph) of
                    false ->
                        {error,
                            {same_generation_wait_cycle,
                                lists:sort(digraph_utils:cyclic_strong_components(Graph))}};
                    Order ->
                        Ranks = maps:from_list(lists:zip(Order, lists:seq(0, length(Order) - 1))),
                        true = lists:all(
                            fun
                                (#{lag := 1}) ->
                                    true;
                                (#{waiter := W, prerequisite := P, lag := 0}) ->
                                    maps:get(P, Ranks) < maps:get(W, Ranks)
                            end,
                            Edges
                        ),
                        {ok, #{
                            ranks => Ranks,
                            edges => Edges,
                            property => lexicographically_decreasing_wait,
                            source_refinement => unestablished,
                            reset_marking => unestablished,
                            conditional_event_agreement => unestablished,
                            fairness => local_service_and_declared_external_sinks
                        }}
                end
            after
                digraph:delete(Graph)
            end;
        _ ->
            {error, {same_generation_wait_cycle, [[N] || N <- Self]}}
    end.

%% Unknown nodes or unspecified lags cannot silently remove a real dependency.
-spec validate([term()], [map()]) -> ok | {error, term()}.
validate([], _) ->
    {error, empty_event_graph};
validate(Nodes, Edges) ->
    case length(Nodes) =:= length(lists:usort(Nodes)) of
        false -> {error, duplicate_event_identity};
        true -> validate_edges(Edges, maps:from_keys(Nodes, true))
    end.

%% Initial freedom belongs only to credit reuse; it cannot excuse a current-generation application cycle.
-spec validate_edges([map()], map()) -> ok | {error, term()}.
validate_edges([], _) ->
    ok;
validate_edges([E = #{waiter := W, prerequisite := P, lag := Lag, kind := Kind} | Rest], Nodes) when
    Lag =:= 0; Lag =:= 1
->
    case {maps:is_key(W, Nodes), maps:is_key(P, Nodes), {Lag, Kind}} of
        {false, _, _} ->
            {error, {unknown_waiter, W}};
        {_, false, _} ->
            {error, {unknown_prerequisite, P}};
        {true, true, {0, dependency}} ->
            validate_edges(Rest, Nodes);
        {true, true, {0, sender_order}} ->
            validate_edges(Rest, Nodes);
        {true, true, {1, generation_progress}} ->
            case maps:find(obligation, E) of
                {ok, _} -> validate_edges(Rest, Nodes);
                error -> {error, {unidentified_generation_transition, E}}
            end;
        {true, true, {1, storage_reuse}} ->
            case maps:find(resource, E) of
                {ok, _} -> validate_edges(Rest, Nodes);
                error -> {error, {unidentified_storage, E}}
            end;
        _ ->
            {error, {invalid_wait_edge, E}}
    end;
validate_edges([Edge | _], _) ->
    {error, {invalid_wait_edge, Edge}}.
