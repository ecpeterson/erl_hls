-module(hls_partition_ingress_tests).
-include_lib("eunit/include/eunit.hrl").

%% A spanning command is one packet per owner, retaining global coordinates.
-spec global_rectangle_keeps_wire_identity_test() -> ok.
global_rectangle_keeps_wire_identity_test() ->
    P = partition(),
    [{left, Packet}, {right, Packet}] = hls_partition_ingress:commands(P, control, cells,
        {0, 0, 3, 2}, {work, 16#12345678}),
    Tag = hls_partition_fixture:pack_tag(work),
    ?assertEqual(<<0:16, 0:16, 3:16, 2:16, 0:2, 1:8, 0:16, Tag:8, 16#12345678:96>>, Packet).

%% Sparse device ownership is intersected at actor points, not a bounding-box approximation.
-spec device_selection_exhausts_small_rectangles_test() -> ok.
device_selection_exhausts_small_rectangles_test() ->
    P = partition(),
    lists:foreach(fun({X0, Y0, X1, Y1}) ->
        Expected = lists:usort([case X of 1 -> right; _ -> left end
            || X <- [1, 3], Y <- [0, 2], X0 =< X, X =< X1, Y0 =< Y, Y =< Y1]),
        Actual = hls_partition_ingress:commands(P, control, cells, {X0, Y0, X1, Y1}, {work, 1}),
        ?assertEqual(Expected, [D || {D, _} <- Actual])
    end, [{X0, Y0, X1, Y1} || X0 <- lists:seq(0, 3), X1 <- lists:seq(X0, 3),
        Y0 <- lists:seq(0, 2), Y1 <- lists:seq(Y0, 2)]).

%% Invalid rectangles and undeclared schemas cannot cause a partial send.
-spec invalid_commands_are_rejected_test() -> ok.
invalid_commands_are_rejected_test() ->
    P = partition(),
    lists:foreach(fun(Bounds) ->
        ?assertError({partition_rectangle, Bounds, [4, 3]},
            hls_partition_ingress:commands(P, control, cells, Bounds, {work, 0}))
    end, [{-1, 0, 1, 1}, {0, 0, 4, 1}, {2, 0, 1, 1}, {0, 2, 1, 1}]),
    ?assertError({badmatch, false}, hls_partition_ingress:commands(P, control, cells,
        {0, 0, 3, 2}, {unknown, 0})).

%% Control leaves keep global embedded coordinates and belong only to their device.
-spec local_bindings_preserve_embedded_points_test() -> ok.
local_bindings_preserve_embedded_points_test() ->
    P = partition(),
    #{ingresses := [#{bindings := Left}]} = hls_partition:device(P, left),
    #{ingresses := [#{bindings := Right}]} = hls_partition:device(P, right),
    ?assertEqual([[3, 0], [3, 2]], [Point || #{point := Point} <- Left]),
    ?assertEqual([[1, 0], [1, 2]], [Point || #{point := Point} <- Right]).

%% A singleton's explicit ingress point need not resemble its identity or placement.
-spec exact_actor_point_test() -> ok.
exact_actor_point_test() ->
    Spec = base(),
    Actors = #{one => hls_partition_fixture, two => hls_partition_fixture},
    Routes = [{{Id, Port}, [{external, reports}]} || Id <- [one, two], Port <- [left, right, report]],
    Ingress = [{control, {rectangle, [7, 5]}, [{cells, [work],
        [{actor, one, {at, [6, 4]}}, {actor, two, {at, [0, 0]}}]}]}],
    P = hls_partition:normalize(hls_topology:normalize(Spec#{actors := Actors, families := #{},
        routes := Routes, route_relations := [], ingresses := Ingress}),
        #{{actor, one} => left, {actor, two} => right}),
    ?assertMatch([{left, _}], hls_partition_ingress:commands(P, control, cells, {6, 4, 6, 4}, {work, 9})),
    ?assertMatch([{right, _}], hls_partition_ingress:commands(P, control, cells, {0, 0, 0, 0}, {work, 9})).

%% The full witness seeds every noise actor before requests; all Pauli updates have one owner.
-spec memory_startup_and_control_coverage_test() -> ok.
memory_startup_and_control_coverage_test() ->
    {Plan = #{startup := Startup}, Placement, _} = hls_phi_memory_fixture:fixture(),
    P = hls_partition:normalize(Plan, Placement),
    ?assertEqual(54, map_size(Placement)),
    lists:foreach(fun(#{target := {Family, _, _}, messages := Messages}) ->
        case Family of
            Phi when Phi =:= phi_x; Phi =:= phi_z -> ?assertEqual(1, length(Messages));
            _ -> ?assertMatch([_, {noise_cutoff, 16}], Messages)
        end
    end, Startup),
    lists:foreach(fun({X, Y}) ->
        [{Owner, _}] = hls_partition_ingress:commands(P, control_router, data,
            {X, Y, X, Y}, {pauli_update, hls_pauli:z()}),
        ?assertEqual(case Y < 2 of true -> 0; false -> 1 end, Owner)
    end, [{X, Y} || X <- lists:seq(0, 2), Y <- lists:seq(0, 5)]).

%% Use a sparse global embedding so empty selections and partition holes are observable.
-spec partition() -> map().
partition() ->
    Plan = hls_topology:normalize(base()),
    Placement = maps:from_list([{{family, cells, [X, Y]}, case X of 0 -> right; 1 -> left end}
        || X <- [0, 1], Y <- [0, 1]]),
    hls_partition:normalize(Plan, Placement).

%% Give each actor genuine output routes while control tests vary its address domain.
-spec base() -> hls_topology:spec().
base() ->
    #{version => 1, actors => #{}, families => #{cells => #{module => hls_partition_fixture, shape => [2, 2]}},
        ingresses => [{control, {rectangle, [4, 3]}, [{cells, [work],
            [{family, cells, {embed, [2, 2], [1, 0]}}]}]}],
        externals => [{reports, out, [work]}], routes => [], startup => [],
        route_relations => [{{cells, Port}, [{external, reports}]} || Port <- [left, right, report]]}.
