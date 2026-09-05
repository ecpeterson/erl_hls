%%%% xls_topology_effect_windows
%%%%
%%%% Safe ownership domains for scheduler effect windows.

-module(xls_topology_effect_windows).
-moduledoc false.

-export([partition/2]).

-type policy() :: global | weak_components.
-type scheduler_index() :: non_neg_integer().
-type domain() :: [scheduler_index()].

-spec partition([map()], policy()) -> [domain()].
partition(Schedulers, global) ->
    validate(Schedulers, [scheduler_indices(Schedulers)]);
partition(Schedulers, weak_components) ->
    validate(Schedulers, weak_components(Schedulers)).

-spec weak_components([map()]) -> [domain()].
weak_components(Schedulers) ->
    %% If an owned batch can block on a destination before releasing its
    %% reservation, both schedulers must share one owner. The finest safe
    %% partition is therefore weak connectivity, not directed SCCs.
    Indices = scheduler_indices(Schedulers),
    Adjacency0 = maps:from_list([{Index, []} || Index <- Indices]),
    Adjacency = lists:foldl(
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
    connected_components(Indices, Adjacency, [], []).

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

validate(Schedulers, Domains) ->
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
    Domains.
