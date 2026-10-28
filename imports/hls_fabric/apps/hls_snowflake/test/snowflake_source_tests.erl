-module(snowflake_source_tests).
-moduledoc "The supported Snowflake build keeps source ownership and its finite integration boundary explicit.".
-include_lib("eunit/include/eunit.hrl").

%% Package relocation cannot silently drop an actor source or its include context.
-spec installed_configuration_test() -> ok.
installed_configuration_test() ->
    #{sources := Sources, topology := {snowflake_source, topology, []},
        actor_limit := 13, activation := explicit_start} = snowflake_source:config(),
    Root = code:lib_dir(hls_snowflake),
    Includes = filename:join(Root, "include"),
    ?assert(lists:all(fun({Path, Options}) -> filelib:is_file(Path) andalso
        lists:member({i, Includes}, Options) end, Sources)),
    ?assertEqual(["snowflake_actor_topology.erl", "snowflake_coordinator.erl",
        "snowflake_geometry.erl", "snowflake_source.erl", "snowflake_vertex.erl"],
        lists:sort([filename:basename(Path) || {Path, _} <- Sources])),
    [Coordinator] = [Options || {Path, Options} <- Sources,
        filename:basename(Path) =:= "snowflake_coordinator.erl"],
    ?assert(lists:member({d, 'SNOWFLAKE_COORDINATOR_SOURCES', 12}, Coordinator)),
    ?assert(lists:member({d, 'SNOWFLAKE_COORDINATOR_MAILBOX', 16}, Coordinator)).

%% The supported boundary changes transport buffering, not the existing actor population or startup.
-spec buffered_boundary_test() -> ok.
buffered_boundary_test() ->
    Original = #{routes := [{{coordinator, command}, queued, Recipients} | Rest]} =
        snowflake_actor_topology:topology(2, 2),
    ?assertEqual(Original#{routes := [{{coordinator, command}, buffered, Recipients} | Rest]},
        snowflake_source:topology()).
