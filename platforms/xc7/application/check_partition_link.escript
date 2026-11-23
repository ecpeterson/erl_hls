#!/usr/bin/env escript
%%! +S 1:1 +A 2 +SDio 4 -pa /opt/erl-hls/lib/hls_runtime/ebin -pa /opt/erl-hls/lib/hls_board_examples/ebin -pa /opt/erl-hls/lib/hls_fabric/ebin
%% Exercise one board's host boundary while the actor exchange crosses the DAC.
-mode(compile).

-define(DEFAULT_ROUNDS, 16).
-define(MAX_ROUNDS, 1000000).
-define(DEFAULT_PASSES, 1).
-define(MAX_PASSES, 1000).
-define(PROGRESS_INTERVAL, 256).
-define(FIRST_NONCE, 16#71050000).

-doc "Run the board-A leader or board-B follower acceptance role.".
-spec main([string()]) -> ok.
main(["--lead" | Arguments]) -> requested(a, Arguments);
main(["--follow" | Arguments]) -> requested(b, Arguments);
main(["--debug-smoke"]) -> debug_smoke();
main(["--check-install"]) -> check_install();
main(["--self-test"]) -> self_test(), io:format("PASS: partition-link runner self-test~n");
main(_) -> usage().

%% Parse the optional bounded soak length before opening either DMA endpoint.
-spec requested(a | b, [string()]) -> ok.
requested(Role, Arguments) ->
    case parse_run(Arguments) of
        {ok, Rounds, Passes} -> run(Role, Rounds, Passes);
        error -> usage()
    end.

%% Attach once because the hardware gateway rejects every later attachment until reset.
-spec run(a | b, pos_integer(), pos_integer()) -> ok.
run(Role, Rounds, Passes) ->
    ok = hls_dma_device:await("/dev/hls-dma0", "40000000.dma-mailbox", 5000),
    {ok, _} = application:ensure_all_started(crypto),
    Deployment = deployment(Role),
    {ok, Broker} = hls_fabric:start_link("/dev/hls-dma0", "/dev/hls-dma0"),
    #{counts := Baseline} = hls_fabric:info(Broker),
    Elapsed = try
        {ok, Stream} = hls_partition_stream:start_link(
            Deployment, #{Role => Broker}, #{queue_limit => 8, write_timeout => 10000}),
        try
            Started = erlang:monotonic_time(millisecond),
            ok = run_passes(Role, Stream, Broker, Baseline, Rounds, 1, Passes),
            erlang:monotonic_time(millisecond) - Started
        after
            stop_stream(Stream)
        end
    after
        ok = hls_dma_device:close_broker(Broker, 5000)
    end,
    io:format("PASS: role ~p completed ~p attached pass(es) of ~p actor exchanges "
              "over the PL Ethernet link in ~p ms~n",
              [Role, Passes, Rounds, Elapsed]).

%% Validate each pass before the reverse-direction rendezvous admits the next one.
-spec run_passes(a | b, pid(), pid(), map(), pos_integer(), pos_integer(), pos_integer()) -> ok.
run_passes(Role, Stream, Broker, Baseline, Rounds, Pass, Passes) ->
    FirstNonce = ?FIRST_NONCE + (Pass - 1) * (Rounds + 1),
    Started = erlang:monotonic_time(millisecond),
    soak(Role, Stream, Pass, Passes, FirstNonce, Rounds, Started),
    Elapsed = erlang:monotonic_time(millisecond) - Started,
    Info = hls_partition_stream:info(Stream),
    #{counts := Final} = hls_dma_device:await_broker(Broker, 1000),
    Delta = counter_delta(Baseline, Final),
    Status = hls_dma_device:status("40000000.dma-mailbox", idle, 1000),
    ok = validate_final(Role, Rounds, Pass, Info, Delta, Status),
    io:format("transport role=~p pass=~p/~p cumulative=~p~n", [Role, Pass, Passes, Delta]),
    io:put_chars(hls_dma_device:status_line(application, Status)),
    io:format("PASS: role ~p pass ~p/~p completed ~p actor exchanges in ~p ms~n",
              [Role, Pass, Passes, Rounds, Elapsed]),
    case Pass =:= Passes of
        true -> ok;
        false ->
            ok = rendezvous(Role, Stream, FirstNonce + Rounds),
            io:format("rendezvous role=~p after_pass=~p/~p~n", [Role, Pass, Passes]),
            run_passes(Role, Stream, Broker, Baseline, Rounds, Pass + 1, Passes)
    end.

%% Query the independently routed passive monitor without attaching the application lane.
-spec debug_smoke() -> ok.
debug_smoke() ->
    ok = hls_dma_device:await("/dev/hls-dma1", "40004000.dma-mailbox", 5000),
    {ok, Broker} = hls_fabric:start_link("/dev/hls-dma1", "/dev/hls-dma1"),
    {Counters, Trace, Status} = try
        {ok, Debug} = hls_debug:start_link(undefined, {fabric, Broker, 1}),
        try
            {ok, C = #{version := Version, observation_drops := 0,
                       app_rx_frames := AppRx, app_tx_frames := AppTx}} =
                hls_debug:get_counters(Debug),
            {ok, T = #{count := Count, dropped := Dropped,
                       observation_drops := 0, events := Events}} =
                hls_debug:get_trace(Debug),
            Count = length(Events),
            true = Count =< 64,
            io:format("debug version=~p app_rx_frames=~p app_tx_frames=~p "
                      "trace_count=~p trace_dropped=~p~n",
                      [Version, AppRx, AppTx, Count, Dropped]),
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
    io:put_chars(hls_dma_device:status_line(debug, Status)),
    io:format("PASS: routed passive debug counter and trace queries~n").

%% Exercise both installed terms, actor codecs and pure soak invariants without physical PL.
-spec check_install() -> ok.
check_install() ->
    ok = self_test(),
    A = deployment(a),
    B = deployment(b),
    [{a, _, _, _}] = hls_partition_wire:command(
        A, {control, nodes, {0, 0, 0, 0}, {launch, ?FIRST_NONCE}}),
    [{b, _, _, _}] = hls_partition_wire:command(
        B, {control, nodes, {1, 0, 1, 0}, {launch, ?FIRST_NONCE}}),
    io:format("PASS: installed partition-link deployments and actor codecs~n").

%% Decode only the build-generated, manifest-hashed local deployment artifact.
-spec deployment(a | b) -> map().
deployment(Role) ->
    Path = "/opt/erl-hls/share/partition-link/deployment-" ++ atom_to_list(Role) ++ ".etf",
    {ok, Bytes} = file:read_file(Path),
    Deployment = binary_to_term(Bytes),
    #{devices := Devices} = Deployment,
    [Role] = maps:keys(Devices),
    Deployment.

%% Run one sequential exchange at a time so every nonce has an exact reply boundary.
-spec soak(a | b, pid(), pos_integer(), pos_integer(), non_neg_integer(), pos_integer(), integer()) -> ok.
soak(Role, Stream, Pass, Passes, FirstNonce, Rounds, Started) ->
    soak(Role, Stream, Pass, Passes, FirstNonce, 1, Rounds, Started).

%% Finish after the requested count without allocating a potentially large nonce list.
-spec soak(a | b, pid(), pos_integer(), pos_integer(), non_neg_integer(), pos_integer(),
           pos_integer(), integer()) -> ok.
soak(_Role, _Stream, _Pass, _Passes, _FirstNonce, Completed, Rounds, _Started)
        when Completed > Rounds -> ok;
soak(Role, Stream, Pass, Passes, FirstNonce, Completed, Rounds, Started) ->
    Nonce = FirstNonce + Completed - 1,
    ok = workload_exchange(Role, Stream, Nonce),
    ok = progress(Role, Pass, Passes, Completed, Rounds, Started),
    soak(Role, Stream, Pass, Passes, FirstNonce, Completed + 1, Rounds, Started).

%% Board A injects each launch; board B accepts only the matching peer request.
-spec workload_exchange(a | b, pid(), non_neg_integer()) -> ok.
workload_exchange(a, Stream, Nonce) -> originate(Stream, a, Nonce);
workload_exchange(b, Stream, Nonce) -> respond(Stream, b, Nonce).

%% Board B originates the fence only after validating; board A cannot pass it early.
-spec rendezvous(a | b, pid(), non_neg_integer()) -> ok.
rendezvous(a, Stream, Nonce) -> respond(Stream, a, Nonce);
rendezvous(b, Stream, Nonce) -> originate(Stream, b, Nonce).

%% Launch one local actor and require both its pre-send and returned-reply reports.
-spec originate(pid(), a | b, non_neg_integer()) -> ok.
originate(Stream, Role, Nonce) ->
    {ok, 1} = hls_partition_stream:submit(
        Stream, launch(Role, Nonce)),
    {ok, Role, reports, {observed, Nonce, 1}} = hls_partition_stream:next(Stream, 10000),
    {ok, Role, reports, {observed, Nonce, 3}} = hls_partition_stream:next(Stream, 10000),
    ok.

%% Consume the peer request's local report; its reply is emitted by the actor itself.
-spec respond(pid(), a | b, non_neg_integer()) -> ok.
respond(Stream, Role, Nonce) ->
    {ok, Role, reports, {observed, Nonce, 2}} = hls_partition_stream:next(Stream, 20000),
    ok.

%% Select the only actor coordinate installed in each role-specific deployment.
-spec launch(a | b, non_neg_integer()) -> hls_partition_wire:command().
launch(a, Nonce) -> {control, nodes, {0, 0, 0, 0}, {launch, Nonce}};
launch(b, Nonce) -> {control, nodes, {1, 0, 1, 0}, {launch, Nonce}}.

%% Emit bounded progress without perturbing every exchange with console I/O.
-spec progress(a | b, pos_integer(), pos_integer(), pos_integer(), pos_integer(), integer()) -> ok.
progress(Role, Pass, Passes, Completed, Rounds, Started) ->
    case Completed =:= Rounds orelse Completed rem ?PROGRESS_INTERVAL =:= 0 of
        true ->
            Elapsed = erlang:monotonic_time(millisecond) - Started,
            io:format("progress role=~p pass=~p/~p completed=~p/~p elapsed_ms=~p~n",
                      [Role, Pass, Passes, Completed, Rounds, Elapsed]);
        false -> ok
    end.

%% Accept bounded decimal round/pass counts whose data and fence nonces fit u32.
-spec parse_run([string()]) -> {ok, pos_integer(), pos_integer()} | error.
parse_run([]) -> {ok, ?DEFAULT_ROUNDS, ?DEFAULT_PASSES};
parse_run([Rounds]) -> parse_run([Rounds, integer_to_list(?DEFAULT_PASSES)]);
parse_run([RoundsText, PassesText]) ->
    case {string:to_integer(RoundsText), string:to_integer(PassesText)} of
        {{Rounds, []}, {Passes, []}}
                when Rounds > 0, Rounds =< ?MAX_ROUNDS,
                     Passes > 0, Passes =< ?MAX_PASSES,
                     (Rounds + 1) * Passes - 1 =< 16#ffffffff - ?FIRST_NONCE ->
            {ok, Rounds, Passes};
        _ -> error
    end;
parse_run(_) -> error.

%% Compare the broker's monotone physical frame counters over one invocation.
-spec counter_delta(map(), map()) -> map().
counter_delta(Baseline, Final) ->
    maps:map(fun(Key, Value) -> Value - maps:get(Key, Baseline) end, Final).

%% Require exact host frame counts, drained queues and clean observable transport state.
-spec validate_final(a | b, pos_integer(), pos_integer(), map(), map(), binary()) -> ok.
validate_final(Role, Rounds, Pass, Info, Delta, Status) ->
    ExpectedStream = expected_stream(Role, Rounds, Pass),
    ExpectedStream = maps:with([pending, written, received, delivered, buffered], Info),
    ExpectedTransport = expected_transport(Role, Rounds, Pass),
    ExpectedTransport = Delta,
    true = hls_dma_device:idle(Status),
    ok.

%% Stream totals include earlier board-B-originated rendezvous exchanges.
-spec expected_stream(a | b, pos_integer(), pos_integer()) -> map().
expected_stream(a, Rounds, Pass) ->
    Received = 2 * Rounds * Pass + Pass - 1,
    #{pending => 0, written => Rounds * Pass, received => Received,
      delivered => Received, buffered => 0};
expected_stream(b, Rounds, Pass) ->
    Received = Rounds * Pass + 2 * (Pass - 1),
    #{pending => 0, written => Pass - 1, received => Received,
      delivered => Received, buffered => 0}.

%% Broker totals add one identity request/response to the cumulative stream frames.
-spec expected_transport(a | b, pos_integer(), pos_integer()) -> map().
expected_transport(a, Rounds, Pass) ->
    Stream = expected_stream(a, Rounds, Pass),
    #{written => maps:get(written, Stream) + 1, received => maps:get(received, Stream) + 1,
      discarded => 0, rejected => 0, expired => 0, ignored_acks => 0};
expected_transport(b, Rounds, Pass) ->
    Stream = expected_stream(b, Rounds, Pass),
    #{written => maps:get(written, Stream) + 1, received => maps:get(received, Stream) + 1,
      discarded => 0, rejected => 0, expired => 0, ignored_acks => 0}.

%% Release logical routes during both normal completion and diagnostic failure.
-spec stop_stream(pid()) -> ok.
stop_stream(Stream) ->
    _ = catch hls_partition_stream:stop(Stream),
    ok.

%% Exercise parsing, counter arithmetic and role-specific terminal invariants offline.
-spec self_test() -> ok.
self_test() ->
    {ok, ?DEFAULT_ROUNDS, ?DEFAULT_PASSES} = parse_run([]),
    {ok, 4096, 1} = parse_run(["4096"]),
    {ok, 4096, 2} = parse_run(["4096", "2"]),
    error = parse_run(["0"]),
    error = parse_run(["1000001"]),
    error = parse_run(["16", "0"]),
    error = parse_run(["16", "1001"]),
    error = parse_run(["16", "2", "3"]),
    #{written := 5, received := 7} = counter_delta(
        #{written => 11, received => 13}, #{written => 16, received => 20}),
    #{written := 17, received := 33} = expected_transport(a, 16, 1),
    #{written := 1, received := 17} = expected_transport(b, 16, 1),
    #{written := 33, received := 66} = expected_transport(a, 16, 2),
    #{written := 2, received := 35} = expected_transport(b, 16, 2),
    CleanStatus =
        <<"tx_busy=0 rx_full=0 rx_active=0 fault=0 failed=0 rx_bytes=0 events=0 mask=7\n">>,
    true = hls_dma_device:idle(CleanStatus),
    false = hls_dma_device:idle(
        <<"tx_busy=0 rx_full=0 rx_active=0 fault=1 failed=0 rx_bytes=0 events=0 mask=7\n">>),
    <<"dma role_endpoint=application ", CleanStatus/binary>> =
        iolist_to_binary(hls_dma_device:status_line(application, CleanStatus)),
    <<"dma role_endpoint=debug ", CleanStatus/binary>> =
        iolist_to_binary(hls_dma_device:status_line(debug, CleanStatus)),
    ok.

%% Print the bounded interface accepted by this hardware-specific diagnostic.
-spec usage() -> no_return().
usage() ->
    io:format(standard_error,
        "usage: check_partition_link (--lead|--follow) [rounds [passes]] | "
        "--debug-smoke (rounds 1..~p, passes 1..~p)~n",
        [?MAX_ROUNDS, ?MAX_PASSES]),
    halt(2).
