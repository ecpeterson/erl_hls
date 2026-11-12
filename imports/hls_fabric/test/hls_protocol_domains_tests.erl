-module(hls_protocol_domains_tests).
-moduledoc "Source placement admission and mechanical domain/channel wiring. One real three-actor emission checks the public boundary; these tests do not establish RTL execution or recovery progress.".
-include_lib("eunit/include/eunit.hrl").

%% Invalid placement stops before partition generation; only one case emits complete source units.
-spec composition_test_() -> term().
composition_test_() -> {timeout, 120, fun composition/0}.

%% Framing preserves each partition's actor catalog and gives channel control its own session.
-spec stream_composition_test_() -> term().
stream_composition_test_() -> {timeout, 120, fun stream_composition/0}.

%% A placement without cut edges needs no channel-management parser and rejects explicitly.
-spec stream_composition() -> ok.
stream_composition() ->
    Config = config(),
    Uncut = #{domains => [{ab, [0, 1]}, {c, [2]}], restart_groups => [[ab], [c]]},
    ?assertError({domain_composition, no_crossings}, hls_protocol_domains:emit_stream(Config, Uncut)),
    #{files := Files, result := #{domains := Domains, inputs := Inputs, outputs := Outputs,
        channel_stream := #{interface := Management, state_bit_budget := StateBits}}} =
        hls_protocol_domains:emit_stream(Config, placement()),
    ?assertEqual([a, b, c], [Only || #{interface := #{runtime_interface := #{actors := Actors}}} <- Domains,
        Only <- maps:keys(Actors)]),
    lists:foreach(fun(#{interface := #{runtime_interface := #{actors := Actors}}}) ->
        lists:foreach(fun(#{contract := #{calls := Calls, casts := Casts}, pending_calls := Pending}) ->
            ?assertEqual(#{}, Calls),
            ?assert(Casts =/= []),
            ?assertEqual(0, Pending)
        end, maps:values(Actors))
    end, Domains),
    ?assertMatch(#{kind := domain_channel_management, channels := [0], management_route := {0, 0}}, Management),
    ?assertEqual(1159, StateBits),
    ?assert(lists:member({"channel_transport_session", 64}, Inputs)),
    ?assert(lists:member({"channel_management_output_valid", 1}, Outputs)),
    ?assertNot(lists:keymember("ch_0_bind_request", 1, Inputs)),
    ?assert(lists:keymember("ch_0_data_valid", 1, Inputs)),
    ?assert(lists:keymember("ch_0_bound_source_incarnation", 1, Outputs)),
    lists:foreach(fun(I) ->
        Prefix = "domain_" ++ integer_to_list(I) ++ "_",
        ?assert(lists:member({Prefix ++ "domain_reset", 1}, Inputs)),
        ?assert(lists:member({Prefix ++ "transport_reset", 1}, Inputs)),
        ?assertNot(lists:keymember(Prefix ++ "reset", 1, Inputs)),
        ?assertNot(lists:keymember(Prefix ++ "domain_current", 1, Outputs))
    end, [0, 1, 2]),
    Raw = iolist_to_binary(maps:get("channel/protocol_domains.sv", Files)),
    includes(Raw, ".source_live((!reset && !domain_0_domain_reset && "),
    includes(Raw, ".destination_live((!reset && !domain_1_domain_reset && "),
    Top = iolist_to_binary(maps:get("channel_management/protocol_domains_stream.sv", Files)),
    includes(Top, "module protocol_domains_stream(input wire clk,"),
    includes(Top, ".observed_ch_0_current_source(domain_0_domain_current)"),
    includes(Top, ".observed_ch_0_source(ch_0_bound_source_incarnation)"),
    ok.

%% All negative cases reuse the same small source declarations and never write bundles.
-spec composition() -> ok.
composition() ->
    Config = config(),
    Placement = placement(),
    ?assertError({domain_composition, complete_source_required},
        hls_protocol_domains:emit(#{native_actors => [a]}, Placement)),
    lists:foreach(fun({Reason, Rejected}) ->
        ?assertError({domain_composition, Reason}, hls_protocol_domains:emit(Config, Rejected))
    end, [
        {placement, #{}},
        {placement_fields, Placement#{unexpected => true}},
        {domains, Placement#{domains => [{a, [0, 1, 2]}], restart_groups => [[a]]}},
        {domain_members, Placement#{domains => [{a, [0]}, {b, []}, {c, [1, 2]}]}},
        {domain_members, Placement#{domains => [{a, [0]}, {b, [1]}, {c, [3]}]}},
        {duplicate_domain, Placement#{domains => [{a, [0]}, {a, [1]}, {c, [2]}]}},
        {actor_cover, Placement#{domains => [{a, [0]}, {b, [1]}], restart_groups => [[a, b]]}},
        {actor_cover, Placement#{domains => [{a, [0]}, {b, [0, 1]}, {c, [2]}]}},
        {restart_groups, Placement#{restart_groups => [[], [a, b, c]]}},
        {group_cover, Placement#{restart_groups => [[a, b]]}},
        {group_cover, Placement#{restart_groups => [[a, b], [a, c]]}},
        {crossing_restart_group, Placement#{restart_groups => [[a], [b], [c]]}}
    ]),
    Key = {?MODULE, topology_calls},
    put(Key, 0),
    try
        SnapshotConfig = Config#{sources := maps:get(sources, Config) ++
                [{"test/hls_protocol_domains_fixture.erl", []}],
            topology := {hls_protocol_domains_fixture, topology, [Key]}},
        #{files := Files, result := Result} = hls_protocol_domains:emit(SnapshotConfig, Placement),
        ?assertEqual(1, get(Key)),
        check_composition(Files, Result)
    after
        erase(Key)
    end,
    ok.

%% The independent counter has no crossing; producer and consumer share one declared restart group.
-spec config() -> hls_source_config:network().
config() ->
    #{sources => [{"test/hls_cross_domain_producer.erl", []},
          {"test/hls_cross_domain_consumer.erl", []}, {"test/hls_domain_counter.erl", []}],
      topology => {hls_cross_domain_producer, topology, []}, actor_limit => 3,
      control => rectangle}.

%% Global actor ordering is source-topology ordering, rather than an HDL module-name convention.
-spec placement() -> hls_protocol_domains:placement().
placement() ->
    #{domains => [{a, [0]}, {b, [1]}, {c, [2]}], restart_groups => [[a, b], [c]]}.

%% Public ports retain separate lifecycle/host interfaces and expose transport instead of bare peer wires.
-spec check_composition(hls_generated_files:files(), hls_protocol_domains:result()) -> ok.
check_composition(Files, #{domains := Domains, crossings := [Crossing],
        restart_groups := Groups, inputs := Inputs, outputs := Outputs,
        channel := Channel, frame_payload_words := Words, eligible := Eligible}) ->
    ?assertEqual([{a, 0, [0]}, {b, 1, [1]}, {c, 2, [2]}],
        [{Id, I, Actors} || #{id := Id, index := I, actors := Actors} <- Domains]),
    ?assertEqual([[a, b], [c]], Groups),
    ?assertEqual(false, Eligible),
    ?assertEqual(20, Words),
    ?assertEqual(Words, maps:get(frame_payload_words, Channel)),
    #{index := Link, source_domain := Source, destination_domain := Destination,
        link := #{direction := outgoing, source_index := From, destination_index := To}} = Crossing,
    ?assertEqual({0, 1, 0, 1}, {Source, Destination, From, To}),
    ?assertEqual([1, 1, 0], [length(maps:get(crossings, Interface))
        || #{interface := Interface} <- Domains]),
    ?assertEqual([[0], [1], [2]], [maps:get(native_indices, Network)
        || #{interface := #{network := Network}} <- Domains]),
    PublicNames = [Name || {Name, _} <- Inputs ++ Outputs],
    ?assertEqual(length(PublicNames), length(lists:usort(PublicNames))),
    ?assertNot(lists:any(fun(Name) -> string:find(Name, "_remote_") =/= nomatch end, PublicNames)),
    ?assert(lists:member({"reset", 1}, Inputs)),
    lists:foreach(fun(I) ->
        Prefix = "domain_" ++ integer_to_list(I) ++ "_",
        ?assert(lists:member({Prefix ++ "reset", 1}, Inputs)),
        ?assert(lists:member({Prefix ++ "management_valid", 1}, Inputs)),
        ?assert(lists:member({Prefix ++ "domain_current", 64}, Outputs)),
        ?assert(lists:keymember(Prefix ++ "domain_phase", 1, Outputs))
    end, [0, 1, 2]),
    Prefix = "ch_" ++ integer_to_list(Link) ++ "_",
    lists:foreach(fun({Name, Width}) ->
        ?assert(lists:member({Prefix ++ Name, Width}, Inputs))
    end, [{"bind_request", 1}, {"fence", 1}, {"expected_generation", 64},
        {"data_tx_ready", 1}, {"data_valid", 1}, {"data_generation", 64},
        {"data_sequence", 32}, {"data_slot", 8}, {"data_frame", 32 + Words * 32},
        {"ack_tx_ready", 1}, {"credit_valid", 1}, {"credit_generation", 64}, {"credit_sequence", 32}]),
    ?assert(lists:member({Prefix ++ "fault", 1}, Outputs)),
    ?assertNot(lists:keymember(Prefix ++ "reset", 1, Inputs)),
    ?assertNot(lists:keymember(Prefix ++ "source_incarnation", 1, Inputs)),
    ?assertNot(lists:keymember(Prefix ++ "destination_valid", 1, Outputs)),
    check_wiring(iolist_to_binary(maps:get("channel/protocol_domains.sv", Files)), Link),
    lists:foreach(fun(I) ->
        Name = "domain_" ++ integer_to_list(I),
        ?assert(maps:is_key(Name ++ "/domain/domain.x", Files)),
        Wrapper = iolist_to_binary(maps:get(Name ++ "/domain/protocol_domain.sv", Files)),
        includes(Wrapper, ["module ", Name, "("]),
        includes(Wrapper, [Name, "_core "])
    end, [0, 1, 2]),
    ?assert(maps:is_key("channel/domain_channel.x", Files)),
    ok.

%% Domain reset must suppress channel transfers on that same edge without resetting channel tombstones.
-spec check_wiring(binary(), non_neg_integer()) -> ok.
check_wiring(Text, Link) ->
    includes(Text, "module protocol_domains(input wire clk,"),
    lists:foreach(fun(I) ->
        Prefix = "domain_" ++ integer_to_list(I) ++ "_",
        includes(Text, [".reset((reset || ", Prefix, "reset))"])
    end, [0, 1, 2]),
    includes(Text, ".reset(reset)"),
    includes(Text, ".source_live((!reset && !domain_0_reset && domain_0_domain_phase == "),
    includes(Text, ".destination_live((!reset && !domain_1_reset && domain_1_domain_phase == "),
    Remote = "remote_" ++ integer_to_list(Link) ++ "_",
    lists:foreach(fun({Port, Name}) -> includes(Text, [".", Port, "(", Name, ")"]) end,
        [{"source_incarnation", "domain_0_domain_current"},
         {"destination_incarnation", "domain_1_domain_current"},
         {"source_valid", "domain_0_app_" ++ Remote ++ "valid"},
         {"source_ready", "domain_0_" ++ Remote ++ "ready"},
         {"destination_ready", "domain_1_app_" ++ Remote ++ "ready"},
         {"destination_valid", "domain_1_" ++ Remote ++ "valid"},
         {"destination_frame", "domain_1_" ++ Remote ++ "frame"}]),
    ok.

%% Inspect only externally significant wiring and namespaces, not formatting or full emitted snapshots.
-spec includes(binary(), iodata()) -> ok.
includes(Text, Expected) ->
    ?assertNotEqual(nomatch, binary:match(Text, iolist_to_binary(Expected))),
    ok.
