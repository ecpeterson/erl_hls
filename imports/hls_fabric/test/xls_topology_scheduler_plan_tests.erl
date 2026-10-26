-module(xls_topology_scheduler_plan_tests).
-moduledoc "Small planning regressions inspect physical ownership before source rendering; they do not establish hardware progress or timing.".
-include_lib("eunit/include/eunit.hrl").

%% Interleaved placement has explicit inverse addresses and ordered, prepacked startup requests.
-spec startup_control_ownership_test() -> ok.
startup_control_ownership_test() ->
    Topology = counters(),
    Plan = xls_shared_topology_dslx:plan(Topology, profile(shards(cells))),
    #{representation := compact_shared, schedulers := [Even, Odd],
      families := [#{destinations := Destinations, outputs := Outputs}],
      control := #{families := [cells], groups := [0, 1], width := 2, height := 2},
      effect_window_domains := [[0], [1]]} = xls_shared_topology_dslx:descriptor(Plan),
    ?assertEqual([control, egress_credit], maps:get(producers, Even)),
    ?assertEqual(#{control => 0, egress_credit => 1}, maps:get(producer_index, Odd)),
    ?assertEqual([#{slot => 0, family => cells, coordinates => [0, 0]},
        #{slot => 1, family => cells, coordinates => [1, 0]}], maps:get(addresses, Even)),
    ?assertEqual([#{slot => 0, family => cells, coordinates => [0, 1]},
        #{slot => 1, family => cells, coordinates => [1, 1]}], maps:get(addresses, Odd)),
    ?assertEqual([#{slot => 0, schema => work, payload => <<1, 0, 0, 0>>},
        #{slot => 1, schema => work, payload => <<3, 0, 0, 0>>}], maps:get(startup, Even)),
    ?assertEqual([#{slot => 0, schema => work, payload => <<2, 0, 0, 0>>},
        #{slot => 1, schema => work, payload => <<4, 0, 0, 0>>}], maps:get(startup, Odd)),
    ?assertEqual([{[0, 0], 0, 0}, {[1, 0], 0, 1}, {[0, 1], 1, 0}, {[1, 1], 1, 1}],
        [{C, G, S} || #{coordinates := C, group := G, slot := S} <- Destinations]),
    ?assertEqual([#{port => out, owner => router, delivery => direct,
        recipients => [{external, reports}]}], Outputs),
    Generated = iolist_to_binary(xls_shared_topology_dslx:emit(Plan)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"proc ControlDispatcher">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"proc SchedulerStartup1">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"@@">>)),
    ok.

%% Captured routes disappear from ordinary producers but still couple the reduction-plane owners.
-spec source_fragment_dependency_test() -> ok.
source_fragment_dependency_test() ->
    Topology = reduction(),
    Placement = profile(shards(reducer)),
    Plan = xls_shared_topology_dslx:plan(Topology, Placement#{reduction_placements => #{reducer => source_fragments}}),
    #{families := [#{outputs := Outputs}], schedulers := Schedulers,
      source_fragment_planes := [#{family := reducer, source_schedulers := [0, 1],
        captured_ports := [north, south], destinations := Rows, fragment_capacity := 2}],
      effect_window_domains := [[0, 1]]} = xls_shared_topology_dslx:descriptor(Plan),
    ?assertEqual([north, south], [Port || #{port := Port, owner := source_fragment} <- Outputs]),
    ?assertEqual([report], [Port || #{port := Port, owner := router} <- Outputs]),
    ?assertEqual([[egress_credit], [egress_credit]], [maps:get(producers, S) || S <- Schedulers]),
    ?assertEqual([[], []], [maps:get(destinations, S) || S <- Schedulers]),
    ?assertEqual(9, length(Rows)),
    ?assertEqual([0, 1], [maps:get(effect_window_position, S) || S <- Schedulers]),
    ?assertEqual(#{hls_topology_source_fragment_fixture => #{frame_payload_words => 3, shared_service => aggregate_only}},
        xls_shared_topology_dslx:artifact_requirements(Plan)),
    ok.

%% Without capture the same reciprocal graph retains ordinary producers and routed destinations.
-spec ordinary_dependency_test() -> ok.
ordinary_dependency_test() ->
    Plan = xls_shared_topology_dslx:plan(reduction(), profile(shards(reducer))),
    #{source_fragment_planes := [], schedulers := Schedulers,
      effect_window_domains := [[0, 1]], families := [#{outputs := Outputs}]} =
        xls_shared_topology_dslx:descriptor(Plan),
    ?assertEqual([[{scheduler, 0}, {scheduler, 1}, egress_credit],
        [{scheduler, 0}, {scheduler, 1}, egress_credit]], [maps:get(producers, S) || S <- Schedulers]),
    ?assertEqual([[0, 1], [0, 1]], [maps:get(destinations, S) || S <- Schedulers]),
    ?assertEqual([router, router, router], [Owner || #{owner := Owner} <- Outputs]),
    ok.

%% Dedicated families and materialized graphs report their distinct representations explicitly.
-spec representations_test() -> ok.
representations_test() ->
    Dedicated = xls_shared_topology_dslx:plan(counters(), profile(#{})),
    ?assertMatch(#{representation := compact_direct}, xls_shared_topology_dslx:descriptor(Dedicated)),
    Exact = hls_topology:normalize(hls_scheduler_build_fixture:topology()),
    Materialized = xls_shared_topology_dslx:plan(Exact, profile(#{})),
    ?assertMatch(#{representation := materialized, lanes := [_, _], effect_window_domains := []},
        xls_shared_topology_dslx:descriptor(Materialized)),
    ok.

%% Four ordinary actors provide startup and rectangle-control coverage without a decoder workload.
-spec counters() -> hls_topology:plan().
counters() ->
    hls_topology:normalize(#{version => 1, actors => #{},
        families => #{cells => #{module => hls_scheduler_build_fixture, shape => [2, 2]}},
        externals => [{reports, out, [work]}], routes => [],
        route_relations => [{{cells, out}, [{external, reports}]}],
        startup => [{{cells, X, Y}, [{work, 1 + 2 * X + Y}]} || X <- [0, 1], Y <- [0, 1]],
        ingresses => [{commands, {rectangle, [2, 2]}, [{all, [work],
            [{family, cells, {embed, [1, 1], [0, 0]}}]}]}]}).

%% The existing tiny reduction actor supplies a two-output reciprocal source prefix.
-spec reduction() -> hls_topology:plan().
reduction() ->
    hls_topology:normalize(#{version => 1, actors => #{},
        families => #{reducer => #{module => hls_topology_source_fragment_fixture, shape => [3, 3]}},
        externals => [{reports, out, [notice]}], routes => [], startup => [], ingresses => [],
        route_relations => [{{reducer, north}, [{family, reducer, {translate, [0, -1], wrap}}]},
            {{reducer, south}, [{family, reducer, {translate, [0, 1], wrap}}]},
            {{reducer, report}, [{external, reports}]}]}).

%% Split each logical family by its existing row-major instance numbering.
-spec shards(atom()) -> hls_scheduler_plan:spec().
shards(Family) ->
    #{even => group({family, Family, {interleaved, 0, 2}}),
      odd => group({family, Family, {interleaved, 1, 2}})}.

%% Shared executors retain separate bounded RAMs for state and mailboxes.
-spec group({family, atom(), {interleaved, non_neg_integer(), pos_integer()}}) -> map().
group(Member) -> #{members => [Member], state_storage => block_ram, mailbox_storage => block_ram}.

%% Weak components expose the plane dependency that ordinary route pruning would otherwise hide.
-spec profile(hls_scheduler_plan:spec()) -> xls_shared_topology_dslx:profile().
profile(Groups) -> #{name => scheduler_plan_fixture, channel_depth => 1, actor_egress_depth => burst,
    scheduler_groups => Groups, effect_window_partition => weak_components}.
