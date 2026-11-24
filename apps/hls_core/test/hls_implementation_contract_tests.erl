-module(hls_implementation_contract_tests).

-include_lib("eunit/include/eunit.hrl").

%% Plan and characterization identities bind exact deterministic terms.
-spec exact_plan_and_characterization_correlation_test() -> ok.
exact_plan_and_characterization_correlation_test() ->
    Plan = plan(),
    Identity = hls_implementation_plan:identity(Plan),
    Characterization = hls_characterization:new(
        Identity,
        <<"realized-a">>,
        <<"evidence-a">>,
        synthetic_fixture,
        <<"finite contract fixture">>,
        #{target_latency_ps => #{fpga_a => 20, fpga_b => 10}}
    ),
    ?assertEqual(ok, hls_characterization:matches(Plan, Characterization)),
    ?assertEqual(ok, hls_characterization:matches(Plan, <<"realized-a">>, Characterization)),
    ?assertEqual(Identity, hls_characterization:plan_identity(Characterization)),
    ?assertEqual(
        <<"realized-a">>, hls_characterization:implementation_identity(Characterization)
    ),
    ?assertEqual(<<"evidence-a">>, hls_characterization:evidence_identity(Characterization)),
    ?assertEqual(synthetic_fixture, hls_characterization:method(Characterization)),
    ?assertEqual(<<"finite contract fixture">>, hls_characterization:scope(Characterization)),
    ?assertMatch(
        {error, {plan_mismatch, _, <<"other-plan">>}},
        hls_characterization:matches(
            Plan, Characterization#{plan := <<"other-plan">>}
        )
    ),
    ?assertMatch(
        {error, {implementation_mismatch, <<"realized-b">>, <<"realized-a">>}},
        hls_characterization:matches(Plan, <<"realized-b">>, Characterization)
    ),
    ?assertEqual(
        ok,
        hls_characterization:matches(
            Plan, Characterization#{implementation := <<"different-realization">>}
        )
    ),
    ?assertNotEqual(
        hls_characterization:identity(Characterization),
        hls_characterization:identity(Characterization#{evidence := <<"evidence-b">>})
    ).

%% Revision provenance names exactly its direct parent and characterization basis.
-spec revision_provenance_is_direct_and_correlated_test() -> ok.
revision_provenance_is_direct_and_correlated_test() ->
    Plan = plan(),
    ?assertEqual(#{clock_period_ps => 5000}, hls_implementation_plan:constraints(Plan)),
    ?assertEqual(
        #{actor_a => <<"implementation-a">>}, hls_implementation_plan:capabilities(Plan)
    ),
    ?assertEqual(
        #{planner => <<"fixture">>, inputs => [<<"input-a">>]},
        hls_implementation_plan:provenance(Plan)
    ),
    First = hls_implementation_plan:revise(
        Plan,
        hls_implementation_plan:placement(Plan),
        hls_implementation_plan:schedules(Plan),
        <<"characterization-a">>
    ),
    FirstProvenance = hls_implementation_plan:provenance(First),
    ?assertEqual(hls_implementation_plan:identity(Plan), maps:get(parent, FirstProvenance)),
    ?assertEqual(<<"characterization-a">>, maps:get(basis, FirstProvenance)),
    Second = hls_implementation_plan:revise(
        First,
        hls_implementation_plan:placement(First),
        hls_implementation_plan:schedules(First),
        <<"characterization-b">>
    ),
    SecondProvenance = hls_implementation_plan:provenance(Second),
    ?assertEqual(hls_implementation_plan:identity(First), maps:get(parent, SecondProvenance)),
    ?assertNotEqual(hls_implementation_plan:identity(Plan), maps:get(parent, SecondProvenance)),
    ?assertEqual(
        [<<"characterization-a">>, <<"characterization-b">>, <<"input-a">>],
        maps:get(inputs, SecondProvenance)
    ).

%% A revision must carry its parent and basis together, both as nonempty identities.
-spec incomplete_revision_provenance_is_rejected_test() -> ok.
incomplete_revision_provenance_is_rejected_test() ->
    Plan = plan(),
    Initial = hls_implementation_plan:provenance(Plan),
    ?assertMatch(
        {error, {invalid_provenance, _}},
        hls_implementation_plan:validate(
            Plan#{provenance := Initial#{basis => <<"characterization">>}}
        )
    ),
    ?assertMatch(
        {error, {invalid_provenance, _}},
        hls_implementation_plan:validate(Plan#{provenance := Initial#{parent => <<"plan">>}})
    ),
    ?assertEqual(
        {error, {invalid_component, parent, <<>>}},
        hls_implementation_plan:validate(
            Plan#{
                provenance := Initial#{basis => <<"characterization">>, parent => <<>>}
            }
        )
    ).

%% Scheduler requests cannot cross their proposed placement or duplicate membership.
-spec invalid_scheduler_membership_is_rejected_test() -> ok.
invalid_scheduler_membership_is_rejected_test() ->
    Plan = plan(),
    [Schedule] = hls_implementation_plan:schedules(Plan),
    WrongTarget = Schedule#{target := fpga_b},
    ?assertMatch(
        {error, {schedule_target_mismatch, {actor, a}, fpga_b, fpga_a}},
        hls_implementation_plan:validate(Plan#{schedules := [WrongTarget]})
    ),
    ?assertEqual(
        {error, duplicate_scheduler_membership},
        hls_implementation_plan:validate(Plan#{schedules := [Schedule, Schedule]})
    ).

%% Deterministic identities reject live VM values even after safe external-term decoding.
-spec process_free_identity_fields_reject_nested_live_values_test() -> ok.
process_free_identity_fields_reject_nested_live_values_test() ->
    Port = open_port({spawn_executable, os:find_executable("cat")}, [binary]),
    try
        Plan = plan(),
        Characterization = hls_characterization:new(
            hls_implementation_plan:identity(Plan),
            <<"realized">>,
            <<"evidence">>,
            synthetic_fixture,
            <<"process-free fixture">>,
            #{}
        ),
        Live = [
            {pid, self()},
            {port, Port},
            {reference, make_ref()},
            {function, fun erlang:abs/1}
        ],
        lists:foreach(
            fun({Kind, Value}) ->
                Decoded = binary_to_term(
                    term_to_binary(#{outer => [{captured, Value}]}), [safe]
                ),
                ?assertEqual(
                    {error, {live_field_value, constraints, Kind}},
                    hls_implementation_plan:validate(Plan#{constraints := Decoded})
                ),
                ?assertEqual(
                    {error, {live_field_value, capabilities, Kind}},
                    hls_implementation_plan:validate(Plan#{capabilities := Decoded})
                ),
                ?assertEqual(
                    {error, {live_metrics_value, Kind}},
                    hls_characterization:validate(Characterization#{metrics := Decoded})
                )
            end,
            Live
        )
    after
        true = port_close(Port)
    end.

%% Construct one small valid proposal used by contract checks.
-spec plan() -> hls_implementation_plan:plan().
plan() ->
    hls_implementation_plan:new(
        <<"logical-a">>,
        #{{actor, a} => fpga_a},
        [#{id => scheduler_a, target => fpga_a, module => actor_a, members => [{actor, a}]}],
        #{clock_period_ps => 5000},
        #{actor_a => <<"implementation-a">>},
        #{planner => <<"fixture">>, inputs => [<<"input-a">>]}
    ).
