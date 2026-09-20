#!/usr/bin/env escript
%%! +S 1:1 +A 2 +SDio 4
%% Inspect and exercise the routed DMA image through public codecs and clients.
-mode(compile).

-doc "Check two register services, independent debug under congestion, and quiescent driver rebind.".
-spec main([string()]) -> ok.
main([]) ->
    {ok, Debug} = hls_fabric:start_link("/dev/hls-dma1", "/dev/hls-dma1"),
    D = [begin {ok, P} = hls_debug:start_link(regsvc, {fabric, Debug, ID}), P end || ID <- [1, 2]],
    pressure(hd(D)),
    {ok, App} = hls_fabric:start_link("/dev/hls-dma0", "/dev/hls-dma0"),
    A = [begin {ok, P} = hls_gs:start_link(regsvc, [], [{fabric, App, ID}]), P end || ID <- [1, 2]],
    lists:foreach(fun({ID, P}) ->
        ok = regsvc:set(P, 0, ID * 100, 16#ffffffff),
        [Value, 0, 0] = regsvc:bulk_get(P, 0, 3),
        true = Value =:= ID * 100
    end, lists:zip([1, 2], A)),
    lists:foreach(fun(Round) ->
        Requests = [{Round * 100 + ID, gen_server:send_request(P, {ping, Round * 100 + ID})}
                    || {ID, P} <- lists:zip([1, 2], A)],
        [{reply, {ack, Value}} = gen_server:wait_response(R, 10000) || {Value, R} <- Requests]
    end, lists:seq(1, 260)),
    io:format("PASS: two DMA-routed actors, isolated registers and transaction-ID reuse~n"),
    lists:foreach(fun({P, DP}) -> full_trace(P, DP) end, lists:zip(A, D)),
    [ok = regsvc:stop(P) || P <- A],
    [ok = hls_debug:stop(P) || P <- D],
    detach([App, Debug]),
    %% Every application/debug reply has been consumed. Rebind preserves actor
    %% state; this is explicitly a quiescent transport test, not a reset protocol.
    driver("bind", "40004000.dma-mailbox"),
    driver("bind", "40000000.dma-mailbox"),
    {ok, Again} = hls_fabric:start_link("/dev/hls-dma0", "/dev/hls-dma0"),
    {ok, Pid} = hls_gs:start_link(regsvc, [], [{fabric, Again, 2}]),
    200 = regsvc:get(Pid, 0),
    ok = regsvc:stop(Pid),
    detach([Again]),
    io:format("PASS: DMA owners closed; reverse-order rebind preserved names and actor state~n"),
    io:format("PASS: ARM BEAM routed application and independent DMA debug~n");
main(_) -> halt(2).

%% Leave the first reply in RX RAM; the next reply must stall while debug works.
-spec pressure(pid()) -> ok.
pressure(Debug) ->
    {ok, FD} = file:open("/dev/hls-dma0", [read, write, raw, binary]),
    try
        C1 = send_ping(FD, 17, 16#12345678),
        await_full(erlang:monotonic_time(millisecond) + 5000),
        C2 = send_ping(FD, 18, 16#87654321),
        Counters = await_stall(Debug, erlang:monotonic_time(millisecond) + 5000),
        io:format("Blocked application, public debug counters: ~p~n", [Counters]),
        {ok, #{observation_drops := 0}} = hls_debug:get_trace(Debug),
        receive_ping(FD, 17, 16#12345678, C1),
        receive_ping(FD, 18, 16#87654321, C2),
        io:format("PASS: debug counters and trace remain usable while application RX is full~n")
    after file:close(FD) end.

%% Encode the same call contract used by an hls_gs proxy, with explicit test IDs.
-spec send_ping(file:io_device(), byte(), non_neg_integer()) -> term().
send_ping(FD, ID, Value) ->
    {Tag, Payload, Context} = hls_gs:encode_request(regsvc, call, {ping, Value}),
    {ok, Frame} = hls_fabric_io:encode({0, 1}, {Tag, ID, 0}, Payload),
    ok = file:write(FD, Frame),
    Context.

%% Consume each response in deliberately small reads and decode its public type.
-spec receive_ping(file:io_device(), byte(), non_neg_integer(), term()) -> ok.
receive_ping(FD, ID, Value, Context) ->
    <<0:16/little, 1:16/little, Words, ID, 0, Tag>> = exact(FD, 8),
    {reply, {ack, Value}} = hls_gs:decode_reply(Tag, exact(FD, 4 * Words), Context),
    ok.

%% Read one bounded fragment at a time without crossing the requested frame field.
-spec exact(file:io_device(), non_neg_integer()) -> binary().
exact(_FD, 0) -> <<>>;
exact(FD, Bytes) ->
    {ok, Part} = file:read(FD, min(3, Bytes)),
    <<Part/binary, (exact(FD, Bytes - byte_size(Part)))/binary>>.

%% Use the driver's public status rather than a timing guess to hold RX storage.
-spec await_full(integer()) -> ok.
await_full(Deadline) ->
    {ok, Status} = file:read_file("/sys/bus/platform/devices/40000000.dma-mailbox/status"),
    case binary:match(Status, <<"rx_full=1">>) of
        nomatch -> true = erlang:monotonic_time(millisecond) < Deadline,
                   timer:sleep(1), await_full(Deadline);
        _ -> ok
    end.

%% Require increasing hardware stall evidence while the separate debug lane runs.
-spec await_stall(pid(), integer()) -> map().
await_stall(Debug, Deadline) ->
    {ok, #{app_tx_stall_cycles := Cycles, observation_drops := 0} = Counters} =
        hls_debug:get_counters(Debug),
    case Cycles > 0 of
        true -> Counters;
        false -> true = erlang:monotonic_time(millisecond) < Deadline,
                 await_stall(Debug, Deadline)
    end.

%% Drain an 800-byte routed trace frame and check bounded overflow accounting.
-spec full_trace(pid(), pid()) -> ok.
full_trace(App, Debug) ->
    {ok, _} = hls_debug:get_trace(Debug),
    [Value = regsvc:ping(App, Value) || Value <- lists:seq(1, 40)],
    {ok, #{count := 64, dropped := 16, observation_drops := 0, events := Events}} =
        hls_debug:get_trace(Debug),
    64 = length(Events),
    {ok, #{count := 0, dropped := 0}} = hls_debug:get_trace(Debug),
    io:format("PASS: full 64-event debug trace over DMA, then empty drain~n").

%% Stop owners, detach quiescent hardware to wake raw reads, then confirm closure.
-spec detach([pid()]) -> ok.
detach(Devices) ->
    Leases = [begin
        #{io := #{lease := Lease}} = hls_fabric:info(Device),
        ok = hls_fabric:stop(Device),
        Lease
    end || Device <- Devices],
    driver("unbind", "40000000.dma-mailbox"),
    driver("unbind", "40004000.dma-mailbox"),
    [ok = hls_fabric:await_closed(Lease, 5000) || Lease <- Leases],
    ok.

%% Rebind/unbind only this explicit two-mailbox bring-up fixture.
-spec driver(string(), string()) -> ok.
driver(Operation, Device) ->
    file:write_file("/sys/bus/platform/drivers/hls-dma-mailbox/" ++ Operation, Device).
