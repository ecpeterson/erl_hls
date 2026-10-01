%%%% Safe ownership domains for scheduler effect windows.
-module(xls_topology_effect_windows).
-moduledoc false.
-export([partition/3, annotate/2]).

%% One global ownership domain or independent weakly connected components.
-type policy() :: global | weak_components.
%% The ordered scheduler indices sharing one effect-window arbiter.
-type domain() :: [non_neg_integer()].

%% Owners are scheduler indices. Dependencies may also contain non-owning
%% vertices (direct actors), and may be hyperedges (bounded reduction planes).
%% Project to owners only AFTER finding weak components: dropping a direct
%% actor first would break paths through it. Edge direction cannot justify
%% splitting ownership, even between distinct directed SCCs.
-doc "Divides the physical communication graph into ownership domains.".
-spec partition([non_neg_integer()], policy(), [[term()]]) -> [domain()].
partition([], _, _) -> [];
partition(Owners, global, _) -> [lists:sort(Owners)];
partition(Owners, weak_components, Dependencies) ->
    Vertices = lists:usort(Owners ++ lists:append(Dependencies)),
    Adjacency = lists:foldl(fun add_dependency/2,
        maps:from_keys(Vertices, []), Dependencies),
    Components = components(Vertices, Adjacency, #{}, []),
    OwnerSet = maps:from_keys(Owners, true),
    lists:sort([Members || Component <- Components,
        Members <- [[V || V <- Component, maps:is_key(V, OwnerSet)]],
        Members =/= []]).

-doc "Attaches domain identity and local arbitration position to each execution group.".
-spec annotate([map()], [domain()]) -> [map()].
annotate(Schedulers, Domains) ->
    Membership = maps:from_list([{Owner, {Domain, Position}} ||
        {Domain, Members} <- lists:enumerate(0, Domains),
        {Position, Owner} <- lists:enumerate(0, Members)]),
    [begin
        {Domain, Position} = maps:get(Index, Membership),
        Scheduler#{effect_window_domain => Domain, effect_window_position => Position}
    end || Scheduler = #{index := Index} <- Schedulers].

%% A star gives a hyperedge's connectivity without quadratic edge expansion.
-spec add_dependency([Vertex], #{Vertex => [Vertex]}) -> #{Vertex => [Vertex]}.
add_dependency([], Adjacency) -> Adjacency;
add_dependency([Root | Rest], Adjacency) ->
    lists:foldl(fun(Member, Acc) ->
        Acc#{Root := [Member | maps:get(Root, Acc)],
            Member := [Root | maps:get(Member, Acc)]}
    end, Adjacency, lists:usort(Rest) -- [Root]).

%% Collects disjoint weakly connected components from the remaining graph vertices.
-spec components([any()],term(),map(),[[any()]]) -> [[any()]].
components([], _, _, Acc) -> lists:reverse(Acc);
components([Vertex | Rest], Adjacency, Seen, Acc) ->
    case maps:is_key(Vertex, Seen) of
        true -> components(Rest, Adjacency, Seen, Acc);
        false ->
            {Members, Seen1} = visit([Vertex], Adjacency, Seen, []),
            components(Rest, Adjacency, Seen1, [lists:sort(Members) | Acc])
    end.

%% Traverses undirected reachability while recording visited vertices.
-spec visit([any()],term(),map(),[any()]) -> {[any()],map()}.
visit([], _, Seen, Members) -> {Members, Seen};
visit([Vertex | Rest], Adjacency, Seen, Members) ->
    case maps:is_key(Vertex, Seen) of
        true -> visit(Rest, Adjacency, Seen, Members);
        false -> visit(maps:get(Vertex, Adjacency) ++ Rest, Adjacency,
            Seen#{Vertex => true}, [Vertex | Members])
    end.
