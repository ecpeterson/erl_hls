#!/usr/bin/env escript
%%! +S 1:1 +A 2 +SDio 4 -pa /opt/erl-hls/lib/hls_runtime/ebin -pa /opt/erl-hls/lib/hls_board_examples/ebin -pa /opt/erl-hls/lib/hls_fabric/ebin
%% Observe one complete local status round from the split N=6 application.
-mode(compile).

-define(DEFAULT_TIMEOUT, 30000).
-define(MEMORY_TIMEOUT, 120000).
-define(MEMORY_PORT, 4056).
-define(MEMORY_REQUEST, 16#52455031).

-doc "Run or demonstrate one role, inspect passive debug, or check installed inputs.".
-spec main([string()]) -> ok.
main(["--run", Role]) -> run(role(Role), ?DEFAULT_TIMEOUT, quiet);
main(["--run", Role, Timeout]) -> run(role(Role), positive(Timeout), quiet);
main(["--demo", Role]) -> run(role(Role), ?DEFAULT_TIMEOUT, verbose);
main(["--demo", Role, Timeout]) -> run(role(Role), positive(Timeout), verbose);
main(["--memory", Role]) -> memory(role(Role), ?MEMORY_TIMEOUT);
main(["--memory", Role, Timeout]) -> memory(role(Role), positive(Timeout));
main(["--debug-smoke"]) -> debug_smoke();
main(["--private-link-smoke"]) -> private_link_smoke();
main(["--stage-smoke"]) -> stage_smoke();
main(["--packet-smoke"]) -> packet_smoke();
main(["--check-install"]) -> check_install();
main(["--self-test"]) -> self_test(), io:format("PASS: repetition-link runner self-test~n");
main(_) -> usage().

%% Attach the local gateway and require all three local phi cells in one status step.
-spec run({a | b, 0 | 1, [0..5], {0..5, 0, 0..5, 0}}, pos_integer(),
          quiet | verbose) -> ok.
run({Role, Device, Coordinates, Rectangle}, Timeout, Output) ->
    ok = hls_dma_device:await("/dev/hls-dma0", "40000000.dma-mailbox", 5000),
    {ok, _} = application:ensure_all_started(crypto),
    Deployment = deployment(Role),
    {ok, Broker} = hls_fabric:start_link("/dev/hls-dma0", "/dev/hls-dma0"),
    #{counts := Baseline} = hls_fabric:info(Broker),
    {Round, Final} = try
        {ok, Stream} = hls_partition_stream:start_link(
            Deployment, #{Device => Broker}, #{queue_limit => 64, write_timeout => 10000}),
        Result = try
            {ok, 1} = hls_partition_stream:submit(Stream, cutoff(Rectangle)),
            Deadline = erlang:monotonic_time(millisecond) + Timeout,
            case await_round(Stream, Device, Coordinates, Deadline, #{}, 0, 0,
                             Role, Output) of
                {complete, CompletedStep, EventCount, CorrectionCount} ->
                    {complete, CompletedStep, EventCount, CorrectionCount};
                {timeout, Partial} ->
                    {timeout, Partial, hls_partition_stream:info(Stream)}
            end
        after
            stop_stream(Stream)
        end,
        #{counts := Counts} = hls_dma_device:await_broker(Broker, 5000),
        {Result, Counts}
    after
        ok = hls_dma_device:close_broker(Broker, 5000)
    end,
    Status = hls_dma_device:status("40000000.dma-mailbox", application, 1000),
    true = hls_dma_device:healthy(Status),
    case Round of
        {complete, Step, Events, Corrections} ->
            io:format("role=~p device=~p step=~p events=~p corrections=~p "
                      "transport=~p~n",
                      [Role, Device, Step, Events, Corrections,
                       hls_link_diagnostics:counter_delta(Baseline, Final)]),
            io:put_chars(hls_dma_device:status_line(application, Status)),
            case Output of
                quiet ->
                    io:format("PASS: role ~p observed a complete three-cell status round "
                              "through the attached 3+3 PL application "
                              "(transport smoke, not decoder qualification)~n", [Role]);
                verbose ->
                    io:format("PASS: role ~p displayed every decoded correction and status "
                              "through its first complete local round "
                              "(application demo, not logical-memory qualification)~n", [Role])
            end;
        {timeout, Progress, StreamInfo} ->
            io:format("TIMEOUT role=~p device=~p progress=~p stream=~p "
                      "transport=~p~n",
                      [Role, Device, Progress, StreamInfo,
                       hls_link_diagnostics:counter_delta(Baseline, Final)]),
            io:put_chars(hls_dma_device:status_line(application, Status)),
            error({round_timeout, Role, Progress})
    end.

%% Close one physical repetition-memory activation across the two host CPUs.
%% Each board owns its local application gateway; the small TCP protocol
%% forwards only correction commands and the closeout fence over PS Ethernet.
-spec memory({a | b, 0 | 1, [0..5], {0..5, 0, 0..5, 0}}, pos_integer()) -> ok.
memory({Role, Device, Coordinates, Rectangle}, Timeout) ->
    ok = hls_dma_device:await("/dev/hls-dma0", "40000000.dma-mailbox", 5000),
    {ok, _} = application:ensure_all_started(crypto),
    {ok, Broker} = hls_fabric:start_link("/dev/hls-dma0", "/dev/hls-dma0"),
    #{counts := Baseline} = hls_fabric:info(Broker),
    {Result, Final} = try
        {ok, Stream} = hls_partition_stream:start_link(
            deployment(Role), #{Device => Broker},
            #{queue_limit => 128, write_timeout => 10000}),
        RunResult = try
            Deadline = erlang:monotonic_time(millisecond) + Timeout,
            {ok, Socket} = memory_peer(Role, Deadline),
            try
                State0 = memory_handshake(Role, Device, Coordinates, Rectangle,
                    Stream, Socket, Deadline),
                memory_loop(State0)
            after
                gen_tcp:close(Socket)
            end
        after
            stop_stream(Stream)
        end,
        #{counts := Counts} = hls_dma_device:await_broker(Broker, 5000),
        {RunResult, Counts}
    after
        ok = hls_dma_device:close_broker(Broker, 5000)
    end,
    Status = hls_dma_device:status("40000000.dma-mailbox", application, 1000),
    true = hls_dma_device:healthy(Status),
    io:format("memory result=~p transport=~p~n",
              [Result, hls_link_diagnostics:counter_delta(Baseline, Final)]),
    io:put_chars(hls_dma_device:status_line(application, Status)),
    io:format("PASS: role ~p completed closed-loop repetition memory; "
              "correction updates were ordered before measurement behind the "
              "global quiet fence, and the logical-X parity was measured "
              "(physical witness, not a "
              "decoder threshold qualification)~n", [Role]).

%% Role B listens first; role A retries its fixed PS-Ethernet connection.
-spec memory_peer(a | b, integer()) -> {ok, port()}.
memory_peer(b, Deadline) ->
    {ok, Listen} = gen_tcp:listen(?MEMORY_PORT,
        [binary, {packet, 4}, {active, false}, {reuseaddr, true}, {nodelay, true}]),
    Timeout = max(1, Deadline - erlang:monotonic_time(millisecond)),
    Result = gen_tcp:accept(Listen, Timeout),
    ok = gen_tcp:close(Listen),
    Result;
memory_peer(a, Deadline) ->
    case gen_tcp:connect({192, 168, 77, 32}, ?MEMORY_PORT,
            [binary, {packet, 4}, {active, false}, {nodelay, true}], 1000) of
        {ok, Socket} -> {ok, Socket};
        {error, _Reason} ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> timer:sleep(100), memory_peer(a, Deadline);
                false -> error(memory_peer_timeout)
            end
    end.

%% Attach both gateways before either role releases the pure reducer's cutoff.
-spec memory_handshake(a | b, 0 | 1, [0..5], {0..5, 0, 0..5, 0},
                       pid(), port(), integer()) -> map().
memory_handshake(Role, Device, Coordinates, Rectangle, Stream, Socket, Deadline) ->
    {Experiment, Cutoff} = phi_repetition_memory:new(#{
        role => Role,
        size => 6,
        coordinates => Coordinates,
        rectangle => Rectangle,
        first_quiet_step => 16,
        request_id => ?MEMORY_REQUEST
    }),
    ok = memory_send(Socket, {hello, Role}),
    {hello, PeerRole} = memory_receive(Socket, Deadline),
    true = PeerRole =:= phi_repetition_memory:peer_role(Role),
    case Role of
        a ->
            ok = memory_send(Socket, start),
            {ok, 1} = hls_partition_stream:submit(Stream, Cutoff),
            start_ack = memory_receive(Socket, Deadline);
        b ->
            start = memory_receive(Socket, Deadline),
            {ok, 1} = hls_partition_stream:submit(Stream, Cutoff),
            ok = memory_send(Socket, start_ack)
    end,
    #{device => Device, stream => Stream, socket => Socket,
      deadline => Deadline, experiment => Experiment}.

%% Alternate bounded PL reads with complete draining of the PS peer socket.
-spec memory_loop(map()) -> map().
memory_loop(State0) ->
    State1 = memory_drain_peer(State0),
    case maps:find(result, State1) of
        {ok, Result} -> Result;
        error ->
            Deadline = maps:get(deadline, State1),
            case erlang:monotonic_time(millisecond) < Deadline of
                false -> error({memory_timeout,
                                phi_repetition_memory:progress(
                                    maps:get(experiment, State1))});
                true ->
                    Stream = maps:get(stream, State1),
                    ExpectedDevice = maps:get(device, State1),
                    case hls_partition_stream:next(Stream, 20) of
                        timeout -> memory_loop(State1);
                        {ok, ExpectedDevice, StreamName, Event} ->
                            memory_loop(memory_event(StreamName, Event, State1));
                        Other -> error({memory_stream, Other})
                    end
            end
    end.

%% Consume every currently queued peer packet before returning to PL output.
-spec memory_drain_peer(map()) -> map().
memory_drain_peer(State = #{socket := Socket}) ->
    case gen_tcp:recv(Socket, 0, 0) of
        {ok, Packet} ->
            Experiment = maps:get(experiment, State),
            Transition = phi_repetition_memory:peer(
                phi_repetition_memory:decode_peer(Packet), Experiment),
            memory_drain_peer(memory_transition(Transition, State));
        {error, timeout} -> State;
        {error, closed} ->
            case maps:is_key(result, State) of
                true -> State;
                false -> error({memory_peer_closed,
                                phi_repetition_memory:progress(
                                    maps:get(experiment, State))})
            end;
        {error, Reason} -> error({memory_peer, Reason})
    end.

%% Feed one local event into the transport-independent closeout reducer.
-spec memory_event(atom(), tuple(), map()) -> map().
memory_event(StreamName, Event, State = #{experiment := Experiment}) ->
    memory_transition(phi_repetition_memory:event(StreamName, Event, Experiment), State).

%% Execute one pure transition while preserving its declared effect order.
-spec memory_transition(phi_repetition_memory:transition(), map()) -> map().
memory_transition({ok, Experiment, Effects}, State) ->
    memory_effects(Effects, State#{experiment := Experiment});
memory_transition({done, Result, Experiment, Effects}, State) ->
    Updated = memory_effects(Effects, State#{experiment := Experiment}),
    Updated#{result => Result};
memory_transition({error, Reason, Experiment}, _State) ->
    error({memory_protocol, Reason, phi_repetition_memory:progress(Experiment)}).

%% Submit local work and send peer packets in the reducer's exact order.
-spec memory_effects([phi_repetition_memory:effect()], map()) -> map().
memory_effects([], State) -> State;
memory_effects([{command, Command} | Rest], State = #{stream := Stream}) ->
    {ok, 1} = hls_partition_stream:submit(Stream, Command),
    memory_effects(Rest, State);
memory_effects([{peer, Message} | Rest], State = #{socket := Socket}) ->
    ok = memory_send(Socket, Message),
    memory_effects(Rest, State);
memory_effects([{observation, Observation} | Rest], State) ->
    io:format("~p~n", [Observation]),
    memory_effects(Rest, State).

%% Send one strictly encoded coordinator packet.
-spec memory_send(port(), phi_repetition_memory:peer_message()) -> ok.
memory_send(Socket, Message) ->
    gen_tcp:send(Socket, phi_repetition_memory:encode_peer(Message)).

%% Receive one coordinator packet before the experiment's whole-run deadline.
-spec memory_receive(port(), integer()) -> phi_repetition_memory:peer_message().
memory_receive(Socket, Deadline) ->
    Timeout = max(1, Deadline - erlang:monotonic_time(millisecond)),
    case gen_tcp:recv(Socket, 0, Timeout) of
        {ok, Packet} -> phi_repetition_memory:decode_peer(Packet);
        {error, Reason} -> error({memory_receive, Reason})
    end.

%% Drain decoded events until one step contains every local coordinate.
-spec await_round(pid(), 0 | 1, [0..5], integer(), map(), non_neg_integer(),
                  non_neg_integer(), a | b, quiet | verbose) ->
    {complete, non_neg_integer(), pos_integer(), non_neg_integer()} |
    {timeout, map()}.
await_round(Stream, Device, Coordinates, Deadline, Rounds, Events, Corrections,
            Role, Output) ->
    case erlang:monotonic_time(millisecond) < Deadline of
        false ->
            {timeout, #{rounds => Rounds, events => Events, corrections => Corrections}};
        true ->
            case hls_partition_stream:next(Stream, 1000) of
                timeout ->
                    await_round(Stream, Device, Coordinates, Deadline, Rounds,
                                Events, Corrections, Role, Output);
                {ok, Device, decoder_events, Status = {phi_status, Step, X, 0, _Flags}}
                        when is_integer(Step), is_integer(X) ->
                    ok = print_demo_event(Output, Role, Status),
                    Seen = maps:get(Step, Rounds, #{}),
                    Updated = trim_rounds(Rounds#{Step => Seen#{X => true}}, Step),
                    Complete = lists:all(fun(Coordinate) ->
                        maps:is_key(Coordinate, maps:get(Step, Updated))
                    end, Coordinates),
                    case Complete of
                        true -> {complete, Step, Events + 1, Corrections};
                        false -> await_round(Stream, Device, Coordinates, Deadline, Updated,
                                             Events + 1, Corrections, Role, Output)
                    end;
                {ok, Device, decoder_events, Correction = {phi_correction, _, _, _, _}} ->
                    ok = print_demo_event(Output, Role, Correction),
                    await_round(Stream, Device, Coordinates, Deadline, Rounds,
                                Events + 1, Corrections + 1, Role, Output);
                {ok, Device, _Stream, _Event} ->
                    await_round(Stream, Device, Coordinates, Deadline, Rounds,
                                Events + 1, Corrections, Role, Output);
                Other ->
                    error({unexpected_stream_result, Other})
            end
    end.

%% Print one decoded application event only in demonstration mode.
-spec print_demo_event(quiet | verbose, a | b,
                       {phi_correction | phi_status, integer(), integer(), integer(), integer()}) -> ok.
print_demo_event(quiet, _Role, _Event) ->
    ok;
print_demo_event(verbose, Role, Event) ->
    io:format("~p~n", [demo_event(Role, Event)]).

%% Name correction targets and status bits without changing the wire record.
-spec demo_event(a | b,
                 {phi_correction | phi_status, integer(), integer(), integer(), integer()}) -> map().
demo_event(Role, {phi_correction, Step, X, 0, Direction}) ->
    {DirectionName, DataX} = correction_target(X, Direction),
    #{role => Role, event => correction, step => Step, check => {X, 0},
      direction => DirectionName, data => {DataX, 0}, update => z};
demo_event(Role, {phi_status, Step, X, 0, Flags}) ->
    #{role => Role, event => status, step => Step, cell => {X, 0},
      present => Flags band 1 =/= 0, quiet => Flags band 2 =/= 0,
      raw_flags => Flags}.

%% Translate the repetition decoder's two valid moves to their data qubits.
-spec correction_target(0..5, 2 | 4) -> {east | west, 0..5}.
correction_target(X, 2) when X >= 0, X < 6 -> {east, (X + 1) rem 6};
correction_target(X, 4) when X >= 0, X < 6 -> {west, X};
correction_target(X, Direction) -> error({correction_direction, X, Direction}).

%% Retain only nearby steps so an unhealthy stream cannot grow host memory without bound.
-spec trim_rounds(map(), non_neg_integer()) -> map().
trim_rounds(Rounds, Latest) ->
    maps:filter(fun(Step, _Seen) -> Step + 8 >= Latest end, Rounds).

%% Query the independently routed passive monitor without opening the application lane.
-spec debug_smoke() -> ok.
debug_smoke() ->
    ok = hls_dma_device:await("/dev/hls-dma1", "40004000.dma-mailbox", 5000),
    {ok, Broker} = hls_fabric:start_link("/dev/hls-dma1", "/dev/hls-dma1"),
    {Counters, Trace, Status} = try
        {ok, Debug} = hls_debug:start_link(undefined, {fabric, Broker, 1}),
        try
            {ok, C = #{version := _Version, observation_drops := 0}} =
                hls_debug:get_counters(Debug),
            {ok, T = #{count := Count, events := Events}} = hls_debug:get_trace(Debug),
            Count = length(Events),
            true = Count =< 64,
            S = hls_dma_device:status("40004000.dma-mailbox", idle, 1000),
            true = hls_dma_device:idle(S),
            {C, T, S}
        after
            ok = hls_debug:stop(Debug)
        end
    after
        ok = hls_dma_device:close_broker(Broker, 5000)
    end,
    true = is_map(Counters) andalso is_map(Trace),
    io:format("debug counters=~p~ndebug trace=~p~n",
              [Counters, maps:remove(raw, Trace)]),
    io:put_chars(hls_dma_device:status_line(debug, Status)),
    io:format("PASS: routed passive debug counter and trace queries~n").

%% Sample the diagnostic build's graph/link taps without interpreting serial-credit words as host frames.
-spec private_link_smoke() -> ok.
private_link_smoke() ->
    ok = hls_dma_device:await("/dev/hls-dma1", "40004000.dma-mailbox", 5000),
    {ok, Broker} = hls_fabric:start_link("/dev/hls-dma1", "/dev/hls-dma1"),
    {Before, Final, Status} = try
        {ok, Debug} = hls_debug:start_link(undefined, {fabric, Broker, 1}),
        try
            {ok, First = #{version := 5}} = hls_debug:get_counters(Debug),
            timer:sleep(1000),
            {ok, Last = #{version := 5}} = hls_debug:get_counters(Debug),
            S = hls_dma_device:status("40004000.dma-mailbox", idle, 1000),
            true = hls_dma_device:idle(S),
            {First, Last, S}
        after
            ok = hls_debug:stop(Debug)
        end
    after
        ok = hls_dma_device:close_broker(Broker, 5000)
    end,
    Delta = hls_link_diagnostics:private_delta(Before, Final),
    io:format("private-link totals=~p~nprivate-link one_second_delta=~p~n"
              "boundary=~s~n",
              [hls_link_diagnostics:private_counters(Final), Delta,
               hls_link_diagnostics:private_boundary(Final, Delta)]),
    io:put_chars(hls_dma_device:status_line(debug, Status)),
    io:format("PASS: private-link directional counters sampled (diagnostic, not progress qualification)~n").

%% Sample the independent scheduler-memory and graph-output diagnostic endpoint.
-spec stage_smoke() -> ok.
stage_smoke() ->
    ok = hls_dma_device:await("/dev/hls-dma1", "40004000.dma-mailbox", 5000),
    {ok, Broker} = hls_fabric:start_link("/dev/hls-dma1", "/dev/hls-dma1"),
    {Before, Final, Trace, Status} = try
        {ok, Debug} = hls_debug:start_link(undefined, {fabric, Broker, 2}),
        try
            {ok, First = #{version := 5}} = hls_debug:get_counters(Debug),
            timer:sleep(1000),
            {ok, Last = #{version := 5}} = hls_debug:get_counters(Debug),
            {ok, T = #{events := _}} = hls_debug:get_trace(Debug),
            S = hls_dma_device:status("40004000.dma-mailbox", idle, 1000),
            true = hls_dma_device:idle(S),
            {First, Last, T, S}
        after
            ok = hls_debug:stop(Debug)
        end
    after
        ok = hls_dma_device:close_broker(Broker, 5000)
    end,
    Delta = hls_link_diagnostics:stage_delta(Before, Final),
    Events = maps:get(events, Trace),
    Flags = hls_link_diagnostics:stage_trace_flags(Events),
    RequestTrace =
        [#{cycle => maps:get(cycle, Event),
           flags => hls_link_diagnostics:stage_flags(maps:get(tx_id, Event) band 31)}
         || Event = #{kind := application_tx} <- Events],
    io:format("stage totals=~p~nstage one_second_delta=~p~n"
              "stage decoded_trace=~p~nstage request_trace=~p~n"
              "stage observed_request_flags=~p~n"
              "boundary=~s~n",
              [hls_link_diagnostics:stage_counters(Final), Delta,
               maps:remove(raw, Trace), RequestTrace,
               hls_link_diagnostics:stage_flags(Flags),
               hls_link_diagnostics:stage_boundary(Final)]),
    io:put_chars(hls_dma_device:status_line(stage, Status)),
    io:format("PASS: host-independent scheduler and graph stages sampled "
              "(diagnostic, not progress qualification)~n").

%% Sample the graph, packet adapter, MAC and receive-delivery boundaries.
-spec packet_smoke() -> ok.
packet_smoke() ->
    ok = hls_dma_device:await("/dev/hls-dma1", "40004000.dma-mailbox", 5000),
    {ok, Broker} = hls_fabric:start_link("/dev/hls-dma1", "/dev/hls-dma1"),
    {Before, Final, Trace, Status} = try
        {ok, Debug} = hls_debug:start_link(undefined, {fabric, Broker, 2}),
        try
            {ok, First = #{version := 5}} = hls_debug:get_counters(Debug),
            timer:sleep(1000),
            {ok, Last = #{version := 5}} = hls_debug:get_counters(Debug),
            {ok, T = #{events := _}} = hls_debug:get_trace(Debug),
            S = hls_dma_device:status("40004000.dma-mailbox", idle, 1000),
            true = hls_dma_device:idle(S),
            {First, Last, T, S}
        after
            ok = hls_debug:stop(Debug)
        end
    after
        ok = hls_dma_device:close_broker(Broker, 5000)
    end,
    Delta = hls_link_diagnostics:packet_delta(Before, Final),
    Events = maps:get(events, Trace),
    {AdapterRaw, MacRaw} = hls_link_diagnostics:packet_trace_flags(Events),
    Adapter = hls_link_diagnostics:packet_adapter_flags(AdapterRaw),
    Mac = hls_link_diagnostics:packet_mac_flags(MacRaw),
    EventTrace =
        [hls_link_diagnostics:packet_trace_event(Event)
         || Event = #{kind := application_tx, op := Op} <- Events,
            Op == 16#d1 orelse Op == 16#d2],
    io:format("packet totals=~p~npacket one_second_delta=~p~n"
              "packet decoded_trace=~p~npacket event_trace=~p~n"
              "packet adapter_flags=~p~npacket mac_flags=~p~n"
              "boundary=~s~n",
              [hls_link_diagnostics:packet_counters(Final), Delta,
               maps:remove(raw, Trace), EventTrace, Adapter, Mac,
               hls_link_diagnostics:packet_boundary(Final, Adapter, Mac)]),
    io:put_chars(hls_dma_device:status_line(packet, Status)),
    io:format("PASS: private packet boundaries sampled "
              "(diagnostic, not CDC/MAC qualification)~n").

%% Check both role deployments and their local rectangle command without touching PL.
-spec check_install() -> ok.
check_install() ->
    [ok = check_deployment(Role, Device, Rectangle)
     || {Role, Device, Rectangle} <- [{a, 0, {0, 0, 2, 0}}, {b, 1, {3, 0, 5, 0}}]],
    {ok, Fixture} = file:read_file("/opt/erl-hls/share/repetition-link/fixture.json"),
    true = binary:match(Fixture, <<"\"split\":[3,3]">>) =/= nomatch,
    io:format("PASS: installed 3+3 repetition deployments and codecs~n").

%% Require one role-local encoded command with the expected numeric device identity.
-spec check_deployment(a | b, 0 | 1, {0..5, 0, 0..5, 0}) -> ok.
check_deployment(Role, Device, Rectangle) ->
    Deployment = deployment(Role),
    #{devices := Devices} = Deployment,
    [Device] = maps:keys(Devices),
    [{Device, _Route, _Header, Payload}] = hls_partition_wire:command(
        Deployment, cutoff(Rectangle)),
    true = byte_size(Payload) > 0,
    ok.

%% Decode one manifest-hashed deployment installed by the image builder.
-spec deployment(a | b) -> map().
deployment(Role) ->
    Path = "/opt/erl-hls/share/repetition-link/deployment-" ++ atom_to_list(Role) ++ ".etf",
    {ok, Bytes} = file:read_file(Path),
    binary_to_term(Bytes).

%% Create the first valid host command, which releases the generated gateway's outputs.
-spec cutoff({0..5, 0, 0..5, 0}) -> hls_partition_wire:command().
cutoff(Rectangle) ->
    {control_router, noise, Rectangle, {noise_cutoff, 16}}.

%% Map the image role to its generated device, local coordinates and control rectangle.
-spec role(string()) -> {a | b, 0 | 1, [0..5], {0..5, 0, 0..5, 0}}.
role("a") -> {a, 0, [0, 1, 2], {0, 0, 2, 0}};
role("b") -> {b, 1, [3, 4, 5], {3, 0, 5, 0}};
role(Text) -> error({bad_role, Text}).

%% Accept a bounded decimal timeout in milliseconds.
-spec positive(string()) -> pos_integer().
positive(Text) ->
    case string:to_integer(Text) of
        {Value, []} when Value > 0, Value =< 600000 -> Value;
        _ -> error({bad_timeout, Text})
    end.

%% Release logical routes during normal completion and diagnostic failure.
-spec stop_stream(pid()) -> ok.
stop_stream(Stream) ->
    _ = catch hls_partition_stream:stop(Stream),
    ok.

%% Exercise helpers without PL devices, including acceptance of a character node.
-spec self_test() -> ok.
self_test() ->
    {a, 0, [0, 1, 2], A} = role("a"),
    {b, 1, [3, 4, 5], B} = role("b"),
    {control_router, noise, A, {noise_cutoff, 16}} = cutoff(A),
    {control_router, noise, B, {noise_cutoff, 16}} = cutoff(B),
    30000 = positive("30000"),
    #{cycles := 3} = hls_link_diagnostics:private_delta(
        #{cycles => 16#fffffffe, observation_drops => 0,
          app_rx_beats => 0, app_rx_frames => 0, app_rx_stall_cycles => 0,
          app_tx_beats => 0, app_tx_frames => 0, app_tx_stall_cycles => 0},
        #{cycles => 1, observation_drops => 0,
          app_rx_beats => 0, app_rx_frames => 0, app_rx_stall_cycles => 0,
          app_tx_beats => 0, app_tx_frames => 0, app_tx_stall_cycles => 0}),
    #{9 := #{0 := true}} = trim_rounds(#{0 => #{7 => true}, 9 => #{0 => true}}, 9),
    31 = hls_link_diagnostics:stage_trace_flags(
        [#{kind => application_tx, tx_id => 31}]),
    #{raw := 31, state_read := true, mailbox_snapshot := true} =
        hls_link_diagnostics:stage_flags(31),
    {255, 63} = hls_link_diagnostics:packet_trace_flags([
        #{kind => application_tx, op => 16#d1, tx_id => 255},
        #{kind => application_tx, op => 16#d2, tx_id => 63}]),
    #{tx_frame_accepted := true, rx_link := true} =
        hls_link_diagnostics:packet_adapter_flags(255),
    #{tx_accepted := true, crc_error := true} =
        hls_link_diagnostics:packet_mac_flags(63),
    #{role := a, event := correction, direction := east, data := {0, 0}, update := z} =
        demo_event(a, {phi_correction, 16, 5, 0, 2}),
    #{role := b, event := correction, direction := west, data := {3, 0}, update := z} =
        demo_event(b, {phi_correction, 17, 3, 0, 4}),
    #{event := status, present := true, quiet := true, raw_flags := 3} =
        demo_event(a, {phi_status, 18, 0, 0, 3}),
    {correction, 7, 16, 2, 2, 3, true} = phi_repetition_memory:decode_peer(
        phi_repetition_memory:encode_peer({correction, 7, 16, 2, 2, 3, true})),
    {query, ?MEMORY_REQUEST, 18} = phi_repetition_memory:decode_peer(
        phi_repetition_memory:encode_peer({query, ?MEMORY_REQUEST, 18})),
    "a private frame crossed every instrumented local packet boundary" =
        hls_link_diagnostics:packet_boundary(
            #{app_rx_frames => 1},
            hls_link_diagnostics:packet_adapter_flags(7),
            hls_link_diagnostics:packet_mac_flags(5)),
    true = hls_dma_device:healthy(
        <<"tx_busy=0 rx_full=1 rx_active=0 fault=0 failed=0 rx_bytes=20 events=2 mask=5\n">>),
    false = hls_dma_device:healthy(
        <<"tx_busy=0 rx_full=1 rx_active=0 fault=1 failed=0 rx_bytes=20 events=2 mask=5\n">>),
    ok = hls_dma_device:await("/dev/null", "unused", 0),
    ok.

%% Print accepted target-side invocations and fail the process.
-spec usage() -> no_return().
usage() ->
    io:put_chars(standard_error,
                 ["usage: check_repetition_link --run a|b [timeout_ms] | ",
                  "--demo a|b [timeout_ms] | ",
                  "--memory a|b [timeout_ms] | ",
                  "--debug-smoke | --private-link-smoke | --stage-smoke | ",
                  "--packet-smoke | --check-install | --self-test\n"]),
    halt(2).
