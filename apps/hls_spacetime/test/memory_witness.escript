#!/usr/bin/env escript
%%! +S 2:2
%% Optional real-RTL fixture: no arguments skip; explicit bench/RAM RTL and a fresh directory opt in.
-mode(compile).

%% Inputs are trusted local source paths; tool failures retain the fresh diagnostic directory.
-spec main([string()]) -> ok | no_return().
main([]) ->
    io:format("SKIP optional RAM witness: supply BENCH_RTL, RAM_RTL and FRESH_OUTPUT_DIRECTORY~n");
main([BenchPath, RamPath, OutputPath]) ->
    try
        Root = filename:dirname(filename:dirname(filename:absname(escript:script_name()))),
        Ram = filename:absname(RamPath),
        Bench = filename:absname(BenchPath),
        Stage = filename:absname(OutputPath),
        true = filelib:is_regular(Ram),
        true = filelib:is_regular(Bench),
        ok = file:make_dir(Stage),
        run(Root, Bench, Ram, Stage)
    catch
        Class:Reason:Stack ->
            io:format(standard_error, "RAM witness failed: ~p:~p~n~p~n", [Class, Reason, Stack]),
            halt(1)
    end;
main(_) ->
    io:format(standard_error, "usage: memory_witness.escript BENCH_RTL RAM_RTL FRESH_OUTPUT_DIRECTORY~n", []),
    halt(2).

%% The compiler owns both RTL inputs; the caller supplies them, without copies or fetching.
-spec run(file:filename(), file:filename(), file:filename(), file:filename()) -> ok.
run(Root, Bench, Ram, Stage) ->
    Iverilog = executable("iverilog"),
    Vvp = executable("vvp"),
    Binary = filename:join(Stage, "memory"),
    Trace = filename:join(Stage, "memory.term"),
    _ = tool(Iverilog, ["-g2012", "-s", "spacetime_memory_tb", "-o", Binary, Bench, Ram], Stage),
    _ = tool(Vvp, [Binary, "+TRACE=" ++ Trace], Stage),
    Observer = filename:join([Root, "test", "hls_spacetime_memory_fixture.erl"]),
    Rejects = filename:join([Root, "test", "hls_spacetime_memory_fixture_tests.erl"]),
    Sources = filelib:wildcard(filename:join([Root, "src", "*.erl"])) ++ [Observer, Rejects],
    lists:foreach(fun(Path) -> compile_source(Path, Stage) end, Sources),
    Build = #{source => digest([Bench, Ram]), rtl => digest([Binary]),
        observation => digest([Observer])},
    Result = hls_spacetime_memory_fixture:read(Trace, Build),
    14 = hls_spacetime_memory_fixture_tests:check(Trace, Build),
    _ = hls_spacetime_artifact:write_bundle(maps:get(bundle, Result),
        filename:join(Stage, "bundle")),
    Toolchain = #{otp => list_to_binary(erlang:system_info(otp_release)),
        iverilog => tool_identity(Iverilog, Stage), vvp => tool_identity(Vvp, Stage)},
    Review = #{build => Build, tools => Toolchain, ram_rtl => list_to_binary(Ram), bench_rtl => list_to_binary(Bench),
        summary => maps:without([bundle], Result), negative_cases => 14,
        evidence => simulation_witness},
    ok = file:write_file(filename:join(Stage, "memory-review.json"), json:encode(Review)),
    io:format("~p~n", [maps:without([bundle], Result)]).

%% Loading freshly compiled code needs no compiler checkout or persistent application process.
-spec compile_source(file:filename(), file:filename()) -> ok.
compile_source(Path, Stage) ->
    {ok, Module, Bytes} = compile:file(Path, [binary, debug_info, warnings_as_errors,
        report_errors, report_warnings]),
    ok = file:write_file(filename:join(Stage, atom_to_list(Module) ++ ".beam"), Bytes),
    {module, Module} = code:load_binary(Module, Path, Bytes),
    ok.

%% Hash a deterministic named closure; names distinguish separate inputs with equal contents.
-spec digest([file:filename()]) -> binary().
digest(Paths) ->
    Rows = [[list_to_binary(filename:basename(Path)), hash_file(Path)] || Path <- Paths],
    binary:encode_hex(crypto:hash(sha256, iolist_to_binary(json:encode(Rows))), lowercase).

%% Exact executable bytes accompany human-readable versions in the retained witness.
-spec tool_identity(file:filename(), file:filename()) -> map().
tool_identity(Path, Stage) ->
    #{path => list_to_binary(Path), sha256 => hash_file(Path),
        version => tool(Path, ["-V"], Stage)}.

%% The fresh witness files are small; file errors stop before an identity is published.
-spec hash_file(file:filename()) -> binary().
hash_file(Path) ->
    {ok, Bytes} = file:read_file(Path),
    binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).

%% Missing optional tools are errors only after the caller explicitly opts into this witness.
-spec executable(string()) -> file:filename().
executable(Name) ->
    case os:find_executable(Name) of
        false -> error({missing_tool, Name});
        Path -> Path
    end.

%% Arguments bypass shell parsing; an outer process-group guard must bound child resources.
-spec tool(file:filename(), [string()], file:filename()) -> binary().
tool(Path, Arguments, Stage) ->
    Port = open_port({spawn_executable, Path}, [binary, exit_status, stderr_to_stdout,
        use_stdio, {args, Arguments}, {cd, Stage}]),
    receive_tool(Port, erlang:monotonic_time(millisecond) + 120000, [], 0).

%% Bound both retained diagnostics and elapsed time; a failure never certifies a complete trace.
-spec receive_tool(port(), integer(), [binary()], non_neg_integer()) -> binary().
receive_tool(Port, Deadline, Reverse, Size) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Bytes}} when Size + byte_size(Bytes) =< 8 * 1024 * 1024 ->
            receive_tool(Port, Deadline, [Bytes | Reverse], Size + byte_size(Bytes));
        {Port, {data, _}} ->
            port_close(Port), error(tool_output_limit);
        {Port, {exit_status, 0}} ->
            iolist_to_binary(lists:reverse(Reverse));
        {Port, {exit_status, Code}} ->
            error({tool_exit, Code, iolist_to_binary(lists:reverse(Reverse))})
    after Remaining ->
        port_close(Port), error(tool_timeout)
    end.
