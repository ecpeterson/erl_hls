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
    First = filename:join(Root, "first"), Second = filename:join(Root, "second"),
    ?assertEqual(false, filelib:is_dir(First)),
    ?assertEqual(hls_protocol_transport:descriptor(North), hls_protocol_transport:emit(North, First)),
    ?assertEqual(hls_protocol_transport:descriptor(North), hls_protocol_transport:emit(North, Second)),
    FilesWritten = relative_files(First),
    ?assertEqual(FilesWritten, relative_files(Second)),
    lists:foreach(fun(File) ->
        ?assertEqual(file:read_file(filename:join(First, File)), file:read_file(filename:join(Second, File)))
    end, FilesWritten),
    %% Inspection restriction follows the actual planned cut, not a second native_actors flag.
    ?assertError(partition_inspection_unavailable,
        hls_protocol_network:emit(South, #{inspection => process}, filename:join(Root, "inspection"))),
    ?assertEqual(false, filelib:is_dir(filename:join(Root, "inspection"))),
    Override = filename:join(Root, "override"),
    ?assertError({unsupported_network_options, [native_actors]},
        hls_protocol_network:emit(South, #{native_actors => [left]}, Override)),
    ?assertError({unsupported_bridge_options, [sources]},
        hls_protocol_bridge:emit(South, #{host => 1, service => 7, control => rectangle, sources => Sources}, Override)),
    ?assertEqual(false, filelib:is_dir(Override)),
    ok.

%% All generated actor files and sidecars are bound, not just one representative DSLX module.
-spec relative_files(file:filename()) -> [file:filename()].
relative_files(Root) ->
    Prefix = Root ++ "/",
    lists:sort(filelib:fold_files(Root, ".*", true,
        fun(File, Acc) -> [lists:nthtail(length(Prefix), File) | Acc] end, [])).

%% Fresh disposable output avoids both overwriting old evidence and dependence on test order.
-spec fresh(string()) -> file:filename().
fresh(Name) -> filename:join("_build", Name ++ "-" ++ integer_to_list(erlang:system_time(nanosecond))).
