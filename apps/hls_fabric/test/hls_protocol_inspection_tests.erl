-module(hls_protocol_inspection_tests).
-moduledoc "Checks the public inspection build selection and exact source-to-catalog binding.".
-include_lib("eunit/include/eunit.hrl").

%% Unsupported modes fail before file reads or output creation.
-spec invalid_mode_test() -> ok.
invalid_mode_test() ->
    ?assertError({hls_diagnostic, #{code := unsupported_protocol_inspection, context := #{value := trace}}},hls_protocol_network:write(#{inspection=>trace},"unused")),
    ?assertEqual(none,hls_protocol_inspection:mode(none)).

%% The actual application command produces one resource for every compiled source actor.
-spec catalog_test() -> ok.
catalog_test() ->
    Path=filename:join("_build","inspection-binding-"++integer_to_list(erlang:system_time(nanosecond))),
    #{eligible:=false}=hls_protocol_application:write(#{sources=>[{"apps/hls_fabric/test/hls_protocol_boundary_fixture.erl",[]}],
        topology=>{hls_protocol_boundary_fixture,topology,[]},actor_limit=>4,device=>board,host=>1,inspection=>process},Path),
    {ok,Bytes}=file:read_file(filename:join(Path,"network/inspection.etf")),
    Plan=#{actors:=[A|Rest],manifest:=Manifest}=binary_to_term(Bytes),
    ?assertEqual(maps:get(<<"fingerprint">>,Manifest),hls_topology_debug:manifest_fingerprint(Manifest)),
    Catalog=hls_protocol_observation:catalog(Plan,#{manifest=>Manifest,client=>self(),resources=>list_to_tuple(maps:get(<<"resources">>,Manifest))}),
    ?assertEqual(4,length(hls_debug_catalog:actors(Catalog))),
    {ok,Target}=hls_debug_catalog:actor(Catalog,{actor,a}),
    ?assertMatch({capabilities,#{trace:=false}},hls_debug:info(Target,capabilities)),
    ?assertException(error,_,hls_protocol_observation:catalog(Plan#{actors:=[A#{id:=changed}|Rest]},#{manifest=>Manifest})),
    ?assertException(error,_,hls_protocol_observation:catalog(Plan,#{manifest=>Manifest#{<<"fingerprint">>:=<<"bad">>}})),
    ?assertException(error,_,hls_process_profile:capture(Catalog,[{actor,a},{actor,a}],
        #{session=><<"test">>,reset_free=>true,rounds=>1,timeout_ms=>10,interval_ms=>0,budget_ms=>100})),ok.


%% Public network emission must bind inspection to the finalized inbox/import codebooks.
-spec receiver_codebooks_test() -> ok.
receiver_codebooks_test() ->
    #{result := #{network := #{inspection := Inspection},
        transport := #{bundle := #{modules := Modules}, actor_functions := Functions,
            receivers := Receivers}}, files := Files} = hls_protocol_network:emit(#{
        sources => [{"apps/hls_fabric/test/hls_protocol_inbox_fixture.erl", []}],
        topology => {hls_protocol_inbox_fixture, topology, []}, actor_limit => 3,
        inspection => process}),
    #{hls_protocol_inbox_fixture := #{emitted := Emitted, program := Program}} = Modules,
    #{failure_locations := Locations} = xls_actor_program:spec(Program),
    Sites = xls_emitted:sites(Emitted, Locations),
    ?assertMatch([_ | _], [S || S = #{kind := explicit_fail} <- Sites]),
    [#{file := OwnerFile, manifest := #{dslx_sha256 := OwnerHash}}] = Functions,
    Resources = maps:get(<<"resources">>, Inspection),
    ?assertEqual(length(Receivers), length(Resources)),
    lists:foreach(fun({#{file := File, manifest := Manifest}, Resource}) ->
        ReceiverSites = maps:get(failure_sites, Manifest),
        ?assertEqual(Sites, ReceiverSites),
        Expected = json:decode(iolist_to_binary(json:encode(xls_actor_debug:failures(ReceiverSites)))),
        ?assertEqual(Expected, maps:get(<<"failures">>, Resource)),
        ?assertEqual(#{file => OwnerFile, dslx_sha256 => OwnerHash, dslx_dependencies => #{}}, maps:get(owner_import, Manifest)),
        ?assertEqual(hls_generated_files:hash(maps:get(binary_to_list(File), Files)),
            maps:get(dslx_sha256, Manifest))
    end, lists:zip(Receivers, Resources)).


%% A noncontiguous native subset keeps global addresses and excludes unowned codebooks.
-spec partition_catalog_test() -> ok.
partition_catalog_test() ->
    #{result := #{network := #{inspection := Manifest}, transport := Transport}, files := Files} =
        hls_protocol_network:emit(#{sources => [{"apps/hls_fabric/test/hls_protocol_boundary_fixture.erl", []}],
            topology => {hls_protocol_boundary_fixture, topology, []}, actor_limit => 4,
            native_actors => [a, c], inspection => process}),
    ?assertEqual([0, 2], [I || #{<<"id">> := I} <- maps:get(<<"resources">>, Manifest)]),
    #{actors := Actors} = binary_to_term(iolist_to_binary(maps:get("network/inspection.etf", Files))),
    ?assertEqual([{0, a}, {2, c}], [{I, Id} || #{index := I, id := Id} <- Actors]),
    #{receivers := [First | _] = Receivers} = Transport,
    ?assertError({badmatch, false}, hls_protocol_inspection:emit(Transport#{receivers := [First | Receivers]})),
    ?assertException(error, _, hls_protocol_inspection:emit(Transport#{receivers := [First#{module := mismatched_source_module} | tl(Receivers)]})).
