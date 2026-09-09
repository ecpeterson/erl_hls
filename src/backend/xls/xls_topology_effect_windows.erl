%%%% xls_topology_effect_windows
%%%%
%%%% Safe ownership domains for scheduler effect windows.

-module(xls_topology_effect_windows).
-moduledoc false.

-export([partition/2, partition/3]).

-type policy() :: global | weak_components.
-type scheduler_index() :: non_neg_integer().
-type domain() :: [scheduler_index()].

-spec partition([map()], policy()) -> [domain()].
partition(Schedulers, Policy) ->
    partition(Schedulers, Policy, []).

-doc "Partitions schedulers while treating each incidence list as one edge.".
-spec partition([map()], policy(), [[scheduler_index()]]) -> [domain()].
partition(Schedulers, global, Incidences) ->
    validate(
        Schedulers,
        Incidences,
        [scheduler_indices(Schedulers)]
    );
partition(Schedulers, weak_components, Incidences) ->
    validate(
        Schedulers,
        Incidences,
        weak_components(Schedulers, Incidences)
    ).

-spec weak_components([map()], [[scheduler_index()]]) -> [domain()].
weak_components(Schedulers, Incidences) ->
    %% If an owned batch can block on a destination before releasing its
    %% reservation, both schedulers must share one owner. The finest safe
    %% partition is therefore weak connectivity, not directed SCCs.
    Indices = scheduler_indices(Schedulers),
    Adjacency0 = maps:from_list([{Index, []} || Index <- Indices]),
    RouteAdjacency = lists:foldl(
        fun(Scheduler, Acc0) ->
            Source = maps:get(index, Scheduler),
            lists:foldl(
                fun(Destination, Acc) ->
                    Target = maps:get(index, Destination),
                    add_undirected_edge(Source, Target, Acc)
                end,
                Acc0,
                maps:get(destinations, Scheduler)
            )
        end,
        Adjacency0,
        Schedulers
    ),
    %% A bounded manager shared by several schedulers creates the same
    %% backpressure dependency as ordinary routed effects.  Model each
    %% manager's incidence set as an undirected hyperedge.  A star is enough
    %% to induce its weak component without manufacturing wiring edges.
    Adjacency = lists:foldl(
        fun add_incidence/2,
        RouteAdjacency,
        Incidences
    ),
    connected_components(Indices, Adjacency, [], []).

add_incidence([], Adjacency) ->
    Adjacency;
add_incidence([Root | Members], Adjacency) ->
    lists:foldl(
        fun(Member, Acc) -> add_undirected_edge(Root, Member, Acc) end,
        Adjacency,
        Members
    ).

scheduler_indices(Schedulers) ->
    lists:sort([maps:get(index, Scheduler) || Scheduler <- Schedulers]).

add_undirected_edge(Left, Right, Adjacency) ->
    true = maps:is_key(Left, Adjacency),
    true = maps:is_key(Right, Adjacency),
    Adjacency#{
        Left := lists:usort([Right | maps:get(Left, Adjacency)]),
        Right := lists:usort([Left | maps:get(Right, Adjacency)])
    }.

connected_components([], _Adjacency, _Seen, Components) ->
    lists:reverse(Components);
connected_components([Index | Rest], Adjacency, Seen, Components) ->
    case lists:member(Index, Seen) of
        true ->
            connected_components(Rest, Adjacency, Seen, Components);
        false ->
            {Members, Seen1} = connected_component(
                [Index], Adjacency, Seen, []
            ),
            connected_components(
                Rest,
                Adjacency,
                Seen1,
                [lists:sort(Members) | Components]
            )
    end.

connected_component([], _Adjacency, Seen, Members) ->
    {Members, Seen};
connected_component([Index | Rest], Adjacency, Seen, Members) ->
    case lists:member(Index, Seen) of
        true -> connected_component(Rest, Adjacency, Seen, Members);
        false ->
            connected_component(
                maps:get(Index, Adjacency) ++ Rest,
                Adjacency,
                [Index | Seen],
                [Index | Members]
            )
    end.

validate(Schedulers, Incidences, Domains) ->
    SchedulerIndices = scheduler_indices(Schedulers),
    SchedulerIndices = lists:sort(lists:append(Domains)),
    true = lists:all(fun(Members) -> Members =/= [] end, Domains),
    DomainIndex = maps:from_list([
        {SchedulerIndex, Domain}
        || {Domain, Members} <- lists:enumerate(0, Domains),
           SchedulerIndex <- Members
    ]),
    lists:foreach(
        fun(Scheduler) ->
            Source = maps:get(index, Scheduler),
            SourceDomain = maps:get(Source, DomainIndex),
            lists:foreach(
                fun(Destination) ->
                    SourceDomain = maps:get(
                        maps:get(index, Destination), DomainIndex
                    )
                end,
                maps:get(destinations, Scheduler)
            )
        end,
        Schedulers
    ),
    lists:foreach(
        fun
            ([]) -> ok;
            ([First | Rest]) ->
                Domain = maps:get(First, DomainIndex),
                lists:foreach(
                    fun(Index) -> Domain = maps:get(Index, DomainIndex) end,
                    Rest
                )
        end,
        Incidences
    ),
    Domains.
