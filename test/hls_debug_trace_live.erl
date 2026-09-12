-module(hls_debug_trace_live).
-export([run/1]).

run(Stage) ->
    {ok, Fabric} = hls_fabric:start_link(filename:join(Stage, "debug_tx"), filename:join(Stage, "debug_rx")),
    try run(Fabric, Stage) after hls_fabric:stop(Fabric) end.

run(Fabric, Stage) ->
    {ok, Client} = hls_debug:start_link(undefined, {fabric, Fabric, 1}),
    Boundary = {boundary, Client, injected_streams},
    try
        phase(Stage, 0),
        T0 = trace(Boundary, Stage, 0),
        [{application_rx, 16#10, false}, {application_tx, 16#10, false}] = events(T0),
        0 = maps:get(observation_drops, T0),

        phase(Stage, 1),
        #{framing := #{rx := unsynchronized, tx := unsynchronized}, observation_drops := 1} = counters(Boundary),
        [] = events(trace(Boundary, Stage, 1)),
        phase(Stage, 2),
        #{framing := #{rx := unsynchronized}} = counters(Boundary),
        [] = events(trace(Boundary, Stage, 2)),

        phase(Stage, 3),
        #{framing := #{rx := boundary, tx := unsynchronized}} = counters(Boundary),
        [{application_rx, 16#12, true}] = events(trace(Boundary, Stage, 3)),

        phase(Stage, 4),
        #{framing := #{rx := boundary, tx := boundary}} = counters(Boundary),
        [{application_rx, 16#14, true}, {application_tx, 16#14, true}] = events(trace(Boundary, Stage, 4)),

        phase(Stage, 5),
        [{application_rx, 16#15, false}, {application_rx, 16#17, true}] = events(trace(Boundary, Stage, 5)),

        phase(Stage, 6),
        Full = #{count := 64, dropped := 1, observation_drops := 4,
                 framing := #{rx_gap_pending := true}} = trace(Boundary, Stage, 6),
        ExpectedFull = [{application_rx, Id, false} || Id <- lists:seq(0, 63)],
        ExpectedFull = events(Full),
        phase(Stage, 7),
        [{application_rx, 16#82, true}] = events(trace(Boundary, Stage, 7)),
        ok
    after hls_debug:stop(Client) end,
    % Reset is explicit and quiescent. Replace the debug client; the idle
    % byte transport remains open with no outstanding physical transfers.
    phase(Stage, 8),
    {ok, NextClient} = hls_debug:start_link(undefined, {fabric, Fabric, 1}),
    try
        Fresh = trace({boundary, NextClient, injected_streams}, Stage, 8),
        0 = maps:get(observation_drops, Fresh),
        [{application_rx, 16#90, false}, {application_tx, 16#90, false}] = events(Fresh)
    after hls_debug:stop(NextClient) end,
    file:write_file(filename:join(Stage, "phase_9"), <<>>),
    io:format("PASS: routed headers, loss detection, per-stream resynchronization, overflow and reset diagnosed through hls_debug~n"),
    ok.

phase(Stage, N) ->
    ok = file:write_file(filename:join(Stage, "phase_" ++ integer_to_list(N)), <<>>),
    await(filename:join(Stage, "done_" ++ integer_to_list(N)), 10000).

await(_Path, 0) -> error(stimulus_timeout);
await(Path, Tries) ->
    case file:read_file(Path) of
        {ok, _} -> ok;
        {error, enoent} -> timer:sleep(1), await(Path, Tries-1)
    end.

counters(Boundary) ->
    {ok, #{version := 5} = Counters} = hls_debug:get_counters(Boundary, 10000),
    Counters.

trace(Boundary, Stage, N) ->
    {ok, #{version := 2, record_words := 3} = Trace} = hls_debug:get_trace(Boundary, 10000),
    ok = file:write_file(filename:join(Stage, "trace_" ++ integer_to_list(N) ++ ".term"), io_lib:format("~p.~n", [Trace])),
    Trace.

events(#{events := Events}) ->
    [begin
        #{route := {16#1234, 16#5678}, op := 7, kind := Kind,
            tx_id := Id, observation_gap := Gap} = Event,
        {Kind, Id, Gap}
    end || Event <- Events].
