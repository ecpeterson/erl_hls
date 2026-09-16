-module(packed_samples_live).
-export([run/1]).

run(Stage) ->
    {ok, App} = hls_fabric:start_link(filename:join(Stage, "app_tx"), filename:join(Stage, "app_rx")),
    {ok, Management} = hls_fabric:start_link(filename:join(Stage, "debug_tx"), filename:join(Stage, "debug_rx")),
    {ok, Hardware} = hls_gs:start_link(packed_samples, [], [{fabric, App, 1}]),
    {ok, CPU} = hls_gs:start_link(packed_samples, [], []),
    {ok, Debug} = hls_debug:start_link(packed_samples, {fabric, Management, 1}),
    try
        Read = {read, 0},
        Request = gen_server:send_request(Hardware, Read),
        Counters = await_stall(Debug, erlang:monotonic_time(millisecond) + 10000),
        ok = save(Stage, "stalled.term", Counters),
        ok = file:write_file(filename:join(Stage, "release_app"), <<>>),
        Expected = gen_server:call(CPU, Read),
        {reply, Expected} = gen_server:wait_response(Request, 10000),
        Inputs = [{sample, <<5:3, (N rem 32):5, Delta:16/signed-little>>}
            || N <- lists:seq(0, 39), Delta <- [-32768, -129, -1, 0, 1, 127, 32767]],
        %% Each round trips record fields that cross a byte boundary, including
        %% the stored bitstring, count and signed accumulator.
        lists:foreach(fun(Input) ->
            Result = gen_server:call(CPU, Input),
            Result = gen_server:call(Hardware, Input, 10000)
        end, Inputs),
        {ok, _} = hls_debug:get_trace(Debug, 10000),
        Before = gen_server:call(Hardware, Read, 10000),
        {error, {remote_error, function_clause}} = gen_server:call(Hardware, {sample, <<0:24>>}, 10000),
        %% hls_gs clears hardware state on callback failure. Check that policy
        %% rather than accidentally committing the failed callback outcome.
        Cleared = {receipt, <<0:24>>, 0, 0},
        Cleared = gen_server:call(Hardware, Read, 10000),
        {ok, #{events := Events, observation_drops := 0, dropped := 0} = Trace} =
            hls_debug:get_trace(Debug, 10000),
        ExpectedTags = [packed_samples:pack_tag(read), packed_samples:pack_tag(receipt),
            packed_samples:pack_tag(sample), packed_samples:pack_tag(error),
            packed_samples:pack_tag(read), packed_samples:pack_tag(receipt)],
        ExpectedTags = [Op || #{op := Op} <- Events],
        [application_rx, application_tx, application_rx, application_tx, application_rx, application_tx] =
            [Kind || #{kind := Kind} <- Events],
        [#{tx_id := BeforeTx}, #{tx_id := BeforeTx}, #{tx_id := BadTx},
            #{tx_id := BadTx}, #{tx_id := AfterTx}, #{tx_id := AfterTx}] = Events,
        ok = save(Stage, "failed-decode.term", #{before_failure => Before, after_failure => Cleared, trace => Trace}),
        {ok, #{app_rx_frames := 284, app_tx_frames := 284, observation_drops := 0} = Final} =
            hls_debug:get_counters(Debug, 10000),
        ok = save(Stage, "completed.term", Final),
        io:format("PASS: 280 BEAM/RTL packed samples, stalled reply diagnosed with counters, failed decode diagnosed with trace and cleared state~n")
    after
        hls_debug:stop(Debug), hls_gs:stop(Hardware), hls_gs:stop(CPU),
        hls_fabric:stop(App), hls_fabric:stop(Management)
    end,
    file:write_file(filename:join(Stage, "done"), <<>>).

await_stall(Debug, Deadline) ->
    Remaining = max(1, Deadline - erlang:monotonic_time(millisecond)),
    {ok, #{app_tx_stall_cycles := Cycles} = Counters} = hls_debug:get_counters(Debug, Remaining),
    case Cycles > 0 of
        true -> Counters;
        false ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            await_stall(Debug, Deadline)
    end.

save(Stage, Name, Value) ->
    file:write_file(filename:join(Stage, Name), io_lib:format("~p.~n", [Value])).
