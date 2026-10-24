-module(hls_protocol_mixed_stream_tests).
-moduledoc "Finite mixed-owner transition witnesses using actual hls_statem actors and a controlled broker. A tiny trusted plan isolates admission and write ordering; this is not distribution or hardware qualification.".
-include_lib("eunit/include/eunit.hrl").

%% A retained writer delays all sends, then an admitted ACK precedes control and credited data.
-spec write_priority_test() -> ok.
write_priority_test() ->
    with_owner(running, fun(Stream, Peer, Actors, Plan) ->
        ok = hls_protocol_relay_peer:set(Peer, hold),
        {ok, 1} = hls_protocol_mixed_stream:submit(Stream, control(0, 1)),
        await_held(Peer),
        ok = emit(Peer, data(Plan, 20, 0, 2)),
        {ok, 1} = hls_protocol_mixed_stream:submit(Stream, control(0, 3)),
        ok = gen_server:call(Stream, {source_send, maps:get(0, Actors), {actor, 2}, {total, 4}}),
        ok = emit(Peer, packet(2, 10, 1, 0)),
        await(fun() -> #{received := Count} = hls_protocol_mixed_stream:info(Stream), Count =:= 4 end),
        ?assertEqual([3, 2], operations(Peer)),
        ok = hls_protocol_relay_peer:set(Peer, normal),
        await(fun() -> #{written := Count} = hls_protocol_mixed_stream:info(Stream), Count =:= 6 end),
        ?assertEqual([3, 2, 4, 2, 4], operations(Peer)),
        ?assertMatch([#{kind := 2, link := 20, sequence := 0},
            #{kind := 1, link := 10, sequence := 0}], packets(Peer)),
        ?assertMatch(#{data := [3, 2, 1]}, hls_statem:info(maps:get(0, Actors)))
    end).

%% Full postponed mailboxes withhold their ACK, while another actor admits once and a control retains only its busy suffix.
-spec stalled_admission_test() -> ok.
stalled_admission_test() ->
    with_owner(waiting, fun(Stream, Peer, Actors, Plan) ->
        ok = emit(Peer, data(Plan, 21, 0, 10)),
        await(fun() -> length(packets(Peer)) =:= 1 end),
        ok = emit(Peer, data(Plan, 21, 1, 11)),
        await(fun() -> length(packets(Peer)) =:= 2 end),
        ok = emit(Peer, data(Plan, 21, 2, 12)),
        ok = emit(Peer, data(Plan, 20, 3, 20)),
        await(fun() -> length(packets(Peer)) =:= 3 end),
        {ok, 1} = hls_protocol_mixed_stream:submit(Stream, control(1, 30)),
        ?assertMatch(#{counts := #{commands := 1, reverse := 1}, admission := #{admitted := 4}},
            hls_protocol_mixed_stream:info(Stream)),
        %% Several natural 5 ms retries must not send the already admitted prefix again.
        timer:sleep(30),
        ?assertMatch(#{counts := #{commands := 1, reverse := 1}, admission := #{admitted := 4}},
            hls_protocol_mixed_stream:info(Stream)),
        ?assertMatch(#{data := [30, 20]}, hls_statem:info(maps:get(0, Actors))),
        ?assertMatch(#{data := [], postponed := 2, mailbox := #{occupied := 2}},
            hls_statem:info(maps:get(1, Actors))),
        ?assertEqual([0, 1, 3], [N || #{kind := 2, sequence := N} <- packets(Peer)]),
        ?assertEqual([3, 4, 4, 4], operations(Peer))
    end).

%% Retirement waits for one in-flight write and discards a later command before actor admission.
-spec retire_held_writer_test() -> ok.
retire_held_writer_test() ->
    with_owner(running, fun(Stream, Peer, Actors, _) ->
        ok = hls_protocol_relay_peer:set(Peer, hold),
        {ok, 1} = hls_protocol_mixed_stream:submit(Stream, control(0, 1)),
        await_held(Peer),
        {ok, 1} = hls_protocol_mixed_stream:submit(Stream, control(0, 2)),
        Monitor = monitor(process, Stream),
        Request = gen_server:send_request(Stream, retire),
        ?assertMatch(#{counts := #{writer := 1}}, hls_protocol_mixed_stream:info(Stream)),
        ?assertEqual(timeout, gen_server:wait_response(Request, 0)),
        ok = hls_protocol_relay_peer:set(Peer, normal),
        ?assertEqual({reply, ok}, gen_server:wait_response(Request, 1000)),
        down(Monitor, Stream, normal),
        ?assertEqual([3, 2], operations(Peer)),
        ?assertMatch(#{data := [1]}, hls_statem:info(maps:get(0, Actors)))
    end).

%% A physical error retires the incarnation without repeating actor admission or sending later commands.
-spec write_failure_test() -> ok.
write_failure_test() ->
    with_owner(running, fun(Stream, Peer, Actors, _) ->
        ok = hls_protocol_relay_peer:set(Peer, hold),
        {ok, 1} = hls_protocol_mixed_stream:submit(Stream, control(0, 1)),
        await_held(Peer),
        {ok, 1} = hls_protocol_mixed_stream:submit(Stream, control(0, 2)),
        Monitor = monitor(process, Stream),
        ok = hls_protocol_relay_peer:fail(Peer, {error, unsent}),
        down(Monitor, Stream, {shutdown, {write_failed, {error, unsent}}}),
        await(fun() -> maps:get(owner, hls_protocol_relay_peer:stats(Peer)) =:= retired end),
        ?assertEqual([3, 2], operations(Peer)),
        ?assertMatch(#{data := [1]}, hls_statem:info(maps:get(0, Actors)))
    end).

%% Two real bounded actors and one native destination suffice; a local handle models the already authenticated source binding.
-spec with_owner(waiting | running, fun((pid(), pid(), map(), map()) -> term())) -> ok.
with_owner(SecondMode, Fun) ->
    Plan = plan(),
    Actors = maps:from_list([{I, actor(Mode)} || {I, Mode} <- [{0, running}, {1, SecondMode}]]),
    Handle = spawn(fun() -> receive stop -> ok end end),
    {ok, Peer} = hls_protocol_relay_peer:start(#{host => 55, service => 7, identity => <<1:256>>}),
    try
        {ok, Stream} = hls_protocol_mixed_stream:start_link(Plan, Peer, Actors, 123, #{}),
        unlink(Stream),
        try
            await(fun() -> maps:get(phase, hls_protocol_mixed_stream:info(Stream)) =:= attached end),
            ok = gen_server:call(Stream, {source_bind, #{name => node()}, #{{actor, native} => Handle}}),
            ok = gen_server:call(Stream, {source_attach, self()}),
            {ok, 1} = hls_protocol_mixed_stream:submit(Stream, start),
            await(fun() -> #{written := Count} = hls_protocol_mixed_stream:info(Stream), Count =:= 2 end),
            ok = hls_protocol_relay_peer:emit(Peer, {16#83, 0, 0}, <<123:64/little, 0:32>>),
            ?assertEqual({ok, 123, application, {started}}, hls_protocol_mixed_stream:next(Stream, 1000)),
            Fun(Stream, Peer, Actors, Plan), ok
        after
            catch hls_protocol_relay_peer:set(Peer, normal),
            catch hls_protocol_mixed_stream:stop(Stream)
        end
    after
        catch gen_server:stop(Peer),
        [catch hls_statem:stop(Pid) || Pid <- maps:values(Actors)],
        Handle ! stop
    end.

%% Disconnected actors permit the owner to establish its exclusive input binding before activation.
-spec actor(waiting | running) -> pid().
actor(Mode) ->
    {ok, Pid} = hls_statem:start_link(hls_protocol_mixed_stream_actor, Mode, [{mailbox_capacity, 2}]),
    unlink(Pid), Pid.

%% The trusted descriptor contains only one dynamic u32 schema and explicit reverse destinations.
-spec plan() -> map().
plan() ->
    Module = hls_protocol_mixed_stream_actor,
    Codec = hls_protocol_codec:plan(#{message_bits => 32, payload_bits => 32,
        fields => [#{type => {hls_type, hls_nums, uN, [32]}, message_bit_offset => 0, capture_bit_offset => 0}]},
        Module:pack_tag(total)),
    Class = #{slot => 0, port => out, tag => total, codec => Codec, message_bits => 32},
    Links = [#{index => I, source_index => S, destination_index => D, direction => Direction,
        source_module => Module, destination_module => Module, classes => [Class]}
        || {I, S, D, Direction} <- [{10, 0, 2, to_rtl}, {20, 2, 0, to_beam}, {21, 2, 1, to_beam}]],
    Actors = maps:from_list([{I, #{module => Module, capacity => 2, startup => [],
        outputs => #{out => {actor, native}}}} || I <- [0, 1]]),
    Ingress = #{id => host, shape => [2, 1], targets => [#{id => all, selector => 0, schemas => [total]}],
        bindings => [#{module => Module, device => board, point => [I, 0], targets => [all]} || I <- [0, 1]]},
    #{actors => Actors, targets => #{{actor, native} => {actor, 2}}, binding => #{host => 55, control => 7},
        mixed => #{identity => <<1:256>>, host_actors => [0, 1], links => Links},
        application => #{partition => #{ingresses => [Ingress]},
            devices => #{board => #{host => 55, control => 7, ingress => host}}},
        ingress => #{id => host, targets => [#{id => all,
            recipients => [#{index => I, x => I, y => 0} || I <- [0, 1]]}]}}.

%% Rectangle zero selects the consuming actor; one also selects the postponed actor.
-spec control(0 | 1, non_neg_integer()) -> hls_partition_wire:command().
control(Last, Value) -> {host, all, {0, 0, Last, 0}, {total, Value}}.

%% Reuse the checked crossing codec to form native records; do not hard-code its packed bits.
-spec data(map(), non_neg_integer(), non_neg_integer(), non_neg_integer()) -> map().
data(#{mixed := #{links := Links}}, Index, Sequence, Value) ->
    [Link] = [L || L = #{index := I} <- Links, I =:= Index],
    {0, Frame} = hls_protocol_mixed:encode(Link, out, {total, Value}),
    packet(1, Index, Sequence, Frame).

%% The common native event sequence covers both data and credits in this one session.
-spec packet(1 | 2, non_neg_integer(), non_neg_integer(), non_neg_integer()) -> map().
packet(Kind, Link, Sequence, Frame) ->
    #{kind => Kind, session => 123, sequence => Sequence, link => Link, slot => 0, frame => Frame}.

%% Device output uses the same packet payload with the receive operation byte.
-spec emit(pid(), map()) -> ok.
emit(Peer, Packet) ->
    {_, Bytes} = hls_protocol_bridge_wire:packet(Packet),
    hls_protocol_relay_peer:emit(Peer, {16#84, 0, 0}, Bytes).

%% Inspect public physical-write order, including start and control requests.
-spec operations(pid()) -> [byte()].
operations(Peer) ->
    #{writes := Writes} = hls_protocol_relay_peer:stats(Peer),
    [Operation || {_, {Operation, _, _}, _} <- lists:reverse(Writes)].

%% Decode only actual actor packets written by the owner, preserving issue order.
-spec packets(pid()) -> [map()].
packets(Peer) ->
    #{writes := Writes} = hls_protocol_relay_peer:stats(Peer),
    [begin {packet, Packet} = hls_protocol_bridge_wire:event(123, {16#84, 0, 0}, Bytes), Packet end
        || {_, {4, 0, 0}, Bytes} <- lists:reverse(Writes)].

%% Every pause has a finite deadline and observes a public counter or broker receipt.
-spec await(fun(() -> boolean())) -> ok.
await(Predicate) -> hls_bridge_phi_live:await(Predicate, 1000).

%% A held completion proves that the request was issued before another event is injected.
-spec await_held(pid()) -> ok.
await_held(Peer) -> await(fun() -> maps:get(held, hls_protocol_relay_peer:stats(Peer)) =/= none end).

%% Lifecycle assertions require the exact terminal reason, not merely a missing PID.
-spec down(reference(), pid(), term()) -> ok.
down(Monitor, Stream, Reason) ->
    receive {'DOWN', Monitor, process, Stream, Reason} -> ok
    after 1000 -> error(owner_retirement_timeout) end.
