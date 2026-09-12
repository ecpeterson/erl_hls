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

snapshot_projection_binding_test() ->
    {Plan, Specs} = hls_actor_debug_dslx:fixture(phi),
    Projection = #{<<"banks">> := Banks} = xls_scheduler_debug:projection(Plan, Specs),
    Raw = [A#{<<"kind">> => <<"actor">>, <<"width">> => 26, <<"bank">> => Index,
        <<"module">> => Module, <<"phases">> => Phases, <<"failures">> => Failures} ||
        #{<<"index">> := Index, <<"module">> := Module, <<"phases">> := Phases,
            <<"actors">> := Actors, <<"failures">> := Failures} <- Banks, A <- Actors],
    Resources = [R#{<<"id">> => Id} || {Id, R} <- lists:enumerate(0, Raw)],
    Manifest = #{<<"actor_projection">> => Projection, <<"resources">> => Resources,
        <<"fingerprint">> => <<"fixture">>},
    Session = #{manifest => Manifest, resources => list_to_tuple(Resources)},
    Catalog = hls_debug_catalog:hardware(Plan, Specs, [], Session),
    lists:foreach(fun(Id) ->
        {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
        [{placement, #{index := Bank, slot := Slot}}, {observation, #{resource := ResourceId}},
            {capabilities, #{info := Fields, trace := false, counters := false, inspect_waits := false}}] =
            hls_debug:info(Actor, [placement, observation, capabilities]),
        #{<<"bank">> := Bank, <<"slot">> := Slot, <<"key">> := Key} = lists:nth(ResourceId+1, Resources),
        ?assertEqual(xls_scheduler_debug:actor_key(Id), Key),
        ?assertEqual([], [phase, initialized, enter_pending, failed, cycle] -- Fields),
        ?assertNot(lists:member(message_queue_len, Fields))
    end, hls_debug_catalog:actors(Catalog)),
    Wrong = maps:get(scheduler_groups, phi_decoder_profile_topology_dslx:profile(2)),
    ?assertError(actor_projection_mismatch, hls_debug_catalog:hardware(Plan, Wrong, [], Session)),
    [First | Rest] = Resources,
    Bad = Manifest#{<<"resources">> := [First#{<<"slot">> := 99} | Rest]},
    ?assertError(actor_resources_mismatch, hls_debug_catalog:hardware(Plan, Specs, [], Session#{manifest := Bad})),
    WrongOrigin = Manifest#{<<"resources">> := [First#{<<"failures">> := #{}} | Rest]},
    ?assertError(actor_resources_mismatch, hls_debug_catalog:hardware(Plan, Specs, [], Session#{manifest := WrongOrigin})),
    Duplicate = Manifest#{<<"resources">> := [First | Resources]},
    ?assertError(actor_resources_mismatch, hls_debug_catalog:hardware(Plan, Specs, [], Session#{manifest := Duplicate})).
