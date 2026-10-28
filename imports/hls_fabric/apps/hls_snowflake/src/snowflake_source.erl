-module(snowflake_source).
-moduledoc "Source-protocol example selected through hls_source_build. Uses the ordinary Snowflake actors and geometry; compiler scheduling and source publication remain in the generic build frontend.".
%% Generic build inputs and the application's bounded topology.
-export([config/0, topology/0]).

-doc "Returns the installed D2/H2 source-protocol configuration: twelve vertices, a flat barrier, explicit startup and bounded coordinator storage. Paths and includes are resolved from hls_snowflake, independently of the caller's directory.".
-spec config() -> hls_source_config:boundary().
config() ->
    Root = code:lib_dir(hls_snowflake),
    Includes = [{i, filename:join(Root, "include")}],
    Sources = [
        {snowflake_geometry, []},
        {snowflake_actor_topology, []},
        {snowflake_vertex, []},
        {snowflake_coordinator, [
            {d, 'SNOWFLAKE_COORDINATOR_SOURCES', 12},
            {d, 'SNOWFLAKE_COORDINATOR_MAILBOX', 16}
        ]},
        {?MODULE, []}
    ],
    #{
        sources => [
            {filename:join([Root, "src", atom_to_list(Module) ++ ".erl"]), Includes ++ Options}
         || {Module, Options} <- Sources
        ],
        topology => {?MODULE, topology, []},
        actor_limit => 13,
        activation => explicit_start
    }.

-doc "Selects independently buffered coordinator command copies. Each vertex receives commands in sender order and acknowledges completion before the next round; the logical actor graph is unchanged.".
-spec topology() -> hls_topology:spec().
topology() ->
    Topology =
        #{routes := [{{coordinator, command}, queued, Recipients} | Rest]} =
        snowflake_actor_topology:topology(2, 2),
    Topology#{routes := [{{coordinator, command}, buffered, Recipients} | Rest]}.
