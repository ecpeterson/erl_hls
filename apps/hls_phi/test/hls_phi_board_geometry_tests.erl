-module(hls_phi_board_geometry_tests).
-moduledoc "Physical tiling, wrapped adjacency and aliased-link accounting regressions.".
-include_lib("eunit/include/eunit.hrl").

%% Every board contains four data sites, four syndrome sites and four co-located phi actors.
-spec populations_test() -> ok.
populations_test() ->
    lists:foreach(fun(D) ->
        #{boards := Boards} = hls_phi_board_geometry:report(D, 12),
        ?assertEqual(D*D div 2, length(Boards)),
        [begin
            ?assertEqual(12, maps:get(actors, Board)),
            ?assertEqual([2,2,2,2,2,2], lists:sort(maps:values(maps:get(families, Board))))
        end || Board <- Boards],
        P = hls_phi_board_geometry:placement(D),
        Sites = [hls_phi_board_geometry:physical(D, Id) || Id = {family, F, _} <- maps:keys(P),
            F =/= phi_x, F =/= phi_z],
        ?assertEqual(4*D*D, length(lists:usort(Sites)))
    end, [2,4,6]),
    ?assertError({untiled_distance, 3}, hls_phi_board_geometry:placement(3)).

%% Verify actual data/syndrome routes against physical nearest-neighbor distances, including wraps.
-spec adjacency_test() -> ok.
adjacency_test() ->
    D = 6,
    Plan = hls_topology:normalize(phi_noise_topology:topology(D)),
    Placement = hls_phi_board_geometry:placement(D),
    maps:foreach(fun(Id = {family, F, [X, Y]}, _) ->
        A = hls_phi_board_geometry:physical(D, Id),
        lists:foreach(fun(#{source := {_, Port}, recipients := Recipients}) ->
            [begin
                B = hls_phi_board_geometry:physical(D, {family, T, [TX, TY]}),
                {DX, DY} = case Port of north -> {0,-1}; south -> {0,1}; east -> {1,0}; west -> {-1,0}; _ -> {0,0} end,
                Scale = case F of phi_x -> 2; phi_z -> 2; _ -> 1 end,
                {AX, AY} = A,
                ?assertEqual({(AX+DX*Scale+2*D) rem (2*D), (AY+DY*Scale+2*D) rem (2*D)}, B)
            end || {actor, {T, TX, TY}} <- Recipients]
        end, hls_logical_topology:routes_for_instance(Plan, F, [X,Y]))
    end, Placement).

%% Two north/south boundaries share one remote peer at d=2; four peers are distinct at d=6.
-spec aliased_links_test() -> ok.
aliased_links_test() ->
    #{directions := Small} = hls_phi_board_geometry:report(2,12),
    Remote = [L || L = #{device := 0, local := false} <- Small],
    ?assertEqual([north,south], [P || #{direction := P} <- Remote]),
    ?assertEqual([1], lists:usort([P || #{peer := P} <- Remote])),
    ?assertEqual(720, lists:sum([W || #{wire_words := W} <- Remote])),
    #{directions := Large} = hls_phi_board_geometry:report(6,12),
    Edges = [L || L = #{device := 0, local := false} <- Large],
    ?assertEqual(4, length(lists:usort([P || #{peer := P} <- Edges]))),
    ?assertEqual(#{north=>360,south=>360,east=>180,west=>180},
        maps:from_list([{P,W} || #{direction := P, wire_words := W} <- Edges])).
