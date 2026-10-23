-module(hls_protocol_inspection_tests).
-moduledoc "Checks the public inspection build selection and exact source-to-catalog binding.".
-include_lib("eunit/include/eunit.hrl").

%% Unsupported modes fail before file reads or output creation.
-spec invalid_mode_test() -> ok.
invalid_mode_test() ->
    ?assertError({unsupported_protocol_inspection,trace},hls_protocol_network:write(#{inspection=>trace},"unused")),
    ?assertEqual(none,hls_protocol_inspection:mode(none)).

%% The actual application command produces one resource for every compiled source actor.
-spec catalog_test() -> ok.
catalog_test() ->
    Path=filename:join("_build","inspection-binding-"++integer_to_list(erlang:system_time(nanosecond))),
    #{eligible:=false}=hls_protocol_application:write(#{sources=>[{"test/hls_protocol_boundary_fixture.erl",[]}],
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
