-module(hls_runtime_package_tests).
-moduledoc "Runs compiled actors and retained codecs with only the deployed runtime on the code path.".
-include_lib("eunit/include/eunit.hrl").
%% Isolated child VM entry point.
-export([witness/0]).

%% The child VM cannot accidentally satisfy a runtime dependency from the compiler checkout.
-spec standalone_runtime_test_() -> {timeout, pos_integer(), fun(() -> ok)}.
standalone_runtime_test_() ->
    {timeout, 30, fun standalone_runtime/0}.

%% Copy only the witness and already compiled actor; no source analysis is available in the child.
-spec standalone_runtime() -> ok.
standalone_runtime() ->
    Dir = filename:absname(filename:join(["_build", "runtime-package-test",
        integer_to_list(erlang:unique_integer([positive]))])),
    ok = filelib:ensure_dir(filename:join(Dir, "fixture.beam")),
    try
        lists:foreach(fun(Module) ->
            {Module, Beam, _} = code:get_object_code(Module),
            ok = file:write_file(filename:join(Dir, atom_to_list(Module) ++ ".beam"), Beam)
        end, [?MODULE, hls_reply_fixture]),
        Port = open_port({spawn_executable, os:find_executable("erl")},
            [binary, exit_status, stderr_to_stdout,
             {env, [{"ERL_LIBS", false}, {"ERL_AFLAGS", false}, {"ERL_FLAGS", "+S 2:2"}]},
             {args, ["-noshell", "-pa", filename:join(code:lib_dir(hls_runtime), "ebin"), Dir,
                 "-eval", "ok = hls_runtime_package_tests:witness(), halt(0)."]}]),
        await(Port, <<>>)
    after
        ok = file:del_dir_r(Dir)
    end.

%% Retain diagnostic output on failure and bound an accidentally blocked child VM.
-spec await(port(), binary()) -> ok.
await(Port, Output) ->
    receive
        {Port, {data, Bytes}} -> await(Port, <<Output/binary, Bytes/binary>>);
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, Status}} -> error({runtime_witness_failed, Status, Output})
    after 20000 ->
        port_close(Port),
        error({runtime_witness_timeout, Output})
    end.

%% Child-process entry point; this is a finite CPU/codec witness, not device execution.
-doc "Checks the standalone runtime dependency closure, a transformed server, retained nested codecs and canonical framing.".
-spec witness() -> ok.
witness() ->
    [non_existing = code:which(Module) || Module <-
        [hls_compile, hls_pack, hls_source, hls_service_contract, xls_parse, xls_type]],
    {ok, _} = application:ensure_all_started(hls_runtime),
    undefined = whereis(erl_hls_sup),
    {ok, #{calls := #{read := [small]}}} = hls_service_schema:from_module(hls_reply_fixture),
    {ok, Server} = hls_gs:start_link(hls_reply_fixture, []),
    try
        {small, 7} = gen_server:call(Server, {read, 0}),
        {large, 23, 7} = gen_server:call(Server, {query, 1, 23}),
        {small, 23} = gen_server:call(Server, {read, 0})
    after
        ok = hls_gs:stop(Server)
    end,
    Codec = hls_record_codec:bind(message,
        [{values, hls_vec:vector(hls_serial:counter(3), 2)},
         {flag, hls_bool:bool()}]),
    Packed = hls_record_codec:pack(Codec, {message, [9, -1], true}),
    {{message, [1, 7], true}, <<>>} = hls_record_codec:unpack(Codec, Packed),
    Layout = hls_frame_layout:new(1),
    Frame = hls_frame_layout:pack(Layout, 11, <<17:32/little>>),
    {#{op := 11, payload_words := 1}, <<17:32/little>>} = hls_frame_layout:unpack(Layout, Frame),
    [0, 8, 16, 24] = [hls_frame_layout:header_offset(Name) ||
        {Name, _} <- hls_frame_layout:header_fields()],
    ok.
