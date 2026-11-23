-module(xls_topology_mixed_tests).
-include_lib("eunit/include/eunit.hrl").

%% Checks placements preserve identity and real services.
-spec placements_preserve_identity_and_real_services_test() -> 'ok'.
placements_preserve_identity_and_real_services_test() ->
    lists:foreach(fun({Placement, Shared, Direct}) ->
        Text = generated(Placement),
        ?assertEqual(Shared, count(Text, <<"::SharedService<">>)),
        %% Every unborrowed publication credit must have matching batch storage.
        ?assertEqual(Shared, count(Text, <<"::ScheduledEffects, u32:2>">>)),
        ?assertEqual(Direct, count(Text, <<"::Service(">>)),
        ?assertEqual(Shared, count(Text, <<"effect_window::advance_client(">>)),
        ?assertNotEqual(nomatch, binary:match(Text, <<"actor_0_debug_out">>)),
        ?assertNotEqual(nomatch, binary:match(Text, <<"actor_2_debug_out">>)),
        case Placement of
            direct -> ?assertNotEqual(nomatch, binary:match(Text, <<"family_0_debug_out">>));
            _ -> ?assertEqual(nomatch, binary:match(Text, <<"family_0_debug_out">>))
        end
    end, [{direct, 0, 7}, {one, 1, 3}, {two, 2, 3}, {coalesced, 1, 2}]).

%% Checks family only partial placement uses both services.
-spec family_only_partial_placement_uses_both_services_test() -> 'ok'.
family_only_partial_placement_uses_both_services_test() ->
    Plan = hls_topology:normalize(#{version => 1, actors => #{},
        families => #{left => #{module => hls_topology_source_fixture, shape => [2, 3]},
            right => #{module => hls_topology_source_fixture, shape => [2, 3]}},
        routes => [], ingresses => [], startup => [],
        externals => [{values, out, [message]}],
        route_relations => [{{left, out}, [{family, right, {translate, [0, 0], wrap}}]},
            {{right, out}, [{external, values}]}]}),
    Specs = #{left => #{members => [{family, left}],
        state_storage => block_ram, mailbox_storage => block_ram}},
    Text = iolist_to_binary(xls_fabric_topology_dslx:emit(Plan, profile(Specs))),
    ?assertEqual(1, count(Text, <<"::SharedService<">>)),
    ?assertEqual(6, count(Text, <<"::Service(">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"family_0_debug_out">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"family_1_debug_out">>)).

%% Checks exact only scheduler group uses same backend.
-spec exact_only_scheduler_group_uses_same_backend_test() -> 'ok'.
exact_only_scheduler_group_uses_same_backend_test() ->
    Plan = hls_topology:normalize(#{version => 1,
        actors => #{source => hls_topology_source_fixture, sink => hls_topology_source_fixture},
        families => #{}, ingresses => [], route_relations => [], startup => [],
        externals => [{values, out, [message]}],
        routes => [{{source, out}, [{actor, sink}]}, {{sink, out}, [{external, values}]}]}),
    Specs = #{source => #{members => [{actor, source}],
        state_storage => block_ram, mailbox_storage => block_ram}},
    Text = iolist_to_binary(xls_fabric_topology_dslx:emit(Plan, profile(Specs))),
    ?assertEqual(1, count(Text, <<"::SharedService<">>)),
    ?assertEqual(1, count(Text, <<"::Service(">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"actor_0_debug_out">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"actor_1_debug_out">>)),
    %% Supplying the placement key selects the same backend even after the
    %% final group is removed; no unrelated profile keys need to disappear.
    SharedProfile = (profile(Specs))#{mailbox_debug := false},
    DirectProfile = SharedProfile#{scheduler_groups := #{}},
    DirectText = iolist_to_binary(xls_fabric_topology_dslx:emit(Plan, DirectProfile)),
    ?assertEqual(0, count(DirectText, <<"::SharedService<">>)),
    ?assertEqual(2, count(DirectText, <<"::Service(">>)),
    ?assertNotEqual(nomatch, binary:match(DirectText, <<"actor_0_debug_out">>)),
    ?assertNotEqual(nomatch, binary:match(DirectText, <<"actor_1_debug_out">>)),
    ?assertEqual(#{hls_topology_source_fixture =>
        #{frame_payload_words => 3, shared_service => ordinary, direct_actor_debug => true}},
        xls_fabric_topology_dslx:artifact_requirements(Plan, DirectProfile)).

%% Checks same artifact can supply both physical services.
-spec same_artifact_can_supply_both_physical_services_test() -> 'ok'.
same_artifact_can_supply_both_physical_services_test() ->
    {Plan, Specs} = hls_mixed_topology_dslx:fixture(one),
    Requirements = xls_fabric_topology_dslx:artifact_requirements(Plan, profile(Specs)),
    ?assertEqual(#{frame_payload_words => 3, shared_service => ordinary, direct_actor_debug => true,
        mailbox_debug => true}, maps:get(hls_mixed_worker, Requirements)),
    ?assertEqual(#{frame_payload_words => 3, shared_service => ordinary, direct_actor_debug => true},
        maps:get(hls_mixed_source, Requirements)),
    {Coalesced, Groups} = hls_mixed_topology_dslx:fixture(coalesced),
    ?assertEqual(#{frame_payload_words => 3, shared_service => ordinary, mailbox_debug => true},
        maps:get(hls_mixed_worker,
            xls_fabric_topology_dslx:artifact_requirements(Coalesced, profile(Groups)))).

%% Checks shared destination slots and return credits are distinct.
-spec shared_destination_slots_and_return_credits_are_distinct_test() -> 'ok'.
shared_destination_slots_and_return_credits_are_distinct_test() ->
    Text = generated(one),
    %% Four family mailbox destinations are four producer inputs; the fifth
    %% input is exclusively the executor's effect credit return.
    ?assertNotEqual(nomatch, binary:match(Text,
        <<"chan<hls_mixed_worker::ScheduledRequest, CHANNEL_DEPTH>[u32:5]">>)),
    lists:foreach(fun(Slot) ->
        Needle = iolist_to_binary(["hls_mixed_worker::ScheduledRequest { slot: u32:",
            integer_to_list(Slot), ", frame: effect.frame"]),
        ?assertNotEqual(nomatch, binary:match(Text, Needle))
    end, lists:seq(0, 3)),
    ?assertNotEqual(nomatch, binary:match(Text,
        <<"scheduler_0_egress_c, scheduler_0_requests_p[u32:4]">>)).

%% Checks aliased ports keep one physical lane.
-spec aliased_ports_keep_one_physical_lane_test() -> 'ok'.
aliased_ports_keep_one_physical_lane_test() ->
    Text = generated(one),
    %% Each recipient is selected by either source port on the same send.
    ?assertEqual(5, count(Text, <<
        "effect.port == hls_mixed_source::OutputPort::FIRST || "
        "effect.port == hls_mixed_source::OutputPort::SECOND"
    >>)).

%% Checks one global window covers direct paths between groups.
-spec one_global_window_covers_direct_paths_between_groups_test() -> 'ok'.
one_global_window_covers_direct_paths_between_groups_test() ->
    Text = generated(two),
    ?assertEqual(1, count(Text, <<"spawn effect_window::Arbiter<u32:2>">>)),
    ?assertEqual(2, count(Text, <<"::SharedService<">>)).

%% Checks direct feedback paths keep one window.
-spec direct_feedback_paths_keep_one_window_test() -> 'ok'.
direct_feedback_paths_keep_one_window_test() ->
    {Plan, Specs} = hls_mixed_topology_dslx:fixture(two),
    Profile = (profile(Specs))#{effect_window_partition => weak_components},
    %% There is no immediate shared-to-shared route: both workers reply through
    %% the direct collector and source. Dropping those vertices splits them.
    ?assertEqual(generated(two), iolist_to_binary(xls_fabric_topology_dslx:emit(Plan, Profile))).

%% Checks no shared actors need no window.
-spec no_shared_actors_need_no_window_test() -> 'ok'.
no_shared_actors_need_no_window_test() ->
    {Plan, Specs} = hls_mixed_topology_dslx:fixture(direct),
    Profile = (profile(Specs))#{effect_window_partition => weak_components},
    Text = iolist_to_binary(xls_fabric_topology_dslx:emit(Plan, Profile)),
    ?assertEqual(0, count(Text, <<"spawn effect_window::Arbiter">>)).

%% Checks disconnected mixed components use local grant indices.
-spec disconnected_mixed_components_use_local_grant_indices_test() -> 'ok'.
disconnected_mixed_components_use_local_grant_indices_test() ->
    {Plan, Specs} = hls_mixed_topology_dslx:fixture({components, weak_components}),
    Profile = (profile(Specs))#{effect_window_partition => weak_components},
    Text = iolist_to_binary(xls_fabric_topology_dslx:emit(Plan, Profile)),
    ?assertEqual(2, count(Text, <<"spawn effect_window::Arbiter<u32:2>">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"domain 0: schedulers 0, 2.">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"domain 1: schedulers 1, 3.">>)),
    ?assertEqual(0, count(Text, <<"_request_p[u32:3]">>)),
    Global = iolist_to_binary(xls_fabric_topology_dslx:emit(Plan, profile(Specs))),
    ?assertEqual(1, count(Global, <<"spawn effect_window::Arbiter<u32:4>">>)).

%% Checks shared executor joins logically disconnected components.
-spec shared_executor_joins_logically_disconnected_components_test() -> 'ok'.
shared_executor_joins_logically_disconnected_components_test() ->
    {Plan, Specs} = hls_mixed_topology_dslx:fixture({components, weak_components}),
    #{even := Even, even_peer := Peer} = Specs,
    Joined = (maps:remove(even_peer, Specs))#{even := Even#{members :=
        maps:get(members, Even) ++ maps:get(members, Peer)}},
    Text = iolist_to_binary(xls_fabric_topology_dslx:emit(Plan,
        (profile(Joined))#{effect_window_partition => weak_components})),
    ?assertEqual(1, count(Text, <<"spawn effect_window::Arbiter<u32:3>">>)).

%% Checks exact only components ignore external sink fan in.
-spec exact_only_components_ignore_external_sink_fan_in_test() -> 'ok'.
exact_only_components_ignore_external_sink_fan_in_test() ->
    Plan = hls_topology:normalize(#{version => 1, families => #{},
        actors => maps:from_keys([a, b, c, relay], hls_topology_source_fixture),
        ingresses => [], route_relations => [], startup => [],
        externals => [{values, out, [message]}],
        routes => [{{a, out}, [{actor, relay}]}, {{relay, out}, [{actor, b}]},
            {{b, out}, [{external, values}]}, {{c, out}, [{external, values}]}]}),
    Groups = maps:from_list([{Id, #{members => [{actor, Id}],
        state_storage => block_ram, mailbox_storage => block_ram}} || Id <- [a, b, c]]),
    Text = iolist_to_binary(xls_fabric_topology_dslx:emit(Plan,
        (profile(Groups))#{effect_window_partition => weak_components})),
    ?assertEqual(1, count(Text, <<"spawn effect_window::Arbiter<u32:2>">>)),
    ?assertEqual(1, count(Text, <<"spawn effect_window::Arbiter<u32:1>">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"domain 0: schedulers 0, 1.">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"domain 1: schedulers 2.">>)).

%% Checks unsupported physical contracts fail explicitly.
-spec unsupported_physical_contracts_fail_explicitly_test() -> 'ok'.
unsupported_physical_contracts_fail_explicitly_test() ->
    {Plan, Specs} = hls_mixed_topology_dslx:fixture(one),
    Profile = profile(Specs),
    ?assertError({unsupported_instance_section, reduction_placements},
        xls_fabric_topology_dslx:emit(Plan, Profile#{reduction_placements => #{workers => source_fragments}})).

%% Checks scheduled startup must fit reserved mailboxes.
-spec scheduled_startup_must_fit_reserved_mailboxes_test() -> 'ok'.
scheduled_startup_must_fit_reserved_mailboxes_test() ->
    {Plan, Specs} = hls_mixed_topology_dslx:fixture(one),
    #{startup := Startup} = Plan,
    Frames = [{configure, 0} || _ <- lists:seq(1, 20)],
    Changed = [case Item of
        #{target := {workers, 0, 0}} -> Item#{messages := Frames};
        _ -> Item
    end || Item <- Startup],
    ?assertException(error, {scheduler_startup_capacity, {workers, 0, 0}, 20, _},
        xls_fabric_topology_dslx:emit(Plan#{startup := Changed}, profile(Specs))).

%% Checks stale connectivity caches are rejected before materializing.
-spec stale_connectivity_caches_are_rejected_before_materializing_test() -> 'ok'.
stale_connectivity_caches_are_rejected_before_materializing_test() ->
    {Plan, Specs} = hls_mixed_topology_dslx:fixture(one),
    lists:foreach(fun(Key) ->
        Expected = maps:get(Key, Plan),
        Reason = case Key of
            lanes -> inconsistent_dslx_plan_lanes;
            lane_relations -> inconsistent_dslx_family_plan_lanes
        end,
        ?assertError({Reason, Expected, []},
            xls_fabric_topology_dslx:emit(Plan#{Key := []}, profile(Specs)))
    end, [lanes, lane_relations]).

%% Checks physical options do not change semantic family size.
-spec physical_options_do_not_change_semantic_family_size_test() -> 'ok'.
physical_options_do_not_change_semantic_family_size_test() ->
    {Plan, Specs} = hls_mixed_topology_dslx:fixture(one),
    Before = term_to_binary(Plan),
    _ = xls_fabric_topology_dslx:emit(Plan, profile(Specs)),
    ?assertEqual(Before, term_to_binary(Plan)),
    ?assertEqual(1, length(maps:get(families, Plan))),
    ?assertEqual(3, length(maps:get(actors, Plan))).

%% Renders the fixture and returns its generated text for structural assertions.
-spec generated('coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {term(),term()}}}) -> binary().
generated(Placement) ->
    {Plan, Specs} = hls_mixed_topology_dslx:fixture(Placement),
    iolist_to_binary(xls_fabric_topology_dslx:emit(Plan, profile(Specs))).
%% Selects bounded storage and observation settings for the test deployment.
-spec profile(map()) -> map().
profile(Specs) ->
    #{name => mixed, channel_depth => 1, actor_egress_depth => 0,
        scheduler_groups => Specs, direct_actor_debug => true,
        mailbox_debug => map_size(Specs) > 0}.
%% Counts nonoverlapping occurrences of a generated structural marker.
-spec count(iodata(), iodata()) -> non_neg_integer().
count(Text, Needle) -> length(binary:matches(Text, Needle)).
