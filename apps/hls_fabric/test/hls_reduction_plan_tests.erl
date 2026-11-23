-module(hls_reduction_plan_tests).

-include_lib("eunit/include/eunit.hrl").

%% Checks valid source fragment plan is deterministic.
-spec valid_source_fragment_plan_is_deterministic_test() -> 'ok'.
valid_source_fragment_plan_is_deterministic_test() ->
    Spec = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Topology = hls_topology:normalize(Spec),
    Scheduler = scheduler_plan(Topology, [reducer, source]),
    Expected = #{
        placements => [#{
            kind => source_fragments,
            family => reducer,
            module => hls_topology_source_fragment_fixture,
            shape => [3, 3],
            scheduler_groups => [reducer],
            population => 2,
            sites => [#{
                id => 0,
                phase => gathering,
                name => sum,
                population => #{mode => count, size => 2},
                contribution_schema => message
            }],
            fragments => [
                #{
                    ordinal => 0,
                    port => north,
                    offset => [0, -1],
                    inverse_offset => [0, 1],
                    inverse_ordinal => 1
                },
                #{
                    ordinal => 1,
                    port => south,
                    offset => [0, 1],
                    inverse_offset => [0, -1],
                    inverse_ordinal => 0
                }
            ],
            fragment_capacity => 2,
            semantic_assumptions => [
                coherent_window_sequence,
                unrelated_mail_commutes_with_completion
            ]
        }],
        artifact_requirements => #{
            hls_topology_source_fragment_fixture => #{
                shared_service => aggregate_only
            },
            hls_topology_source_fixture => #{shared_service => ordinary}
        }
    },
    ?assertEqual(Expected, hls_reduction_plan:normalize(
        Topology, Scheduler, #{reducer => source_fragments}
    )),
    ?assertEqual(Expected, hls_reduction_plan:normalize(
        Topology, Scheduler, #{reducer => source_fragments}
    )).

%% Checks artifact requirements are an explicit query.
-spec artifact_requirements_are_an_explicit_query_test() -> 'ok'.
artifact_requirements_are_an_explicit_query_test() ->
    {Topology, Scheduler} = closed_plan([3, 3]),
    Plan = hls_reduction_plan:normalize(
        Topology, Scheduler, #{reducer => source_fragments}
    ),
    ?assertEqual(
        maps:get(artifact_requirements, Plan),
        hls_reduction_plan:artifact_requirements(Plan)
    ).

%% Checks empty placement keeps shared artifacts ordinary.
-spec empty_placement_keeps_shared_artifacts_ordinary_test() -> 'ok'.
empty_placement_keeps_shared_artifacts_ordinary_test() ->
    {Topology, Scheduler} = closed_plan([3, 3]),
    Plan = hls_reduction_plan:normalize(Topology, Scheduler, #{}),
    ?assertEqual([], maps:get(placements, Plan)),
    ?assertEqual(#{
        hls_topology_source_fragment_fixture => #{
            shared_service => ordinary
        },
        hls_topology_source_fixture => #{shared_service => ordinary}
    }, hls_reduction_plan:artifact_requirements(Plan)).

%% Checks placement spec is closed.
-spec placement_spec_is_closed_test() -> any().
placement_spec_is_closed_test() ->
    {Topology, Scheduler} = closed_plan([3, 3]),
    assert_plan_error(unsupported_reduction_placement, fun() ->
        hls_reduction_plan:normalize(
            Topology, Scheduler, #{reducer => joined}
        )
    end),
    assert_plan_error(source_fragment_unknown_family, fun() ->
        hls_reduction_plan:normalize(
            Topology, Scheduler, #{missing => source_fragments}
        )
    end),
    assert_plan_error(source_fragment_requires_reductions, fun() ->
        hls_reduction_plan:normalize(
            Topology, Scheduler, #{source => source_fragments}
        )
    end).

%% Checks source fragment family must be scheduled.
-spec source_fragment_family_must_be_scheduled_test() -> any().
source_fragment_family_must_be_scheduled_test() ->
    Spec = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Topology = hls_topology:normalize(Spec),
    Scheduler = scheduler_plan(Topology, [source]),
    assert_plan_error(source_fragment_family_not_fully_scheduled, fun() ->
        hls_reduction_plan:normalize(
            Topology, Scheduler, #{reducer => source_fragments}
        )
    end).

%% Checks interleaved scheduler partitions cover one placement.
-spec interleaved_scheduler_partitions_cover_one_placement_test() -> 'ok'.
interleaved_scheduler_partitions_cover_one_placement_test() ->
    Topology = hls_topology:normalize(closed_topology(
        hls_topology_source_fragment_fixture,
        [3, 3]
    )),
    Scheduler = hls_scheduler_plan:normalize(Topology, #{
        reducer_even => group_spec([
            {family, reducer, {interleaved, 0, 2}}
        ]),
        reducer_odd => group_spec([
            {family, reducer, {interleaved, 1, 2}}
        ]),
        source => group_spec([{family, source}])
    }),
    Plan = hls_reduction_plan:normalize(
        Topology,
        Scheduler,
        #{reducer => source_fragments}
    ),
    [Placement] = maps:get(placements, Plan),
    ?assertEqual(
        [reducer_even, reducer_odd],
        maps:get(scheduler_groups, Placement)
    ).

%% Checks branching suffix does not invalidate source capture.
-spec branching_suffix_does_not_invalidate_source_capture_test() -> 'ok'.
branching_suffix_does_not_invalidate_source_capture_test() ->
    Module = hls_reduction_plan_branch_fixture,
    Spec = closed_topology(Module, [3, 3]),
    Topology = hls_topology:normalize(Spec#{route_relations =>
        maps:get(route_relations, Spec) ++
            [{{reducer, alternate}, [{external, reports}]}]}),
    Plan = hls_reduction_plan:normalize(Topology,
        scheduler_plan(Topology, [reducer, source]), #{reducer => source_fragments}),
    [Placement] = maps:get(placements, Plan),
    ?assertEqual([north, south], [maps:get(port, F)
        || F <- maps:get(fragments, Placement)]),
    ?assertEqual(3, hls_actor_interface:max_entry_effects(
        hls_actor_interface:from_module(Module))),
    %% Exercise both layout arms in the aggregate artifact's prefix renderer.
    Generated = iolist_to_binary(xls_scheduler_actor:to_xls(
        "apps/hls_fabric/test/hls_reduction_plan_branch_fixture.erl", #{shared_service => aggregate_only})),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"match scheduled.effects.layout">>)).

%% Checks reduction prefix must have the complete population.
-spec reduction_prefix_must_have_the_complete_population_test() -> any().
reduction_prefix_must_have_the_complete_population_test() ->
    assert_fixture_error(
        hls_reduction_plan_short_fixture,
        source_fragment_short_prefix
    ).

%% Checks reduction open must be unconditional for source capture.
-spec reduction_open_must_be_unconditional_for_source_capture_test() -> any().
reduction_open_must_be_unconditional_for_source_capture_test() ->
    assert_fixture_error(hls_reduction_plan_optional_fixture,
        source_fragment_conditional_open).

%% Checks reduction prefix must be unconditional.
-spec reduction_prefix_must_be_unconditional_test() -> any().
reduction_prefix_must_be_unconditional_test() ->
    assert_fixture_error(
        hls_reduction_plan_conditional_fixture,
        source_fragment_conditional_prefix
    ).

%% Checks reduction prefix must use the contribution schema.
-spec reduction_prefix_must_use_the_contribution_schema_test() -> any().
reduction_prefix_must_use_the_contribution_schema_test() ->
    assert_fixture_error(
        hls_reduction_plan_wrong_schema_fixture,
        source_fragment_prefix_schema
    ).

%% Checks selected contribution must be source transportable.
-spec selected_contribution_must_be_source_transportable_test() -> 'ok'.
selected_contribution_must_be_source_transportable_test() ->
    Reason = assert_fixture_error(
        hls_reduction_plan_nontransportable_fixture,
        source_fragment_nontransportable_contribution
    ),
    ?assertEqual(
        {source_fragment_nontransportable_contribution,
            reducer, 0, message},
        Reason
    ).

%% Checks captured contribution must cover the entire schema.
-spec captured_contribution_must_cover_the_entire_schema_test() -> 'ok'.
captured_contribution_must_cover_the_entire_schema_test() ->
    Reason = assert_fixture_error(
        hls_reduction_plan_guarded_fixture,
        source_fragment_nonexhaustive_contribution
    ),
    ?assertEqual(
        {source_fragment_nonexhaustive_contribution,
            reducer, 0, message},
        Reason
    ).

%% Checks captured contribution pattern must be irrefutable.
-spec captured_contribution_pattern_must_be_irrefutable_test() -> 'ok'.
captured_contribution_pattern_must_be_irrefutable_test() ->
    Reason = assert_fixture_error(
        hls_reduction_plan_refutable_fixture,
        source_fragment_nonexhaustive_contribution
    ),
    ?assertEqual(
        {source_fragment_nonexhaustive_contribution,
            reducer, 0, message},
        Reason
    ).

%% Checks reduction prefix cannot exceed the population.
-spec reduction_prefix_cannot_exceed_the_population_test() -> any().
reduction_prefix_cannot_exceed_the_population_test() ->
    assert_fixture_error(
        hls_reduction_plan_excess_fixture,
        source_fragment_excess_prefix
    ).

%% Checks reduction sites must have one route pattern.
-spec reduction_sites_must_have_one_route_pattern_test() -> any().
reduction_sites_must_have_one_route_pattern_test() ->
    Spec = four_lane_topology(hls_reduction_plan_inconsistent_fixture),
    assert_spec_error(Spec, source_fragment_inconsistent_site).

%% Checks equal size count and member sites share one source fragment plane.
-spec equal_size_count_and_member_sites_share_one_source_fragment_plane_test() -> 'ok'.
equal_size_count_and_member_sites_share_one_source_fragment_plane_test() ->
    Spec = two_lane_topology(
        hls_reduction_plan_population_fixture,
        [3, 3]
    ),
    Topology = hls_topology:normalize(Spec),
    Scheduler = scheduler_plan(Topology, [reducer]),
    Plan = hls_reduction_plan:normalize(
        Topology, Scheduler, #{reducer => source_fragments}
    ),
    [Placement] = maps:get(placements, Plan),
    ?assertEqual(2, maps:get(population, Placement)),
    ?assertEqual(
        [
            #{mode => count, size => 2},
            #{mode => members, size => 2, members => [0, 1]}
        ],
        [maps:get(population, Site) || Site <- maps:get(sites, Placement)]
    ).

%% Checks captured route must not cross families.
-spec captured_route_must_not_cross_families_test() -> any().
captured_route_must_not_cross_families_test() ->
    Spec0 = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Spec = replace_relation(Spec0, {reducer, north},
        {{reducer, north}, [
            {family, source, {translate, [0, -1], wrap}}
        ]}),
    assert_spec_error(Spec, source_fragment_effect_relation).

%% Checks captured route must be direct.
-spec captured_route_must_be_direct_test() -> any().
captured_route_must_be_direct_test() ->
    Spec0 = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Spec = replace_relation(Spec0, {reducer, north},
        {{reducer, north}, buffered, [
            {family, reducer, {translate, [0, -1], wrap}},
            {external, messages}
        ]}),
    assert_spec_error(Spec, source_fragment_effect_relation).

%% Checks captured route must not fan out.
-spec captured_route_must_not_fan_out_test() -> any().
captured_route_must_not_fan_out_test() ->
    Spec0 = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Spec = replace_relation(Spec0, {reducer, north},
        {{reducer, north}, buffered, [
            {family, reducer, {translate, [0, -1], wrap}},
            {family, reducer, {translate, [-1, 0], wrap}}
        ]}),
    assert_spec_error(Spec, source_fragment_effect_relation).

%% Checks captured port cannot survive after the prefix.
-spec captured_port_cannot_survive_after_the_prefix_test() -> any().
captured_port_cannot_survive_after_the_prefix_test() ->
    Spec = closed_topology(
        hls_topology_source_fragment_port_fixture,
        [3, 3]
    ),
    assert_spec_error(Spec, source_fragment_captured_port_reused).

%% Checks ordinary self route cannot overtake a fragment batch.
-spec ordinary_self_route_cannot_overtake_a_fragment_batch_test() -> any().
ordinary_self_route_cannot_overtake_a_fragment_batch_test() ->
    Spec0 = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Spec = replace_relation(Spec0, {reducer, report},
        {{reducer, report}, [
            {family, reducer, {translate, [0, 0], wrap}}
        ]}),
    assert_spec_error(Spec, source_fragment_uncaptured_self_relation).

%% Checks ordinary relation cannot leak a contribution.
-spec ordinary_relation_cannot_leak_a_contribution_test() -> any().
ordinary_relation_cannot_leak_a_contribution_test() ->
    Spec0 = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Spec = replace_relation(Spec0, {source, out},
        {{source, out}, [
            {family, reducer, {translate, [0, 0], wrap}}
        ]}),
    assert_spec_error(Spec, source_fragment_uncaptured_contribution_relation).

%% Checks ingress cannot leak a contribution.
-spec ingress_cannot_leak_a_contribution_test() -> any().
ingress_cannot_leak_a_contribution_test() ->
    Spec0 = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Spec = Spec0#{ingresses := [
        {contributions, {rectangle, [3, 3]}, [
            {values, [message], [
                {family, reducer, {embed, [1, 1], [0, 0]}}
            ]}
        ]}
    ]},
    assert_spec_error(Spec, source_fragment_contribution_ingress).

%% Checks startup cannot leak a contribution.
-spec startup_cannot_leak_a_contribution_test() -> any().
startup_cannot_leak_a_contribution_test() ->
    Spec0 = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Spec = Spec0#{startup := [
        {{reducer, 0, 0}, [{message, 7}]}
    ]},
    assert_spec_error(Spec, source_fragment_contribution_startup).

%% Checks opaque startup to selected family is rejected.
-spec opaque_startup_to_selected_family_is_rejected_test() -> any().
opaque_startup_to_selected_family_is_rejected_test() ->
    Spec0 = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Spec = Spec0#{startup := [
        {{reducer, 0, 0}, [opaque_message]}
    ]},
    assert_spec_error(Spec, source_fragment_untyped_startup).

%% Checks similarly named exact actor startup is ignored.
-spec similarly_named_exact_actor_startup_is_ignored_test() -> 'ok'.
similarly_named_exact_actor_startup_is_ignored_test() ->
    ActorId = {reducer, 9, 9},
    Spec0 = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Spec = Spec0#{
        actors := #{ActorId => hls_topology_source_fixture},
        routes := [{{ActorId, out}, [{external, messages}]}],
        startup := [{ActorId, [opaque_message]}]
    },
    Topology = hls_topology:normalize(Spec),
    Scheduler = scheduler_plan(Topology, [reducer, source]),
    Plan = hls_reduction_plan:normalize(
        Topology,
        Scheduler,
        #{reducer => source_fragments}
    ),
    ?assertMatch(#{placements := [_]}, Plan).

%% Checks captured routes must be inverse closed.
-spec captured_routes_must_be_inverse_closed_test() -> any().
captured_routes_must_be_inverse_closed_test() ->
    Spec0 = closed_topology(hls_topology_source_fragment_fixture, [3, 3]),
    Spec = replace_relation(Spec0, {reducer, north},
        {{reducer, north}, [
            {family, reducer, {translate, [0, 0], wrap}}
        ]}),
    assert_spec_error(Spec, source_fragment_offsets_not_inverse_closed).

%% Checks size two aliases preserve inverse multiplicity.
-spec size_two_aliases_preserve_inverse_multiplicity_test() -> 'ok'.
size_two_aliases_preserve_inverse_multiplicity_test() ->
    {Topology, Scheduler} = closed_plan([2, 2]),
    Plan = hls_reduction_plan:normalize(
        Topology, Scheduler, #{reducer => source_fragments}
    ),
    [Placement] = maps:get(placements, Plan),
    Fragments = maps:get(fragments, Placement),
    ?assertEqual([[0, 1], [0, 1]], [
        maps:get(offset, Fragment) || Fragment <- Fragments
    ]),
    ?assertEqual([[0, 1], [0, 1]], [
        maps:get(inverse_offset, Fragment) || Fragment <- Fragments
    ]),
    ?assertEqual([0, 1], lists:sort([
        maps:get(inverse_ordinal, Fragment) || Fragment <- Fragments
    ])).

%% Checks one scheduler group cannot mix artifact modes.
-spec one_scheduler_group_cannot_mix_artifact_modes_test() -> any().
one_scheduler_group_cannot_mix_artifact_modes_test() ->
    Topology = hls_topology:normalize(dual_reducer_topology()),
    Scheduler = hls_scheduler_plan:normalize(Topology, #{
        combined => group_spec([
            {family, reducer_a},
            {family, reducer_b}
        ])
    }),
    assert_plan_error(source_fragment_scheduler_group_conflict, fun() ->
        hls_reduction_plan:normalize(
            Topology, Scheduler, #{reducer_a => source_fragments}
        )
    end).

%% Checks one module cannot require two artifact modes.
-spec one_module_cannot_require_two_artifact_modes_test() -> any().
one_module_cannot_require_two_artifact_modes_test() ->
    Topology = hls_topology:normalize(dual_reducer_topology()),
    Scheduler = scheduler_plan(Topology, [reducer_a, reducer_b]),
    assert_plan_error(source_fragment_module_artifact_conflict, fun() ->
        hls_reduction_plan:normalize(
            Topology, Scheduler, #{reducer_a => source_fragments}
        )
    end).

%% Requires translation of a negative fixture to report the expected reason.
-spec assert_fixture_error('hls_reduction_plan_conditional_fixture' | 'hls_reduction_plan_excess_fixture' | 'hls_reduction_plan_guarded_fixture' | 'hls_reduction_plan_nontransportable_fixture' | 'hls_reduction_plan_optional_fixture' | 'hls_reduction_plan_refutable_fixture' | 'hls_reduction_plan_short_fixture' | 'hls_reduction_plan_wrong_schema_fixture','source_fragment_conditional_open' | 'source_fragment_conditional_prefix' | 'source_fragment_excess_prefix' | 'source_fragment_nonexhaustive_contribution' | 'source_fragment_nontransportable_contribution' | 'source_fragment_prefix_schema' | 'source_fragment_short_prefix') -> any().
assert_fixture_error(Module, Tag) ->
    Spec = two_lane_topology(Module, [3, 3]),
    assert_spec_error(Spec, Tag).

%% Requires invalid physical settings to report the expected diagnostic.
-spec assert_spec_error(map(), atom()) -> tuple().
assert_spec_error(Spec, Tag) ->
    Topology = hls_topology:normalize(Spec),
    Scheduler = scheduler_plan(Topology, maps:keys(maps:get(families, Spec))),
    assert_plan_error(Tag, fun() ->
        hls_reduction_plan:normalize(
            Topology, Scheduler, #{reducer => source_fragments}
        )
    end).

%% Requires invalid reduction placement to report the expected diagnostic.
-spec assert_plan_error(atom(), fun(() -> term())) -> tuple().
assert_plan_error(Tag, Fun) ->
    Reason = try Fun() of
        Value -> error({expected_plan_error, Tag, Value})
    catch
        error:Caught -> Caught
    end,
    ?assert(is_tuple(Reason)),
    ?assertEqual(Tag, element(1, Reason)),
    Reason.

%% Normalizes a closed fixture graph for reduction-placement checks.
-spec closed_plan([2 | 3,...]) -> {term(),term()}.
closed_plan(Shape) ->
    Topology = hls_topology:normalize(closed_topology(
        hls_topology_source_fragment_fixture,
        Shape
    )),
    {Topology, scheduler_plan(Topology, [reducer, source])}.

%% Assigns the fixture's logical families to the selected execution groups.
-spec scheduler_plan(hls_topology:plan(), [term()]) -> hls_scheduler_plan:plan().
scheduler_plan(Topology, Families) ->
    hls_scheduler_plan:normalize(Topology, maps:from_list([
        {Family, group_spec([{family, Family}])}
        || Family <- Families
    ])).

%% Builds a homogeneous storage policy for the requested fixture members.
-spec group_spec([{'family',term()} | {'family','reducer',{term(),term(),term()}},...]) -> map().
group_spec(Members) ->
    #{
        members => Members,
        state_storage => block_ram,
        mailbox_storage => block_ram
    }.

%% Builds a closed periodic graph for placement validation.
-spec closed_topology('hls_reduction_plan_branch_fixture' | 'hls_topology_source_fragment_fixture' | 'hls_topology_source_fragment_port_fixture',[2 | 3,...]) -> map().
closed_topology(Module, Shape) ->
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => #{
            reducer => #{module => Module, shape => Shape},
            source => #{
                module => hls_topology_source_fixture,
                shape => Shape
            }
        },
        externals => [
            {messages, out, [message]},
            {reports, out, [notice]}
        ],
        routes => [],
        route_relations => [
            {{reducer, north}, [
                {family, reducer, {translate, [0, -1], wrap}}
            ]},
            {{reducer, south}, [
                {family, reducer, {translate, [0, 1], wrap}}
            ]},
            {{reducer, report}, [{external, reports}]},
            {{source, out}, [{external, messages}]}
        ],
        startup => []
    }.

%% Builds a two-lane contribution pattern for coverage checks.
-spec two_lane_topology('hls_reduction_plan_conditional_fixture' | 'hls_reduction_plan_excess_fixture' | 'hls_reduction_plan_guarded_fixture' | 'hls_reduction_plan_nontransportable_fixture' | 'hls_reduction_plan_optional_fixture' | 'hls_reduction_plan_population_fixture' | 'hls_reduction_plan_refutable_fixture' | 'hls_reduction_plan_short_fixture' | 'hls_reduction_plan_wrong_schema_fixture',[3,...]) -> map().
two_lane_topology(Module, Shape) ->
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => #{reducer => #{module => Module, shape => Shape}},
        externals => [],
        routes => [],
        route_relations => [
            {{reducer, north}, [
                {family, reducer, {translate, [0, -1], wrap}}
            ]},
            {{reducer, south}, [
                {family, reducer, {translate, [0, 1], wrap}}
            ]}
        ],
        startup => []
    }.

%% Builds four reciprocal contribution lanes for placement checks.
-spec four_lane_topology('hls_reduction_plan_inconsistent_fixture') -> map().
four_lane_topology(Module) ->
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => #{
            reducer => #{module => Module, shape => [3, 3]}
        },
        externals => [],
        routes => [],
        route_relations => [
            {{reducer, north}, [
                {family, reducer, {translate, [0, -1], wrap}}
            ]},
            {{reducer, east}, [
                {family, reducer, {translate, [-1, 0], wrap}}
            ]},
            {{reducer, west}, [
                {family, reducer, {translate, [1, 0], wrap}}
            ]},
            {{reducer, south}, [
                {family, reducer, {translate, [0, 1], wrap}}
            ]}
        ],
        startup => []
    }.

%% Builds two reduction families to test module-placement consistency.
-spec dual_reducer_topology() -> map().
dual_reducer_topology() ->
    Relations = lists:append([
        [
            {{Family, north}, [
                {family, Family, {translate, [0, -1], wrap}}
            ]},
            {{Family, south}, [
                {family, Family, {translate, [0, 1], wrap}}
            ]},
            {{Family, report}, [{external, reports}]}
        ]
        || Family <- [reducer_a, reducer_b]
    ]),
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => maps:from_list([
            {Family, #{
                module => hls_topology_source_fragment_fixture,
                shape => [3, 3]
            }}
            || Family <- [reducer_a, reducer_b]
        ]),
        externals => [{reports, out, [notice]}],
        routes => [],
        route_relations => Relations,
        startup => []
    }.

%% Substitutes one routing relation to create a targeted negative witness.
-spec replace_relation(map(),{'reducer','north' | 'report'} | {'source','out'},{{'reducer','north' | 'report'} | {'source','out'},[{term(),term(),term()},...]} | {{'reducer','north'},'buffered',[{term(),term()} | {term(),term(),term()},...]}) -> map().
replace_relation(Spec, Source, Replacement) ->
    Spec#{route_relations := [
        case Relation of
            {Source, _Recipients} -> Replacement;
            {Source, _Delivery, _Recipients} -> Replacement;
            _ -> Relation
        end
        || Relation <- maps:get(route_relations, Spec)
    ]}.
