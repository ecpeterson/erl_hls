-module(hls_debug_catalog_shared_tests).
-include_lib("eunit/include/eunit.hrl").


%% Checks interleaved placement is derived from scheduler slots.
-spec interleaved_placement_is_derived_from_scheduler_slots_test() -> 'ok'.
interleaved_placement_is_derived_from_scheduler_slots_test() ->
    Plan = hls_topology:from_module(phi_decoder_profile_topology),
    Check = fun(Shards) ->
        Catalog = hls_shared_debug_catalog:hardware(Plan,
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

%% Checks snapshot projection binding.
-spec snapshot_projection_binding_test() -> 'ok'.
snapshot_projection_binding_test() ->
    {Plan, Specs} = hls_actor_debug_dslx:fixture(phi),
    Projection = #{<<"banks">> := Banks} = hls_actor_debug_dslx:projection(phi),
    Raw = [maps:merge(A#{<<"kind">> => <<"actor">>, <<"width">> => 26, <<"bank">> => Index,
        <<"module">> => Module, <<"phases">> => Phases, <<"failures">> => Failures},
        case Bank of
            #{<<"reduction">> := R = #{<<"width">> := W}} -> #{<<"reduction">> => R, <<"width">> => 56+W};
            _ -> #{}
        end) ||
        #{<<"index">> := Index, <<"module">> := Module, <<"phases">> := Phases,
            <<"actors">> := Actors, <<"failures">> := Failures} = Bank <- Banks, A <- Actors],
    Resources = [R#{<<"id">> => Id} || {Id, R} <- lists:enumerate(0, Raw)],
    Manifest = #{<<"actor_projection">> => Projection, <<"resources">> => Resources,
        <<"fingerprint">> => <<"fixture">>},
    Session = #{manifest => Manifest, resources => list_to_tuple(Resources)},
    Catalog = hls_shared_debug_catalog:hardware(Plan, Specs, [], Session),
    lists:foreach(fun(Id) ->
        {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
        [{placement, #{index := Bank, slot := Slot}}, {observation, #{resource := ResourceId}},
            {capabilities, #{info := Fields, trace := false, counters := false, inspect_waits := false}}] =
            hls_debug:info(Actor, [placement, observation, capabilities]),
        #{<<"bank">> := Bank, <<"slot">> := Slot, <<"key">> := Key} = lists:nth(ResourceId+1, Resources),
        ?assertEqual(xls_actor_debug:actor_key(Id), Key),
        ?assertEqual([], [phase, initialized, enter_pending, failed, cycle] -- Fields),
        ?assertNot(lists:member(message_queue_len, Fields))
    end, hls_debug_catalog:actors(Catalog)),
    [Bank | OtherBanks] = Banks,
    Failures = maps:get(<<"failures">>, Bank),
    [{Code, Origin} | _] = [{C, O} || {C, O = #{<<"file">> := _}} <- maps:to_list(Failures)],
    lists:foreach(fun(BadFailures) ->
        BadProjection = Projection#{<<"banks">> :=
            [Bank#{<<"failures">> := BadFailures} | OtherBanks]},
        ?assertError(actor_projection_mismatch,
            xls_scheduler_debug:validate(Plan, Specs, BadProjection))
    end, [Failures#{Code := Origin#{<<"file">> := <<"absent.erl">>}},
        (maps:remove(Code, Failures))#{<<"65535">> => Origin}]),
    Wrong = maps:get(scheduler_groups, phi_decoder_profile_topology_dslx:profile(2)),
    ?assertError(actor_projection_mismatch, hls_shared_debug_catalog:hardware(Plan, Wrong, [], Session)),
    [First | Rest] = Resources,
    Bad = Manifest#{<<"resources">> := [First#{<<"slot">> := 99} | Rest]},
    ?assertError(actor_resources_mismatch, hls_shared_debug_catalog:hardware(Plan, Specs, [], Session#{manifest := Bad})),
    WrongOrigin = Manifest#{<<"resources">> := [First#{<<"failures">> := #{}} | Rest]},
    ?assertError(actor_resources_mismatch, hls_shared_debug_catalog:hardware(Plan, Specs, [], Session#{manifest := WrongOrigin})),
    Duplicate = Manifest#{<<"resources">> := [First | Resources]},
    ?assertError(actor_resources_mismatch, hls_shared_debug_catalog:hardware(Plan, Specs, [], Session#{manifest := Duplicate})).
