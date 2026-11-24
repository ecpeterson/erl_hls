-module(hls_bridge_phi_fixture_tests).
-include_lib("eunit/include/eunit.hrl").

partition_preserves_wrapping_routes_and_global_startup_test() ->
    Config = #{shape => [4, 2], planes => [x]},
    {#{actors := Actors, routes := Routes, startup := Startup}, Placement} =
        hls_bridge_phi_fixture:fixture(Config),
    ?assertEqual(16, length(Actors)),
    ?assertEqual([8, 8], [length([ok || Device <- maps:values(Placement), Device =:= I])
        || I <- [0, 1]]),
    ?assertEqual([{actor, {phi_x, 0, 1}}], recipients(Routes, {phi_x, 0, 0}, north)),
    ?assertEqual([{actor, {phi_x, 0, 1}}], recipients(Routes, {phi_x, 0, 0}, south)),
    ?assertEqual([{actor, {phi_x, 3, 0}}], recipients(Routes, {phi_x, 0, 0}, west)),
    ?assertEqual([{actor, {syndrome_x, 0, 0}}], recipients(Routes, {phi_x, 0, 0}, syndrome)),
    Original = hls_topology:normalize(phi_decoder_profile_topology:topology(Config)),
    ?assertEqual(maps:get(startup, Original), Startup).

board_sized_single_plane_population_test() ->
    {#{actors := Actors}, Placement} = hls_bridge_phi_fixture:fixture(#{shape => [2, 2]}),
    ?assertEqual(8, length(Actors)),
    ?assertEqual(2, length([ok || #{id := Id, module := phi_halo_cell} <- Actors,
        maps:get({actor, Id}, Placement) =:= 0])).

both_planes_have_distinct_stable_seeds_test() ->
    {#{startup := Both}, _} = hls_bridge_phi_fixture:fixture(#{shape => [2, 2], planes => [x, z]}),
    {#{startup := Single}, _} = hls_bridge_phi_fixture:fixture(#{shape => [2, 2], planes => [z]}),
    ?assertEqual(Single, [Entry || Entry = #{target := {Family, _, _}} <- Both,
        lists:member(Family, [phi_z, syndrome_z])]).

unequal_partition_is_rejected_test() ->
    ?assertError({unequal_y_partition, 3}, hls_bridge_phi_fixture:fixture(#{shape => [4, 3]})).

deployment_artifact_preserves_logical_to_wire_mapping_test_() ->
    {timeout, 30, fun() ->
        Stage = filename:join("_build", "phi-deployment-" ++
            integer_to_list(erlang:unique_integer([positive, monotonic]))),
        ok = file:make_dir(Stage),
        try
            ok = file:write_file(filename:join(Stage, "config.term"),
                "#{shape => [2, 2], planes => [x]}.\n"),
            ok = hls_bridge_phi_fixture:write(Stage),
            {ok, [Deployment]} = file:consult(filename:join(Stage, "deployment.term")),
            {ok, Bytes} = file:read_file(filename:join(Stage, "bridge.json")),
            #{<<"partition_fingerprint">> := Fingerprint} = json:decode(Bytes),
            ?assertEqual(binary:encode_hex(crypto:hash(sha256,
                term_to_binary(Deployment, [deterministic])), lowercase), Fingerprint),
            #{actors := Actors, tx_lanes := Lanes} = hls_partition:device(Deployment, 0),
            ?assertEqual([{actor, {phi_x, 0, 0}}, {actor, {phi_x, 1, 0}},
                {actor, {syndrome_x, 0, 0}}, {actor, {syndrome_x, 1, 0}}],
                [Id || #{identity := Id} <- Actors]),
            ?assertEqual([{0, {actor, {phi_x, 0, 0}}, {actor, {actor, {phi_x, 0, 1}}}},
                {1, {actor, {phi_x, 1, 0}}, {actor, {actor, {phi_x, 1, 1}}}}],
                [{Wire, Source, Destination} || #{wire_id := Wire, source := Source,
                    destination := Destination, ports := [north, south]} <- Lanes])
        after
            ok = file:del_dir_r(Stage)
        end
    end}.

recipients(Routes, Actor, Port) ->
    [Recipients] = [R || #{source := Source, recipients := R} <- Routes, Source =:= {Actor, Port}],
    Recipients.
