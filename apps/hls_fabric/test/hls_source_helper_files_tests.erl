-module(hls_source_helper_files_tests).
-moduledoc "Generated source helpers survive owner composition, pure bundle emission and standalone writes.".
-include_lib("eunit/include/eunit.hrl").

%% A source helper must accompany its actor through each public packaging route.
-spec source_helper_files_test_() -> term().
source_helper_files_test_() -> {timeout, 60, fun source_helper_files/0}.

%% Two receiver facades share one checked helper file; existing conflicting bytes reject.
-spec source_helper_files() -> ok.
source_helper_files() ->
    Root = filename:join(["_build", "source-helper-files-" ++
        integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
        integer_to_list(erlang:unique_integer([positive, monotonic]))]),
    File = filename:join(Root, "hls_helper_file_actor.erl"),
    ok = filelib:ensure_dir(File),
    {ok, Original} = file:read_file("apps/hls_fabric/test/hls_scheduler_build_fixture.erl"),
    Renamed = binary:replace(Original, <<"hls_scheduler_build_fixture">>, <<"hls_helper_file_actor">>, [global]),
    Source = binary:replace(Renamed, <<"Cell#cell{value = Value}">>,
        <<"Cell#cell{value = hls_helper_file_math:adjust(Value)}">>),
    ok = file:write_file(File, Source, [exclusive]),
    ok = file:write_file(filename:join(Root, "hls_helper_file_math.erl"),
        <<"-module(hls_helper_file_math).\n-export([adjust/1]).\n"
          "-spec adjust(hls_nums:u8()) -> hls_nums:u8().\nadjust(Value) -> Value bxor 1.\n">>, [exclusive]),
    Actor = #{emitted := Emitted} = hls_local_actor:compile(File, []),
    Dependencies = xls_emitted:dependencies(Emitted),
    ?assertEqual(1, map_size(Dependencies)),
    [{Dependency, Contents}] = maps:to_list(Dependencies),
    ExpectedHashes = #{list_to_binary(Dependency) => hls_generated_files:hash(Contents)},
    ?assertEqual(ExpectedHashes, maps:get(dslx_dependencies, hls_local_actor:manifest(Actor))),
    Files = hls_local_actor:emit(Actor, "nested/owner.x"),
    ?assertEqual(Contents, maps:get("nested/" ++ Dependency, Files)),
    Imported = #{emitted := Receiver} = xls_local_owner:import_owner(Actor, <<"actors/owner.x">>),
    ?assertEqual(Dependencies, xls_emitted:dependencies(Receiver)),
    ?assertEqual(ExpectedHashes, maps:get(dslx_dependencies, maps:get(owner_import, Imported))),
    First = filename:join(Root, "output/first.x"),
    _ = hls_local_actor:write(Actor, First),
    _ = hls_local_actor:write(Actor, filename:join(Root, "output/second.x")),
    Shared = filename:join([Root, "output", Dependency]),
    ?assertEqual({ok, Contents}, file:read_file(Shared)),
    ok = file:write_file(Shared, <<"different helper bytes">>),
    Rejected = filename:join(Root, "output/rejected.x"),
    ?assertError({local_actor_dependency_mismatch, Shared}, hls_local_actor:write(Actor, Rejected)),
    ?assertNot(filelib:is_file(Rejected)),
    ?assertNot(filelib:is_file(Rejected ++ ".json")),
    Config = #{sources => [{File, []}], topology => {hls_helper_file_actor, topology, []},
        actor_limit => 2, frame_payload_words => 1},
    #{files := Transport, result := #{receivers := Receivers}} = hls_protocol_transport:emit(Config),
    ?assertEqual(2, length(Receivers)),
    ?assertEqual(Contents, maps:get("actors/" ++ Dependency, Transport)),
    Scheduler = hls_scheduler_build:plan((maps:without([actor_limit, frame_payload_words], Config))#{
        placement => #{name => helper_scheduler, channel_depth => 1, actor_egress_depth => burst,
            scheduler_groups => #{}}}),
    Bundle = filename:join(Root, "scheduler"),
    _ = hls_scheduler_build:write(Scheduler, Bundle),
    {ok, SchedulerContents} = file:read_file(filename:join([Bundle, "actors", Dependency])),
    {ok, Json} = file:read_file(filename:join([Bundle, "actors", "hls_helper_file_actor.x.json"])),
    #{<<"dslx_dependencies">> := SchedulerHashes} = json:decode(Json),
    ?assertEqual(#{list_to_binary(Dependency) => hls_generated_files:hash(SchedulerContents)}, SchedulerHashes),
    ok.
