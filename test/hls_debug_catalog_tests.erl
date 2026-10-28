-module(hls_debug_catalog_tests).
-include_lib("eunit/include/eunit.hrl").

%% A single family member retains logical identity independently of its process address.
-spec cpu_targets_retain_logical_identity_test() -> ok.
cpu_targets_retain_logical_identity_test() ->
    Plan = hls_topology:normalize(hls_grid_topology_fixture:topology(1, 1)),
    {ok, Pid} = hls_statem:start_link(hls_grid_cell_fixture, [],
        [{mailbox_capacity, 1}, {outputs, #{}}]),
    Identity = {family, grid, [0, 0]},
    try
        Catalog = hls_debug_catalog:cpu(Plan, #{Identity => Pid}),
        ?assertEqual([Identity], hls_debug_catalog:actors(Catalog)),
        {ok, Target} = hls_debug_catalog:actor(Catalog, Identity),
        ?assertEqual([{identity, Identity}, {lifecycle, connected}],
            hls_debug:info(Target, [identity, lifecycle])),
        ?assertEqual({placement, #{kind => process, pid => Pid}}, hls_debug:info(Target, placement)),
        #{mailbox := #{committed := Count}} = hls_statem:info(Pid),
        ?assertEqual({message_queue_len, Count}, hls_debug:info(Target, message_queue_len)),
        ?assertMatch({error, {unknown_actor, _}}, hls_debug_catalog:actor(Catalog, {family, grid, [9, 9]}))
    after gen_server:stop(Pid) end.

%% Checks exact actor placement and binding validation.
-spec exact_actor_placement_and_binding_validation_test() -> ok.
exact_actor_placement_and_binding_validation_test() ->
    Plan = hls_topology:from_module(ordered_egress_topology),
    Catalog = hls_debug_catalog:hardware(Plan, #{}, []),
    [Id | _] = hls_debug_catalog:actors(Catalog),
    {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
    ?assertEqual({placement, #{kind => direct}}, hls_debug:info(Actor, placement)),
    ?assertError({process_bindings, _, []}, hls_debug_catalog:cpu(Plan, #{})).
