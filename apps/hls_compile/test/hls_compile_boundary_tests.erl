-module(hls_compile_boundary_tests).
-moduledoc """
Exercises computation synthesis without Fabric, target, facade or started
runtime services.
""".

-include_lib("eunit/include/eunit.hrl").

%% Isolated child-VM witness.
-export([isolated_witness/0]).

%% Source analysis and XLS computation lowering stop at the compiler artifact boundary.
-spec computation_only_lowering_test() -> ok.
computation_only_lowering_test() ->
    Artifact = xls_parse:to_artifact(
        "apps/hls_compile/test/hls_compile_boundary_fixture.erl", #{}
    ),
    Source = xls_emitted:bytes(Artifact),
    ?assertNotEqual(nomatch, binary:match(Source, <<"pub proc Top">>)),
    ?assertNotEqual(nomatch, binary:match(Source, <<"struct ActorState">>)).

%% Loading a runtime-owned value provider must not start its OTP application or supervisor.
-spec computation_without_runtime_services_test_() ->
    {timeout, pos_integer(), fun(() -> ok)}.
computation_without_runtime_services_test_() ->
    {timeout, 30, fun computation_without_runtime_services/0}.

%% Copy only this witness; production code paths are limited to the declared compiler closure.
-spec computation_without_runtime_services() -> ok.
computation_without_runtime_services() ->
    Directory = filename:absname(
        filename:join(
            "_build",
            "compiler-runtime-isolation-" ++
                integer_to_list(erlang:unique_integer([positive]))
        )
    ),
    ok = filelib:ensure_dir(filename:join(Directory, "placeholder")),
    try
        {?MODULE, Beam, _Filename} = code:get_object_code(?MODULE),
        ok = file:write_file(filename:join(Directory, atom_to_list(?MODULE) ++ ".beam"), Beam),
        Port = open_port(
            {spawn_executable, os:find_executable("erl")},
            [
                binary,
                exit_status,
                stderr_to_stdout,
                {env, [{"ERL_LIBS", false}, {"ERL_AFLAGS", false}, {"ERL_FLAGS", "+S 2:2"}]},
                {args, [
                    "-noshell",
                    "-pa",
                    filename:join(code:lib_dir(hls_core), "ebin"),
                    filename:join(code:lib_dir(hls_runtime), "ebin"),
                    filename:join(code:lib_dir(hls_compile), "ebin"),
                    Directory,
                    "-eval",
                    "ok = hls_compile_boundary_tests:isolated_witness(), halt(0)."
                ]}
            ]
        ),
        await(Port, <<>>)
    after
        ok = file:del_dir_r(Directory)
    end.

%% Retain diagnostics and bound a child that unexpectedly waits on a runtime process.
-spec await(port(), binary()) -> ok.
await(Port, Output) ->
    receive
        {Port, {data, Bytes}} -> await(Port, <<Output/binary, Bytes/binary>>);
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, Status}} -> error({compiler_isolation_failed, Status, Output})
    after 20000 ->
        port_close(Port),
        error({compiler_isolation_timeout, Output})
    end.

-doc """
Lowers a retained-handle descriptor with runtime code available but no runtime
application or service started.
""".
-spec isolated_witness() -> ok.
isolated_witness() ->
    [non_existing = code:which(Module) ||
        Module <- [hls_compile, hls_compile_cli, xls_fabric_topology_dslx, hls_artifact_bundle]],
    RuntimeProvider = code:which(hls_gs),
    true = is_list(RuntimeProvider),
    false = code:is_loaded(hls_gs),
    false = code:is_loaded(hls_fabric_sup),
    undefined = whereis(hls_fabric_sup),
    Started = application:which_applications(),
    false = lists:keymember(hls_runtime, 1, Started),
    false = lists:keymember(hls_compile, 1, Started),
    Artifact = xls_parse:to_artifact(
        "apps/hls_compile/test/hls_compile_runtime_provider_fixture.erl", #{}
    ),
    Source = xls_emitted:bytes(Artifact),
    true = binary:match(Source, <<"pub proc Top">>) =/= nomatch,
    {file, RuntimeProvider} = code:is_loaded(hls_gs),
    false = code:is_loaded(hls_fabric_sup),
    undefined = whereis(hls_fabric_sup),
    Started = application:which_applications(),
    ok.
