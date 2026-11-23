-module(phi_domain_repetition_fixture_tests).
-moduledoc "Checks application-owned recovery placement and setup without rendering hardware. Actual source compilation, RTL traffic and board qualification remain separate witnesses.".
-include_lib("eunit/include/eunit.hrl").

%% Global indices follow elaboration while each half owns all three source families.
-spec selected_placement_test() -> ok.
selected_placement_test() ->
    {Config, Placement, #{actors := Actors, physical_board_image := false}} =
        phi_domain_repetition_fixture:configuration(8, 4, none),
    ?assertEqual(24, maps:get(actor_limit, Config)),
    ?assertEqual(20, maps:get(frame_payload_words, Config)),
    ?assertEqual([[a, b]], maps:get(restart_groups, Placement)),
    ?assertEqual(lists:seq(0, 23), lists:sort(lists:append([Is || {_, Is} <- maps:get(domains, Placement)]))),
    lists:foreach(fun({Role, First, Last}) ->
        ?assertEqual(lists:sort([{F, X, 0} || F <- [data, syndrome, phi], X <- lists:seq(First, Last)]),
            lists:sort([Id || #{id := Id, domain := D} <- Actors, D =:= Role]))
    end, [{a, 0, 3}, {b, 4, 7}]),
    ok.

%% Observation changes only the requested view; source, placement and setup remain matched.
-spec matched_inspection_test() -> ok.
matched_inspection_test() ->
    {Plain, Placement, Metadata} = phi_domain_repetition_fixture:configuration(8, 4, none),
    {Inspected, Placement, Observations} = phi_domain_repetition_fixture:configuration(8, 4, process),
    ?assertEqual(Plain#{inspection := process}, Inspected),
    ?assertEqual(Metadata#{inspection := process}, Observations).

%% The host can address setup without broadcasting an indistinguishable coordinate to two families.
-spec addressed_topology_test() -> ok.
addressed_topology_test() ->
    Topology = phi_domain_repetition_fixture:topology(8, 16#80000000),
    #{startup := [], ingresses := [{control_router, {rectangle, [8, 1]}, Targets}],
        route_relations := Routes, externals := Externals} = Topology,
    ?assertEqual([data, syndrome, phi], [Family || {Family, _, _} <- Targets]),
    ?assert(lists:member({decoder_corrections, out, [phi_correction]}, Externals)),
    ?assert(lists:member({decoder_status, out, [phi_status]}, Externals)),
    ?assert(lists:member({{phi, correction}, [{external, decoder_corrections}]}, Routes)),
    ?assert(lists:member({{phi, status}, [{external, decoder_status}]}, Routes)),
    Original = phi_repetition_topology:topology(8),
    ?assertEqual(maps:without([startup, ingresses, externals, route_relations], Original),
        maps:without([startup, ingresses, externals, route_relations], Topology)).

%% Preserve exact original configuration, then order cutoff before any decoder is released.
-spec setup_order_test() -> ok.
setup_order_test() ->
    {_, _, #{original_startup := Original, host_setup := #{prepare := Prepare, start := Start}}} =
        phi_domain_repetition_fixture:configuration(8, 4, none),
    OriginalMessages = lists:sort([{Id, M} || #{target := Id, messages := Ms} <- Original, M <- Ms]),
    Configurations = lists:sort([{Id, M} || #{actor := Id, message := M} <- Prepare ++ Start,
        element(1, M) =/= noise_cutoff]),
    ?assertEqual(OriginalMessages, Configurations),
    ?assertEqual(32, length(Prepare)),
    ?assertEqual(8, length(Start)),
    ?assertEqual(16, length([ok || #{message := {noise_cutoff, 8}} <- Prepare])),
    ?assert(lists:all(fun(#{actor := {Family, _, _}}) -> Family =/= phi end, Prepare)),
    ?assert(lists:all(fun(#{actor := {phi, _, _}, message := {phi_config, _}}) -> true;
        (_) -> false end, Start)),
    ok.

%% Reject empty roles and unsupported observation modes before compiling source actors.
-spec bounds_test() -> ok.
bounds_test() ->
    lists:foreach(fun({Width, Split, Inspection}) ->
        ?assertError({domain_repetition_options, Width, Split, Inspection},
            phi_domain_repetition_fixture:configuration(Width, Split, Inspection))
    end, [{1, 1, none}, {17, 4, none}, {8, 0, none}, {8, 8, none}, {8, 4, full}]),
    {_, #{domains := [{a, A}, {b, B}]}, _} = phi_domain_repetition_fixture:configuration(3, 1, none),
    ?assertEqual({3, 6}, {length(A), length(B)}).
