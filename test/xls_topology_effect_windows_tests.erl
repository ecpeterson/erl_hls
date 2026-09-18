-module(xls_topology_effect_windows_tests).
-include_lib("eunit/include/eunit.hrl").

non_owners_connect_without_receiving_grants_test() ->
    D = fun(I) -> {direct, I} end,
    Dependencies = [[0, D(0)], [D(0), D(1)], [D(1), 2],
        [1, D(2)], [D(2), 3], [D(3), D(4)]],
    ?assertEqual([[0, 2], [1, 3], [4]],
        xls_topology_effect_windows:partition([4, 3, 2, 1, 0], weak_components, Dependencies)),
    ?assertEqual([[0, 1, 2, 3, 4]],
        xls_topology_effect_windows:partition([4, 3, 2, 1, 0], global, Dependencies)),
    ?assertEqual([], xls_topology_effect_windows:partition([], global, Dependencies)),
    ?assertEqual([], xls_topology_effect_windows:partition([], weak_components, Dependencies)).

bounded_manager_hyperedges_and_local_positions_test() ->
    Domains = xls_topology_effect_windows:partition([0, 1, 2, 3], weak_components,
        [[], [0], [0, 0], [0, {direct, 7}, 2], [1, 3, 1]]),
    ?assertEqual([[0, 2], [1, 3]], Domains),
    Annotated = xls_topology_effect_windows:annotate([#{index => I} || I <- [3, 0, 2, 1]], Domains),
    ?assertEqual([{1, 1}, {0, 0}, {0, 1}, {1, 0}],
        [{D, P} || #{effect_window_domain := D, effect_window_position := P} <- Annotated]),
    ?assertEqual([<<"effect_window_domain_1_request_p[u32:1]">>,
        <<"effect_window_domain_1_grant_c[u32:1]">>, <<"effect_window_domain_1_release_p[u32:1]">>],
        [iolist_to_binary(A) || A <- xls_effect_window_dslx:arguments(Domains, hd(Annotated))]).

%% Exhaust all undirected four-vertex graphs and all owner subsets against
%% OTP's graph implementation. Vertices without ownership may occur anywhere
%% in a path. Reverse edge and input order to check canonical domain numbering.
small_graphs_match_otp_components_test() ->
    Vertices = [0, 1, 2, 3],
    Edges = [[A, B] || A <- Vertices, B <- Vertices, A < B],
    lists:foreach(fun(Mask) ->
        Selected = subset(Edges, Mask),
        Graph = digraph:new(),
        try
            [digraph:add_vertex(Graph, V) || V <- Vertices],
            [digraph:add_edge(Graph, A, B) || [A, B] <- Selected],
            Components = digraph_utils:components(Graph),
            lists:foreach(fun(OwnerMask) ->
                Owners = subset(Vertices, OwnerMask),
                Expected = lists:sort([lists:sort(Members) || C <- Components,
                    Members <- [[V || V <- C, lists:member(V, Owners)]], Members =/= []]),
                ?assertEqual(Expected, xls_topology_effect_windows:partition(
                    lists:reverse(Owners), weak_components,
                    [lists:reverse(E) || E <- lists:reverse(Selected)]))
            end, lists:seq(0, 15))
        after digraph:delete(Graph) end
    end, lists:seq(0, 63)).

subset(Items, Mask) -> [Item || {I, Item} <- lists:enumerate(0, Items), Mask band (1 bsl I) =/= 0].
