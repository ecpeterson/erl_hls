-module(hls_spacetime_plan_tests).

-include_lib("eunit/include/eunit.hrl").

%% Proposal balances stable identities and requests homogeneous scheduler groups.
-spec deterministic_proposal_test() -> ok.
deterministic_proposal_test() ->
    Plan = hls_spacetime_plan:propose(
        topology(), [fpga_a, fpga_b], #{sharing => {by_module, 2}}
    ),
    ?assertEqual(
        #{{actor, a} => fpga_a, {actor, b} => fpga_b, {actor, c} => fpga_a},
        hls_implementation_plan:placement(Plan)
    ),
    ?assertEqual(2, length(hls_implementation_plan:schedules(Plan))).

%% A supplied characterization and an ETF cache round trip drive the same pure revision.
-spec supplied_and_cached_characterization_match_test() -> ok.
supplied_and_cached_characterization_match_test() ->
    Plan = hls_spacetime_plan:propose(
        topology(), [fpga_a, fpga_b], #{sharing => {by_module, 2}}
    ),
    Characterization = hls_characterization:new(
        hls_implementation_plan:identity(Plan),
        <<"realized-fixture">>,
        <<"synthetic-costs">>,
        synthetic_fixture,
        <<"three actors; target ordering only">>,
        #{target_latency_ps => #{fpga_a => 20, fpga_b => 10}}
    ),
    Cached = binary_to_term(term_to_binary(Characterization, [deterministic]), [safe]),
    Policy = fun(Current, Evidence) -> prefer_fast_target(Current, Evidence) end,
    Revised = hls_spacetime_plan:revise(Plan, <<"realized-fixture">>, Characterization, Policy),
    ?assertEqual(
        Revised,
        hls_spacetime_plan:revise(Plan, <<"realized-fixture">>, Cached, Policy)
    ),
    ?assert(lists:all(
        fun(Target) -> Target =:= fpga_b end,
        maps:values(hls_implementation_plan:placement(Revised))
    )).

%% A characterization for another proposal is rejected before policy execution.
-spec mismatched_characterization_is_rejected_test() -> ok.
mismatched_characterization_is_rejected_test() ->
    Plan = hls_spacetime_plan:propose(topology(), [fpga_a, fpga_b], #{}),
    Characterization = hls_characterization:new(
        <<"other-plan">>, <<"realized">>, <<"evidence">>, analytical_model, <<"fixture">>, #{}
    ),
    ?assertError(
        {spacetime_revision, {plan_mismatch, _, <<"other-plan">>}},
        hls_spacetime_plan:revise(
            Plan, <<"realized">>, Characterization, fun(_, _) -> error(unreachable) end
        )
    ).

%% Evidence for another exact realized implementation is rejected before policy execution.
-spec mismatched_implementation_is_rejected_test() -> ok.
mismatched_implementation_is_rejected_test() ->
    Plan = hls_spacetime_plan:propose(topology(), [fpga_a], #{}),
    Characterization = hls_characterization:new(
        hls_implementation_plan:identity(Plan),
        <<"realized-a">>,
        <<"evidence">>,
        native_measurement,
        <<"fixture">>,
        #{}
    ),
    ?assertError(
        {spacetime_revision, {implementation_mismatch, <<"realized-b">>, <<"realized-a">>}},
        hls_spacetime_plan:revise(
            Plan, <<"realized-b">>, Characterization, fun(_, _) -> error(unreachable) end
        )
    ).

%% The fixture is already a core materialized-instance view; no compiler module is involved.
-spec topology() -> map().
topology() ->
    #{
        version => 1,
        actors => [
            #{id => a, module => alpha, outputs => [], mailbox_capacity => 1},
            #{id => b, module => beta, outputs => [], mailbox_capacity => 1},
            #{id => c, module => alpha, outputs => [], mailbox_capacity => 1}
        ],
        families => [],
        routes => [],
        route_relations => [],
        ingresses => [],
        externals => [],
        interfaces => #{},
        startup => [],
        lanes => [],
        lane_relations => [],
        instances => [
            #{identity => {actor, a}, actor => #{id => a, module => alpha}},
            #{identity => {actor, b}, actor => #{id => b, module => beta}},
            #{identity => {actor, c}, actor => #{id => c, module => alpha}}
        ]
    }.

%% This finite synthetic policy demonstrates contract use, not physical optimality.
-spec prefer_fast_target(hls_implementation_plan:plan(), hls_characterization:characterization()) ->
    {hls_implementation_plan:placement(), [hls_implementation_plan:schedule()]}.
prefer_fast_target(Plan, Characterization) ->
    #{target_latency_ps := Costs} = hls_characterization:metrics(Characterization),
    [{_Cost, Target} | _] = lists:sort([{Cost, Name} || {Name, Cost} <- maps:to_list(Costs)]),
    Placement = maps:map(fun(_, _) -> Target end, hls_implementation_plan:placement(Plan)),
    Schedules = [
        Schedule#{
            id => {schedule, Target, maps:get(module, Schedule), Index},
            target => Target
        }
     || {Index, Schedule} <-
            lists:enumerate(0, hls_implementation_plan:schedules(Plan))
    ],
    {Placement, Schedules}.
