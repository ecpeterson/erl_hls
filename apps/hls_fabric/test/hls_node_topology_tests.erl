-module(hls_node_topology_tests).
-include_lib("eunit/include/eunit.hrl").

%% Retained scheduler bindings preserve selector, payload and per-actor slot encoding.
-spec placement_and_cast_codec_test() -> ok.
placement_and_cast_codec_test() ->
    {Plan, Specs, Endpoints} = hls_actor_pid_dslx:fixture(),
    #{actors := Actors, groups := Groups} = hls_node_topology:normalize(Plan, Specs, Endpoints),
    ?assertEqual(ok, hls_node_binding:validate(#{actors => Actors, groups => Groups})),
    ?assertEqual([#{id => even, index => 0, module => hls_actor_pid_fixture,
        slot_count => 2, endpoint => 7},
        #{id => odd, index => 1, module => hls_actor_pid_fixture,
            slot_count => 2, endpoint => 8}], Groups),
    ?assertEqual(lists:seq(0, 3), [T || #{target := T} <- Actors]),
    ?assertEqual([{family, cells, [X, Y]} || X <- [0, 1], Y <- [0, 1]],
        [Id || #{identity := Id} <- Actors]),
    Placements = hls_scheduler_plan:placements(hls_scheduler_plan:normalize(Plan, Specs)),
    Tag = hls_actor_pid_fixture:pack_tag(work),
    lists:foreach(fun(Actor = #{identity := Id, placement := Placement,
            slot := Slot, endpoint := Endpoint, schemas := Schemas}) ->
        ?assertEqual(maps:get(Id, Placements), Placement),
        #{id := Group} = Placement,
        ?assertEqual(maps:get(Group, Endpoints), Endpoint),
        ?assertEqual([work], maps:keys(Schemas)),
        ?assertMatch(#{work := #{selector := Tag, width := 32, codec := _}}, Schemas),
        ?assertEqual({{Tag, 255, 1}, <<Slot:32/little, 16#01234567:32/little>>},
            hls_node_binding:encode_cast(Actor, {work, 16#01234567}))
    end, Actors).

stable_logical_ids_across_placement_test() ->
    {Plan, Specs, Endpoints} = hls_actor_pid_dslx:fixture(),
    #{actors := Before} = hls_node_topology:normalize(Plan, Specs, Endpoints),
    Combined = #{all => #{members => [{family, cells}],
        state_storage => block_ram, mailbox_storage => block_ram}},
    #{actors := After} = hls_node_topology:normalize(Plan, Combined, #{all => 42}),
    Identity = fun(Actors) -> [{I, T} || #{identity := I, target := T} <- Actors] end,
    ?assertEqual(Identity(Before), Identity(After)),
    ?assertEqual([0, 1, 2, 3], lists:sort([S || #{slot := S} <- After])),
    ?assertEqual([42], lists:usort([E || #{endpoint := E} <- After])).

endpoint_bindings_test() ->
    {Plan, Specs, Endpoints} = hls_actor_pid_dslx:fixture(),
    ?assertError({scheduler_endpoints, [odd], []},
        hls_node_topology:normalize(Plan, Specs, maps:remove(odd, Endpoints))),
    ?assertError({scheduler_endpoints, [], [unused]},
        hls_node_topology:normalize(Plan, Specs, Endpoints#{unused => 9})),
    ?assertError({duplicate_endpoints, [7]},
        hls_node_topology:normalize(Plan, Specs, #{even => 7, odd => 7})),
    ?assertError({badmatch, false},
        hls_node_topology:normalize(Plan, Specs, Endpoints#{odd := 65536})),
    ?assertError({unscheduled_actors, [{family, cells}]},
        hls_node_topology:normalize(Plan, #{}, #{})).

%% Retained runtime validation rejects endpoints, identities and slots inconsistent with the deployment.
-spec descriptor_coherence_test() -> ok.
descriptor_coherence_test() ->
    {Plan, Specs, Endpoints} = hls_actor_pid_dslx:fixture(),
    Deployment = #{actors := [A, B | Rest], groups := [G | Groups]} =
        hls_node_topology:normalize(Plan, Specs, Endpoints),
    #{identity := Id, placement := Placement} = A,
    ?assertError({actor_binding, Id}, hls_node_binding:validate(
        Deployment#{actors := [A#{endpoint := 1}, B | Rest]})),
    ?assertError({actor_binding, Id}, hls_node_binding:validate(
        Deployment#{actors := [A#{kind := application}, B | Rest]})),
    ?assertError({actor_binding, Id}, hls_node_binding:validate(
        Deployment#{actors := [A#{module := regsvc}, B | Rest]})),
    ?assertError({actor_binding, Id}, hls_node_binding:validate(
        Deployment#{actors := [A#{placement := Placement#{slot := 1}}, B | Rest]})),
    ?assertError({actor_targets, [0, 0, 2, 3]}, hls_node_binding:validate(
        Deployment#{actors := [A, B#{target := 0} | Rest]})),
    ?assertError({duplicate_actor_identities, [Id]}, hls_node_binding:validate(
        Deployment#{actors := [A, B#{identity := Id} | Rest]})),
    ?assertError({duplicate_actor_slots, [{7, 0}]}, hls_node_binding:validate(
        Deployment#{actors := [A, (maps:merge(B, maps:with(
            [endpoint, slot, placement], A))) | Rest]})),
    ?assertError({actor_slots, even}, hls_node_binding:validate(
        Deployment#{groups := [G#{slot_count := 3} | Groups]})),
    ?assertError({duplicate_endpoints, [7]}, hls_node_binding:validate(
        Deployment#{groups := [G | [Other#{endpoint := 7} || Other <- Groups]]})).

%% Retained codecs admit only declared cast schemas and enforce their checked value bounds.
-spec unsupported_cast_test() -> ok.
unsupported_cast_test() ->
    {Plan, Specs, Endpoints} = hls_actor_pid_dslx:fixture(),
    #{actors := [Actor | _]} = hls_node_topology:normalize(Plan, Specs, Endpoints),
    %% A public output record has a valid generated codec, but no cast dispatch.
    ?assertError({invalid_request, cast, report},
        hls_node_binding:encode_cast(Actor, {report, 12})),
    ?assertError({invalid_request, cast, unknown},
        hls_node_binding:encode_cast(Actor, {unknown, 12})),
    ?assertError(badarg, hls_node_binding:encode_cast(Actor, not_a_record)),
    ?assertError(badarg, hls_node_binding:encode_cast(Actor, {work, -1})).

debug_manifest_checked_before_catalog_test() ->
    %% Even a caller-supplied plan cannot bypass the device's manifest check.
    Client = spawn(fun() ->
        receive {'$gen_call', From, {query, 16#10, <<>>}} ->
            gen_server:reply(From, {ok, <<5:32/little, 1:32/little,
                1:32/little, 0:32/little, 0:32/little, 0:256>>})
        end
    end),
    try
        ?assertEqual({error, topology_manifest_mismatch},
            hls_node_topology:bind_debug(unused, unused, Client, #{}))
    after exit(Client, kill) end.
