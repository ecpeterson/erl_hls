-module(hls_protocol_network_tests).
-moduledoc "Public network boundary rejects unsupported activation before source or filesystem work.".
-include_lib("eunit/include/eunit.hrl").

%% An invalid mode cannot be silently interpreted as automatic activation.
-spec unsupported_activation_test() -> ok.
unsupported_activation_test() ->
    ?assertError({hls_diagnostic, #{stage := network, code := unsupported_protocol_activation, context := #{value := pause}}},
        hls_protocol_network:write(#{activation=>pause},"unused")),
    ?assertError({hls_diagnostic, #{stage := network, code := unsupported_protocol_activation, context := #{value := <<"explicit_start">>}}},
        hls_protocol_network:write(#{activation=><<"explicit_start">>},"unused")).

%% One source definition backs several independent inbox owners, bound by hash.
-spec imported_owner_test() -> ok.
imported_owner_test() ->
    Config = #{sources => [{"test/hls_protocol_boundary_fixture.erl", []}],
        topology => {hls_protocol_boundary_fixture, topology, []}, actor_limit => 4},
    #{result := Plan} = hls_protocol_transport:emit(hls_protocol_transport:plan(Config)),
    #{actor_functions := [#{file := File, manifest := #{dslx_sha256 := Hash}}],
        receivers := Receivers} = Plan,
    ?assertEqual([0, 1, 2, 3], [I || #{index := I} <- Receivers]),
    lists:foreach(fun(#{manifest := #{owner_import := Import, inbox := Inbox}}) ->
        ?assertEqual(#{file => File, dslx_sha256 => Hash}, Import),
        ?assert(maps:get(mask_bits, Inbox) > 0)
    end, Receivers).

%% Rendering regression only: transport slices use receiver spans, with startup and host retirement kept separate.
-spec receiver_owned_slices_test() -> ok.
receiver_owned_slices_test() ->
    Inbox = #{links => [#{index => 19, slots => 2}, #{index => 3, slots => 1},
            #{index => 11, slots => 3}],
        slots => [#{index => 0, link => 19, slot => 0},
            #{index => 1, link => 19, slot => 1},
            #{index => 2, link => 3, slot => 0},
            #{index => 3, link => 11, slot => 0},
            #{index => 4, link => 11, slot => 1},
            #{index => 5, link => 11, slot => 2}],
        physical_slots => 6, mask_bits => 9,
        startup => #{count => 2, offset => 6}, host => #{slots => 1, offset => 8}},
    Plan = #{fabric => #{sources => [#{index => 2}], boundaries => [],
            links => [#{index => 3, destination_index => 2, slots => 1},
                #{index => 11, destination_index => 2, slots => 3},
                #{index => 19, destination_index => 2, slots => 2}]},
        receivers => [#{index => 2, file => <<"receivers/receiver_2.x">>,
            manifest => #{inbox => Inbox}}],
        bundle => #{topology => #{externals => []}}, inspection => none,
        activation => automatic, ingress => #{kind => rectangle, input_bits => 194, actors => 3, width => 3, height => 1,
            state_bits => 132, targets => [#{recipients => [#{index => 2, x => 2, y => 0}],
                domains => [#{mask => 0, value => 0}]}]}},
    %% Stub components supply content hashes only; this test does not claim an XLS-compiled network.
    Components = #{"dslx/transport.x" => "// Rendering fixture transport.\n",
        "receivers/receiver_2.x" => "// Rendering fixture receiver.\n"},
    #{files := #{"network/network.x" := Source}, result := Manifest} =
        xls_protocol_network:emit(xls_protocol_network:plan(Plan), Components),
    {match, Slices} = re:run(Source,
        <<"link_[0-9]+_(?:eligible|take|release_valid): [^,\\n]+">>,
        [global, {capture, first, binary}]),
    ?assertEqual([
        <<"link_3_eligible: eligible_2[2+:bits[1]]">>,
        <<"link_11_eligible: eligible_2[3+:bits[3]]">>,
        <<"link_19_eligible: eligible_2[0+:bits[2]]">>,
        <<"link_3_take: or_reduce(step_2.output.take[2+:bits[1]])">>,
        <<"link_3_release_valid: step_2.output.release[2+:bits[1]]">>,
        <<"link_11_take: or_reduce(step_2.output.take[3+:bits[3]])">>,
        <<"link_11_release_valid: step_2.output.release[3+:bits[3]]">>,
        <<"link_19_take: or_reduce(step_2.output.take[0+:bits[2]])">>,
        <<"link_19_release_valid: step_2.output.release[0+:bits[2]]">>
    ], [Slice || [Slice] <- Slices]),
    ?assertNotEqual(nomatch, binary:match(Source,
        <<"step_2.output.take[8+:u1] ++ u1:0 ++ u1:0">>)),
    ?assertMatch(#{startup_messages := 2, native_indices := [2]}, Manifest).
