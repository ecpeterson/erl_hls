-module(hls_compile_topology_tests).
-moduledoc "Topology packaging retains source preprocessing and rejects incomplete build declarations before publication.".
-include_lib("eunit/include/eunit.hrl").

%% Relative paths are anchored to the config, even when the command runs elsewhere.
-spec preprocessing_context_test() -> ok.
preprocessing_context_test() ->
    hls_source_fixture:with_source(fun(_Path, Directory) ->
        Graph = filename:join(Directory, "packaging_topology.erl"),
        ok = file:write_file(Graph,
            "-module(packaging_topology).\n-export([topology/0]).\n"
            "topology() -> #{version=>1, actors=>#{cell=>hls_source_context_fixture},"
            "families=>#{}, route_relations=>[], startup=>[],"
            "ingresses=>[{input,{rectangle,[1,1]},"
            "[{cell,[message],[{actor,cell,{at,[0,0]}}]}]}],"
            "externals=>[{result,out,[message]}],"
            "routes=>[{{cell,out},[{external,result}]}]}.\n"),
        Build = filename:join(Directory, "build.config"),
        Config = #{sources => [{"src/hls_source_context_fixture.erl",
            [{i,"headers"},{d,'WIDE'},{d,'INITIAL',7},{d,'CAPACITY',2}]},
            {"packaging_topology.erl", []}], topology => packaging_topology,
            profile => #{name => source_context_top, channel_depth => 1,
                actor_egress_depth => burst, frame_payload_words => 5},
            pipeline_stages => 3},
        ok = file:write_file(Build, io_lib:format("~tp.~n", [Config])),
        Output = filename:join(Directory, "bundle"),
        try
            #{units := [Unit], metadata := #{frame_abi := Abi}} = hls_compile:topology(Build, Output),
            ?assertEqual(5, maps:get(payload_words, Abi)),
            ?assert(lists:member(<<"--pipeline_stages=3">>, maps:get(codegen_flags, Unit))),
            ?assertEqual(64, hls_source_context_fixture:pack_width(cell)),
            {ok, Actor} = file:read_file(filename:join([Output,"actors","hls_source_context_fixture.x"])),
            ?assertNotEqual(nomatch, binary:match(Actor, <<"value : u64">>)),
            ?assertNotEqual(nomatch, binary:match(Actor, <<"@erl">>))
        after
            code:purge(packaging_topology),
            code:delete(packaging_topology)
        end
    end).

%% Build mistakes reject before any bundle can be mistaken for a complete artifact.
-spec invalid_build_test() -> ok.
invalid_build_test() ->
    Output = filename:join("_build", "invalid-topology-" ++
        binary_to_list(binary:encode_hex(crypto:strong_rand_bytes(12), lowercase))),
    {ok, [Config]} = file:consult("src/examples/telemetry/topology.config"),
    Sources = [{filename:join("src/examples/telemetry", File), Options}
        || {File, Options} <- maps:get(sources, Config)],
    Build = Config#{sources := Sources},
    Cases = [{#{}, config}, {Build#{unexpected => true}, unknown_options},
        {Build#{pipeline_stages => 0}, pipeline_stages},
        {Build#{sources := [bad]}, source},
        {Build#{dslx_path => invalid}, import_path},
        {Build#{sources := [hd(Sources), hd(Sources)]}, duplicate_module},
        {Build#{sources := tl(Sources)}, missing_source}],
    lists:foreach(fun({Invalid, Code}) ->
        ?assertException(error, {hls_diagnostic, #{code := Code}},
            hls_compile:topology(Invalid, Output)),
        ?assertNot(filelib:is_dir(Output))
    end, Cases).
