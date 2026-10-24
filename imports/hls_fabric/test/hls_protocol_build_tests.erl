-module(hls_protocol_build_tests).
-moduledoc "In-process source preparation and placement regressions. These check build boundaries and artifact identity, not hardware execution or progress.".
-include_lib("eunit/include/eunit.hrl").

%% Planning different roles must use the prepared source even when its files are no longer present.
-spec reusable_program_test() -> ok.
reusable_program_test() ->
    Root = fresh("prepared-program"),
    ok = file:make_dir(Root),
    Files = ["hls_protocol_network_fixture.erl", "hls_protocol_inbox_fixture.erl"],
    Sources = [begin
        Target = filename:join(Root, File),
        {ok, _} = file:copy(filename:join("test", File), Target),
        {Target, []}
    end || File <- Files],
    Program = hls_protocol_transport:prepare(#{sources => Sources,
        topology => {hls_protocol_network_fixture, framed, []}, actor_limit => 3}),
    lists:foreach(fun({File, _}) -> ok = file:rename(File, File ++ ".prepared") end, Sources),
    North = hls_protocol_transport:plan(Program, #{native_actors => [left, sink]}),
    South = hls_protocol_transport:plan(Program, #{native_actors => [right]}),
    #{bundle := NorthBundle, fabric := #{sources := NorthActors}} = hls_protocol_transport:descriptor(North),
    #{bundle := SouthBundle, fabric := #{sources := SouthActors}} = hls_protocol_transport:descriptor(South),
    ?assertEqual(hls_protocol_transport:bundle(Program), NorthBundle),
    ?assertEqual(NorthBundle, SouthBundle),
    ?assertEqual([0, 2], [I || #{index := I} <- NorthActors]),
    ?assertEqual([1], [I || #{index := I} <- SouthActors]),
    %% A placement API must not silently accept a request to change its source configuration.
    ?assertError({unsupported_transport_options, [sources]},
        hls_protocol_transport:plan(Program, #{sources => Sources})),
    Before = relative_files(Root),
    Output = #{files := Generated, result := Descriptor} = hls_protocol_transport:emit(North),
    ?assertEqual(hls_protocol_transport:descriptor(North), Descriptor),
    ?assertEqual(Output, hls_protocol_transport:emit(North)),
    ?assertEqual(Before, relative_files(Root)),
    First = filename:join(Root, "first"), Second = filename:join(Root, "second"),
    ?assertEqual(Descriptor, hls_generated_files:write(Output, First)),
    ?assertEqual(Descriptor, hls_protocol_transport:write(North, Second)),
    FilesWritten = relative_files(First),
    ?assertEqual(lists:sort(maps:keys(Generated)), FilesWritten),
    ?assertEqual(FilesWritten, relative_files(Second)),
    lists:foreach(fun(File) ->
        Bytes = iolist_to_binary(maps:get(File, Generated)),
        ?assertEqual({ok, Bytes}, file:read_file(filename:join(First, File))),
        ?assertEqual({ok, Bytes}, file:read_file(filename:join(Second, File)))
    end, FilesWritten),
    %% Inspection restriction follows the actual planned cut, not a second native_actors flag.
    ?assertError(partition_inspection_unavailable,
        hls_protocol_network:write(South, #{inspection => process}, filename:join(Root, "inspection"))),
    ?assertEqual(false, filelib:is_dir(filename:join(Root, "inspection"))),
    Override = filename:join(Root, "override"),
    ?assertError({unsupported_network_options, [native_actors]},
        hls_protocol_network:write(South, #{native_actors => [left]}, Override)),
    ?assertError({unsupported_bridge_options, [sources]},
        hls_protocol_bridge:write(South, #{host => 1, service => 7, control => rectangle, sources => Sources}, Override)),
    ?assertEqual(false, filelib:is_dir(Override)),
    ok.

%% Filename input is a trusted source map; emission has no output side effects and hashes its returned bytes.
-spec emission_inputs_test() -> ok.
emission_inputs_test() ->
    Root = fresh("emission-inputs"),
    ok = file:make_dir(Root),
    Config = #{sources => [{"test/hls_protocol_network_fixture.erl", []}],
        topology => {hls_protocol_network_fixture, isolated, []}, actor_limit => 1},
    Filename = filename:join(Root, "source.config"),
    ok = file:write_file(Filename, io_lib:format("~tp.~n", [Config]), [exclusive]),
    Before = relative_files(Root),
    #{files := FromMap, result := #{network := Network}} = hls_protocol_network:emit(Config),
    #{files := FromFile, result := #{network := Network}} = hls_protocol_network:emit(Filename),
    ?assertEqual(Before, relative_files(Root)),
    %% Compiler-origin references in trusted ETF plans need not survive another preparation.
    ?assertEqual(hardware_files(FromMap), hardware_files(FromFile)),
    #{dslx_sha256 := Hash, components := Components} = Network,
    ?assertEqual(Hash, digest(maps:get("network/network.x", FromMap))),
    lists:foreach(fun(#{file := File, sha256 := Expected}) ->
        ?assertEqual(Expected, digest(maps:get(binary_to_list(File), FromMap)))
    end, Components),
    Saved = filename:join(Root, "saved.etf"),
    ok = file:write_file(Saved, term_to_binary(Config, [deterministic]), [exclusive]),
    ?assertException(error, _, hls_protocol_network:emit(Saved)),
    ok.

%% Compare generated hardware independently of process-local compiler provenance in plans.
-spec hardware_files(hls_generated_files:files()) -> #{string() => binary()}.
hardware_files(Files) ->
    maps:from_list([{File, iolist_to_binary(Bytes)} || {File, Bytes} <- maps:to_list(Files),
        lists:member(filename:extension(File), [".x", ".sv"])]).

%% Use the standard hash operation independently of the file-bundle helper.
-spec digest(iodata()) -> binary().
digest(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).

%% All generated actor files and sidecars are bound, not just one representative DSLX module.
-spec relative_files(file:filename()) -> [file:filename()].
relative_files(Root) ->
    Prefix = Root ++ "/",
    lists:sort(filelib:fold_files(Root, ".*", true,
        fun(File, Acc) -> [lists:nthtail(length(Prefix), File) | Acc] end, [])).

%% Fresh disposable output avoids both overwriting old evidence and dependence on test order.
-spec fresh(string()) -> file:filename().
fresh(Name) -> filename:join("_build", Name ++ "-" ++ integer_to_list(erlang:system_time(nanosecond))).
