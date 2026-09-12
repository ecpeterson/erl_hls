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

interleaved_placement_is_derived_from_scheduler_slots_test() ->
    Plan = hls_topology:from_module(phi_decoder_profile_topology),
    Check = fun(Shards) ->
        Catalog = hls_debug_catalog:hardware(Plan,
            maps:get(scheduler_groups, phi_decoder_profile_topology_dslx:profile(Shards)), []),
        ?assertEqual(36, length(hls_debug_catalog:actors(Catalog))),
        Slots = [begin
            {ok, Actor} = hls_debug_catalog:actor(Catalog, {family, phi_x, [X, Y]}),
            {placement, #{kind := scheduler, id := {2, phi_x, Shard}, slot := Slot}} =
                hls_debug:info(Actor, placement),
            ?assertEqual((X*3 + Y) rem Shards, Shard),
            ?assertEqual((X*3 + Y) div Shards, Slot),
            {Shard, Slot}
        end || X <- lists:seq(0, 2), Y <- lists:seq(0, 2)],
        ?assertEqual(9, length(lists:usort(Slots)))
    end,
    Check(2), Check(3).

exact_actor_placement_and_binding_validation_test() ->
    Plan = hls_topology:from_module(ordered_egress_topology),
    Catalog = hls_debug_catalog:hardware(Plan, #{}, []),
    [Id | _] = hls_debug_catalog:actors(Catalog),
    {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
    ?assertEqual({placement, #{kind => direct}}, hls_debug:info(Actor, placement)),
    ?assertError({process_bindings, _, []}, hls_debug_catalog:cpu(Plan, #{})).
