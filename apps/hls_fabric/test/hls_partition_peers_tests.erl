-module(hls_partition_peers_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% The smallest even torus without aliased physical neighbors has eighteen patches.
-spec four_neighbor_geometry_test_() -> {timeout, pos_integer(), fun(() -> ok)}.
four_neighbor_geometry_test_() ->
    {timeout, 60, fun four_neighbor_geometry/0}.

%% Every wire ID joins the same source/recipient at both endpoints; peer namespaces never alias.
-spec four_neighbor_geometry() -> ok.
four_neighbor_geometry() ->
    {Plan, Placement, _} = hls_phi_memory_fixture:fixture(mesh_memory),
    P = #{actors := Actors, devices := Devices} = hls_partition:normalize(Plan, Placement),
    ?assertEqual(216, length(Actors)),
    ?assertEqual(lists:seq(0, 17), Devices),
    lists:foreach(fun(D) ->
        #{actors := Local, links := Links} = hls_partition:device(P, D),
        ?assertEqual(12, length(Local)),
        ?assertEqual([0, 1, 2, 3], [I || #{index := I} <- Links]),
        lists:foreach(fun(#{peer := Peer, tx_lanes := Out, rx_lanes := In}) ->
            ?assertNotEqual(D, Peer),
            ?assertEqual(lists:seq(0, length(Out)-1), [W || #{wire_id := W} <- Out]),
            ?assertEqual(lists:seq(0, length(In)-1), [W || #{wire_id := W} <- In]),
            #{links := PeerLinks} = hls_partition:device(P, Peer),
            [#{tx_lanes := In, rx_lanes := Out}] = [L || L = #{peer := Owner} <- PeerLinks, Owner =:= D]
        end, Links)
    end, Devices).

%% Arbitrary device IDs must not collide with counters used to assign graph indices.
-spec device_ids_do_not_alias_numbering_test() -> ok.
device_ids_do_not_alias_numbering_test() ->
    Actors = #{a => hls_partition_fixture, b => hls_partition_fixture, c => hls_partition_fixture},
    Plan = hls_topology:normalize(#{version => 1, actors => Actors, families => #{},
        ingresses => [], externals => [{reports, out, [work]}], route_relations => [], startup => [],
        routes => [{{a, left}, [{actor, b}]}, {{a, right}, [{actor, c}]},
            {{b, left}, [{actor, a}]}, {{c, left}, [{actor, a}]},
            {{b, right}, [{actor, a}]}, {{c, right}, [{actor, a}]}] ++
            [{{A, report}, [{external, reports}]} || A <- [a, b, c]]}),
    P = hls_partition:normalize(Plan, #{{actor, a} => tx, {actor, b} => rx, {actor, c} => wire}),
    #{links := [_, _], tx_lanes := [A, B]} = Local = hls_partition:device(P, tx),
    ?assertEqual([0, 0], [maps:get(wire_id, L) || L <- [A, B]]),
    ?assertNotEqual(hls_partition_links:channel(Local, A, out), hls_partition_links:channel(Local, B, out)),
    ?assertEqual(6, length(hls_partition_links:ports(Local))),
    DSLX = iolist_to_binary(hls_partition_links:spawn(Local)),
    ?assertNotEqual(nomatch, binary:match(DSLX, <<"outgoing_0_c, received_0_p">>)),
    ?assertNotEqual(nomatch, binary:match(DSLX, <<"outgoing_1_c, received_1_p">>)).

%% A credit bridge needs reverse traffic even when an application route is one-way.
-spec unidirectional_link_rejected_test() -> ok.
unidirectional_link_rejected_test() ->
    ?assertError({unidirectional_partition_link, peer}, hls_partition_links:spawn(
        #{links => [#{index => 0, peer => peer, tx_lanes => [#{tx_index => 0}], rx_lanes => []}]})).

%% Width, buffering and hardware identity must describe the same endpoints.
-spec packed_transport_binding_test_() -> {timeout, pos_integer(), fun(() -> ok)}.
packed_transport_binding_test_() -> {timeout, 60, fun packed_transport_binding/0}.

%% Opaque actor lanes stay identical as the peer transfer width and capacity change.
-spec packed_transport_binding() -> ok.
packed_transport_binding() ->
    {Plan, Placement, _} = hls_phi_memory_fixture:fixture(board_memory),
    Original = hls_partition:normalize(Plan, Placement),
    #{devices := BaseDevices} = hls_partition_binding:deployment(Original),
    lists:foreach(fun({Words, Credits, Compact}) ->
        Plain = #{words => Words, credits => Credits},
        Transport = case Compact of true -> Plain#{compact => true}; false -> Plain end,
        P = hls_partition_links:configure(Original, Transport),
        ?assertEqual(hls_partition_links:configure(Original, Plain),
            hls_partition_links:configure(Original, Plain#{compact => false})),
        #{devices := Devices} = Deployment = hls_partition_binding:deployment(P),
        lists:foreach(fun(Device) ->
            #{local := Local, identity := Identity} = maps:get(Device, Devices),
            ?assertEqual(Transport, maps:get(transport, Local)),
            ?assertNotEqual(maps:get(identity, maps:get(Device, BaseDevices)), Identity),
            Base = hls_partition:device(Original, Device),
            ?assertEqual(maps:get(lanes, Base), maps:get(lanes, Local)),
            ?assertEqual([34*Words], lists:usort([Width || {"_link_" ++ _, Width, _} <- hls_partition_links:ports(Local)])),
            Text = iolist_to_binary(xls_partition_application:emit(Deployment, Device, test_graph)),
            ?assertNotEqual(nomatch, binary:match(Text, <<"import hls_packed_link;">>)),
            ?assertEqual(nomatch, binary:match(Text, <<"import hls_credit_link;">>)),
            case Compact of
                true ->
                    #{devices := PlainDevices} = hls_partition_binding:deployment(
                        hls_partition_links:configure(Original, Plain)),
                    ?assertNotEqual(maps:get(identity, maps:get(Device, PlainDevices)), Identity),
                    ?assertNotEqual(nomatch, binary:match(Text, <<", true>(link_">>));
                false -> ok
            end
        end, maps:get(devices, P)),
        ?assertEqual(Original, hls_partition_links:configure(P, serial))
    end, [{1, 1, false}, {2, 4, false}, {4, 16, false}, {1, 4, true}, {4, 4, true}]),
    lists:foreach(fun(Bad) ->
        ?assertError({partition_transport, Bad}, apply(hls_partition_links, configure, [Original, Bad]))
    end, [#{}, #{words => 3, credits => 4}, #{words => 1, credits => 0},
        #{words => 1, credits => 17}, #{words => 1, credits => 1.0},
        #{words => 1, credits => 4, extra => ignored}, #{words => 1, credits => 4, compact => yes}]).
