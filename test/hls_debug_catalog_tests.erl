-module(hls_debug_catalog_tests).
-include_lib("eunit/include/eunit.hrl").

phi_cpu_targets_retain_logical_identity_test() ->
    {ok, Fabric} = phi_memory_cpu_fabric:start_link(3, 0),
    try
        Catalog = phi_memory_cpu_fabric:debug_targets(Fabric),
        ?assertEqual(54, length(hls_debug_catalog:actors(Catalog))),
        {ok, Target} = hls_debug_catalog:actor(Catalog, {family, phi_x, [0, 0]}),
        ?assertEqual([{identity, {family, phi_x, [0, 0]}}, {lifecycle, disconnected}],
            hls_debug:info(Target, [identity, lifecycle])),
        {placement, #{kind := process, pid := Pid}} = hls_debug:info(Target, placement),
        #{mailbox := #{committed := Count}} = hls_statem:info(Pid),
        ?assertEqual({message_queue_len, Count}, hls_debug:info(Target, message_queue_len)),
        ?assertMatch({error, {unknown_actor, _}}, hls_debug_catalog:actor(Catalog, {family, phi_x, [9, 9]}))
    after phi_memory_cpu_fabric:stop(Fabric) end.

exact_actor_placement_and_binding_validation_test() ->
    Plan = hls_topology:from_module(ordered_egress_topology),
    Catalog = hls_debug_catalog:hardware(Plan, #{}, []),
    [Id | _] = hls_debug_catalog:actors(Catalog),
    {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
    ?assertEqual({placement, #{kind => direct}}, hls_debug:info(Actor, placement)),
    ?assertError({process_bindings, _, []}, hls_debug_catalog:cpu(Plan, #{})).
