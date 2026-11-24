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
    ?assertMatch(
        {error, {plan_mismatch, _, <<"other-plan">>}},
        hls_characterization:matches(
            Plan, Characterization#{plan := <<"other-plan">>}
        )
    ),
    ?assertNotEqual(
        hls_characterization:identity(Characterization),
        hls_characterization:identity(Characterization#{evidence := <<"evidence-b">>})
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
