-module(xls_protocol_spacetime_identity_tests).
-moduledoc "Checks that observation-plan identity survives equivalent map construction and persistence into a fresh Erlang process.".
-include_lib("eunit/include/eunit.hrl").

%% Large nested maps exercise hashed-map serialization rather than only small flat maps.
-spec equivalent_maps_test() -> ok.
equivalent_maps_test() ->
    Pairs = [{integer_to_binary(I), #{ordinal => I, tags => [kept, I]}} || I <- lists:seq(0, 79)],
    A = fixture(maps:from_list(Pairs)),
    B = fixture(maps:from_list(lists:reverse(Pairs))),
    ?assertEqual(A, B),
    ?assertEqual(
        xls_protocol_spacetime:observation_digest(A),
        xls_protocol_spacetime:observation_digest(B)
    ),
    ?assertNotEqual(
        xls_protocol_spacetime:observation_digest(A),
        xls_protocol_spacetime:observation_digest(A#{inputs := #{rtl => <<"changed">>}})
    ).

%% The previous byte-encoding hash changed when an equal plan was decoded elsewhere.
-spec fresh_process_test_() -> {timeout, pos_integer(), fun(() -> ok)}.
fresh_process_test_() -> {timeout, 15, fun fresh_process/0}.

%% A child VM loads only the adapter module and trusted plan; no simulator is involved.
-spec fresh_process() -> ok.
fresh_process() ->
    Plan = fixture(maps:from_list([{I, #{value => I * I}} || I <- lists:seq(0, 79)])),
    Expected = xls_protocol_spacetime:observation_digest(Plan),
    Directory = filename:absname(
        filename:join([
            "_build",
            "identity-fixture",
            integer_to_list(erlang:unique_integer([positive]))
        ])
    ),
    Path = filename:join(Directory, "plan.etf"),
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, term_to_binary(Plan)),
    try
        Eval = lists:flatten(
            io_lib:format(
                "{ok,B}=file:read_file(~tp), P=binary_to_term(B), "
                "io:put_chars(xls_protocol_spacetime:observation_digest(P)), halt().",
                [Path]
            )
        ),
        Port = open_port(
            {spawn_executable, filename:join([code:root_dir(), "bin", "erl"])},
            [
                binary,
                exit_status,
                stderr_to_stdout,
                {env, [{"ERL_LIBS", false}, {"ERL_AFLAGS", false}, {"ERL_FLAGS", false}]},
                {args, [
                    "+S",
                    "2:2",
                    "+A",
                    "2",
                    "-noshell",
                    "-pa",
                    filename:dirname(code:which(xls_protocol_spacetime)),
                    "-eval",
                    Eval
                ]}
            ]
        ),
        ?assertEqual(Expected, await(Port, erlang:monotonic_time(millisecond) + 10000, <<>>))
    after
        ok = file:del_dir_r(Directory)
    end.

%% Bound the process duration and retained diagnostics even on a broken startup.
-spec await(port(), integer(), binary()) -> binary().
await(Port, Deadline, Output) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Bytes}} ->
            Combined = <<Output/binary, Bytes/binary>>,
            case byte_size(Combined) =< 65536 of
                true ->
                    await(Port, Deadline, Combined);
                false ->
                    port_close(Port),
                    error(identity_child_output_limit)
            end;
        {Port, {exit_status, 0}} ->
            Output;
        {Port, {exit_status, Status}} ->
            error({identity_child_failed, Status, Output})
    after Remaining ->
        port_close(Port),
        error({identity_child_timeout, Output})
    end.

%% Input metadata can contain differently ordered maps without changing observation meaning.
-spec fixture(map()) -> xls_protocol_spacetime:plan().
fixture(Metadata) ->
    #{
        schema => 1,
        signals => [],
        actors => [],
        registers => [],
        state => [],
        unsupported => [],
        inputs => #{
            rtl => <<"rtl">>,
            source_build => <<"source">>,
            implementation => <<"implementation">>,
            metadata => Metadata
        }
    }.
