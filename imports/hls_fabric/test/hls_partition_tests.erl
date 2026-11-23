-module(hls_partition_tests).
-include_lib("eunit/include/eunit.hrl").

family_expansion_preserves_alias_lanes_test() ->
    P = hls_partition:normalize(plan(), placement()),
    #{actors := Actors, lanes := Lanes} = P,
    ?assertEqual(4, length(Actors)),
    Remote = [L || L = #{kind := remote} <- Lanes],
    ?assertEqual(4, length(Remote)),
    ?assert(lists:all(fun(#{ports := Ports}) -> Ports =:= [left, right] end, Remote)),
    #{tx_lanes := Tx, rx_lanes := Rx, actors := Local} = hls_partition:device(P, a),
    ?assertEqual([0, 1], [I || #{wire_id := I} <- Tx]),
    ?assertEqual([0, 1], [I || #{wire_id := I} <- Rx]),
    ?assertEqual([0, 1], [I || #{local_slot := I} <- Local]),
    ?assertEqual([[[1, 0]], [[1, 1]]],
        [[Coords] || #{destination := {actor, {family, cells, Coords}}} <- Tx]).

placement_coverage_test() ->
    Placement = placement(),
    ?assertError({partition_placement, [{family, cells, [0, 0]}], []},
        hls_partition:normalize(plan(), maps:remove({family, cells, [0, 0]}, Placement))),
    ?assertError({partition_placement, [], [{actor, absent}]},
        hls_partition:normalize(plan(), Placement#{{actor, absent} => a})),
    ?assertError({partition_device_count, [a]},
        hls_partition:normalize(plan(), maps:map(fun(_, _) -> a end, Placement))).

deterministic_assignment_test() ->
    Placement = placement(),
    Reverse = maps:from_list(lists:reverse(maps:to_list(Placement))),
    ?assertEqual(hls_partition:normalize(plan(), Placement), hls_partition:normalize(plan(), Reverse)).

unsupported_delivery_test() ->
    Spec = spec(),
    Relations = [{{cells, left}, coupled, [
        {family, cells, {translate, [1, 0], wrap}}, {external, reports}]},
        {{cells, right}, [{family, cells, {translate, [1, 0], wrap}}]},
        {{cells, report}, [{external, reports}]}],
    Plan = hls_topology:normalize(Spec#{route_relations := Relations}),
    ?assertException(error, {partition_route_delivery, _, coupled},
        hls_partition:normalize(Plan, placement())).

queued_fanout_keeps_one_copy_per_recipient_test() ->
    Spec = spec(),
    Relations = [{{cells, left}, queued, [
        {family, cells, {translate, [1, 0], wrap}}, {external, reports}]},
        {{cells, right}, [{family, cells, {translate, [1, 0], wrap}}]},
        {{cells, report}, [{external, reports}]}],
    P = hls_partition:normalize(hls_topology:normalize(Spec#{route_relations := Relations}), placement()),
    #{lanes := Lanes} = P,
    ?assertEqual(8, length(Lanes)),
    ?assertEqual([[left, report]], lists:usort([Ports ||
        #{kind := external, ports := Ports} <- Lanes])).

%% Startup records reach the actor before ordinary per-peer frame traffic.
-spec exact_actor_startup_and_emit_test() -> ok.
exact_actor_startup_and_emit_test() ->
    Plan = hls_topology:normalize(#{version => 1, families => #{}, ingresses => [],
        actors => #{one => hls_partition_fixture, two => hls_partition_fixture},
        externals => [{reports, out, [work]}], route_relations => [],
        routes => lists:append([[{{Source, left}, [{actor, Target}]},
            {{Source, right}, [{actor, Target}]}, {{Source, report}, [{external, reports}]}]
            || {Source, Target} <- [{one, two}, {two, one}]]),
        startup => [{one, [{work, 17}]}]}),
    P = hls_partition:normalize(Plan, #{{actor, one} => a, {actor, two} => b}),
    #{actors := [#{startup := [#{payload := Payload}]} | _]} = P,
    ?assertEqual(<<17:32/little>>, Payload),
    DSLX = iolist_to_binary(hls_partition_dslx:emit(P, a,
        #{name => partition_test, channel_depth => 1, actor_egress_depth => burst})),
    ?assertNotEqual(nomatch, binary:match(DSLX, <<"remote_0_out: chan<axis::Frame>[u32:1] out">>)),
    ?assertNotEqual(nomatch, binary:match(DSLX, <<"spawn axis::ReservedFrame">>)),
    ?assertNotEqual(nomatch, binary:match(DSLX, <<"hls_partition_fixture::OutputPort::LEFT => true">>)),
    ?assertNotEqual(nomatch, binary:match(DSLX, <<"hls_partition_fixture::OutputPort::RIGHT => true">>)),
    ?assertEqual(nomatch, binary:match(DSLX, <<"SharedService">>)).

%% Malformed ingress declarations still fail before any graph is emitted.
-spec malformed_ingress_test() -> ok.
malformed_ingress_test() ->
    Plan = plan(),
    ?assertError({ingress_count, 1},
        hls_partition:normalize(Plan#{ingresses := [any]}, placement())).

%% Public profiles must not silently select unsupported storage or observation behavior.
-spec unsupported_profile_test() -> ok.
unsupported_profile_test() ->
    Partition = hls_partition:normalize(plan(), placement()),
    Base = #{name => profile_test, channel_depth => 1, actor_egress_depth => burst},
    [?assertError({partition_profile, [Key]},
        hls_partition_dslx:emit(Partition, a, Base#{Key => Value}))
        || {Key, Value} <- [{scheduler_groups, #{cells => 2}},
            {reduction_placements, #{cells => bank}}, {mailbox_debug, true},
            {direct_actor_debug, true}, {effect_window_partition, weak_components}]],
    ok.

selector_mismatch_rejected_before_wiring_test() ->
    Plan = hls_topology:normalize(mixed_spec({actor, two})),
    ?assertException(error, {partition_route_encoding, _, _, work},
        hls_partition:normalize(Plan, #{{actor, one} => a, {actor, two} => b})).

mixed_external_encoding_rejected_test() ->
    Plan = hls_topology:normalize(mixed_spec({external, reports})),
    ?assertException(error, {partition_external_encoding, _, _, _},
        hls_partition:normalize(Plan, #{{actor, one} => a, {actor, two} => b})).

mixed_spec(Target) ->
    #{version => 1, families => #{}, ingresses => [],
        actors => #{one => hls_partition_fixture, two => hls_partition_retagged_fixture},
        externals => [{reports, out, [work]}], route_relations => [], startup => [],
        routes => [{{one, left}, [Target]}, {{one, right}, [Target]},
            {{one, report}, [{external, reports}]}, {{two, out}, [{external, reports}]}]}.

plan() -> hls_topology:normalize(spec()).

spec() ->
    #{version => 1, actors => #{},
        families => #{cells => #{module => hls_partition_fixture, shape => [2, 2]}},
        ingresses => [], externals => [{reports, out, [work]}], routes => [], startup => [],
        route_relations => [
            {{cells, left}, [{family, cells, {translate, [1, 0], wrap}}]},
            {{cells, right}, [{family, cells, {translate, [-1, 0], wrap}}]},
            {{cells, report}, [{external, reports}]}]}.

placement() -> maps:from_list([{{family, cells, [X, Y]}, case X of 0 -> a; 1 -> b end}
    || X <- [0, 1], Y <- [0, 1]]).
