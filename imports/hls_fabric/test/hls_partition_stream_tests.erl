-module(hls_partition_stream_tests).
-include_lib("eunit/include/eunit.hrl").

%% Explicit wire words must not inherit DSLX's structural flattening order.
-spec command_encoding_test() -> ok.
command_encoding_test() ->
    Deployment = deployment(),
    Tag = hls_partition_fixture:pack_tag(work),
    [{a, {1, 7}, {2, 0, 0}, Bytes}] = hls_partition_wire:command(Deployment, command(0, 42)),
    ?assertEqual(<<0:16/little, 0:16/little, 0:16/little, 0:16/little,
        0:32/little, 1:8, 0:16, Tag:8, 42:32/little>>, Bytes),
    #{devices := #{a := A, b := B}} = Deployment,
    ?assertNotEqual(maps:get(identity, A), maps:get(identity, B)),
    ?assertEqual({reports, {work, 42}}, hls_partition_wire:event(A, {8, 1}, {Tag, 0, 0}, <<42:32/little>>)),
    ?assertException(error, _, hls_partition_wire:event(A, {8, 2}, {Tag, 0, 0}, <<42:32/little>>)),
    ?assertException(error, _, hls_partition_wire:event(A, {8, 1}, {Tag, 0, 0}, <<42:64/little>>)).

%% A valid narrow value must not hide noncanonical bits in its final wire word.
-spec event_padding_is_checked_test() -> ok.
event_padding_is_checked_test() ->
    Tag = packed_samples:pack_tag(clear),
    Schema = #{name => clear, selector => Tag, width => 1,
        codec => hls_record_codec:bind(clear, [{value, hls_nums:uN(1)}])},
    Binding = #{host => 1, events => #{8 => #{id => samples,
        schemas => #{Tag => Schema}}}},
    Message = {clear, 1},
    Payload = hls_codec:align(packed_samples:pack(Message), 32),
    ?assertEqual({samples, Message}, hls_partition_wire:event(Binding, {8, 1}, {Tag, 0, 0}, Payload)),
    <<Value:32/little>> = Payload,
    ?assertException(error, _, hls_partition_wire:event(Binding, {8, 1}, {Tag, 0, 0},
        <<(Value bxor (1 bsl 31)):32/little>>)).

%% The fixed event envelope admits its last complete word and rejects truncating layouts.
-spec gateway_payload_capacity_test() -> ok.
gateway_payload_capacity_test() ->
    #{devices := Devices} = Deployment = deployment(),
    #{local := Local} = Binding = maps:get(a, Devices),
    AtCapacity = Deployment#{devices := Devices#{a := Binding#{local :=
        Local#{frame_layout := hls_frame_layout:new(8)}}}},
    Text = iolist_to_binary(hls_partition_wire:wrapper(AtCapacity, a, test_graph)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"spawn hls_partition_io::Boundary">>)),
    OverCapacity = Deployment#{devices := Devices#{a := Binding#{local :=
        Local#{frame_layout := hls_frame_layout:new(9)}}}},
    ?assertError({hls_diagnostic, #{stage := partition, code := gateway_payload_capacity,
        context := #{payload_words := 9, maximum := 8}}},
        hls_partition_wire:wrapper(OverCapacity, a, test_graph)).

%% Route credits bound retained events; a timed-out receive leaves no abandoned interest.
-spec credited_events_and_timeout_test() -> ok.
credited_events_and_timeout_test() ->
    with_connection(#{}, fun(Stream, #{a := A}) ->
        ?assertEqual(timeout, hls_partition_stream:next(Stream, 0)),
        ok = hls_partition_peer:emit(A, event(1, 10)),
        ok = hls_partition_peer:emit(A, event(1, 20)),
        await(fun() -> maps:get(buffered, hls_partition_stream:info(Stream)) =:= 1 end),
        ?assertEqual(1, maps:get(receipts, hls_partition_peer:stats(A))),
        ?assertEqual({ok, a, reports, {work, 10}}, hls_partition_stream:next(Stream, 1000)),
        ?assertEqual({ok, a, reports, {work, 20}}, hls_partition_stream:next(Stream, 1000)),
        ?assertEqual(timeout, hls_partition_stream:next(Stream, 0))
    end).

%% A blocked physical writer does not prevent credited reads or inspection.
-spec stalled_write_and_atomic_admission_test() -> ok.
stalled_write_and_atomic_admission_test() ->
    with_connection(#{queue_limit => 1}, fun(Stream, Peers = #{a := A}) ->
        Both = {control, cells, {0, 0, 1, 0}, {work, 9}},
        ?assertEqual({error, busy}, hls_partition_stream:submit(Stream, Both)),
        [?assertEqual([], maps:get(controls, hls_partition_peer:stats(P))) || P <- maps:values(Peers)],
        ok = hls_partition_peer:set(A, hold),
        ?assertEqual({ok, 1}, hls_partition_stream:submit(Stream, command(0, 1))),
        await(fun() -> length(maps:get(controls, hls_partition_peer:stats(A))) =:= 1 end),
        ?assertEqual({error, busy}, hls_partition_stream:submit(Stream, command(0, 2))),
        ok = hls_partition_peer:emit(A, event(1, 7)),
        ?assertEqual({ok, a, reports, {work, 7}}, hls_partition_stream:next(Stream, 1000)),
        ?assertEqual(1, maps:get(pending, hls_partition_stream:info(Stream))),
        ok = hls_partition_peer:set(A, normal),
        await(fun() -> maps:get(pending, hls_partition_stream:info(Stream)) =:= 0 end)
    end).

%% Only proven non-transmission retries, retaining sequence even with later submissions.
-spec admission_retry_keeps_order_test() -> ok.
admission_retry_keeps_order_test() ->
    with_connection(#{}, fun(Stream, #{a := A}) ->
        ok = hls_partition_peer:set(A, reject_once),
        {ok, 1} = hls_partition_stream:submit(Stream, command(0, 11)),
        {ok, 1} = hls_partition_stream:submit(Stream, command(0, 22)),
        await(fun() -> maps:get(written, hls_partition_stream:info(Stream)) =:= 2 end),
        Values = [V || {_, <<_:128, V:32/little>>} <- maps:get(controls, hls_partition_peer:stats(A))],
        ?assertEqual([11, 22], Values)
    end).

%% Capacity retries must not extend a command's original write deadline.
-spec admission_retry_deadline_test() -> ok.
admission_retry_deadline_test() ->
    with_connection(#{write_timeout => 200}, fun(Stream, #{a := A}) ->
        Ref = monitor(process, Stream),
        ok = hls_partition_peer:set(A, reject_forever),
        {ok, 1} = hls_partition_stream:submit(Stream, command(0, 5)),
        receive {'DOWN', Ref, process, Stream, Reason} ->
            ?assertMatch({write_failed, a, {reply, {error, {not_sent, timeout}}}}, Reason)
        after 1000 -> error(deadline_extended) end,
        ?assertEqual([], maps:get(controls, hls_partition_peer:stats(A)))
    end).

%% Invalid commands and foreign callers cannot mutate another owner's stream.
-spec rejected_calls_preserve_connection_test() -> ok.
rejected_calls_preserve_connection_test() ->
    with_connection(#{}, fun(Stream, #{a := A}) ->
        ?assertMatch({error, {invalid_command, _}}, hls_partition_stream:submit(Stream, command(2, 0))),
        Parent = self(),
        spawn(fun() -> Parent ! {foreign, hls_partition_stream:next(Stream, 0)} end),
        receive {foreign, Result} -> ?assertEqual({error, not_owner}, Result) after 1000 -> error(timeout) end,
        ?assertEqual([], maps:get(controls, hls_partition_peer:stats(A)))
    end).

%% Ambiguous completion ends all sessions without trying a second write.
-spec ambiguous_write_aborts_test() -> ok.
ambiguous_write_aborts_test() ->
    with_connection(#{}, fun(Stream, Peers = #{a := A}) ->
        Monitor = monitor(process, Stream),
        ok = hls_partition_peer:set(A, ambiguous),
        {ok, 1} = hls_partition_stream:submit(Stream, command(0, 1)),
        receive {'DOWN', Monitor, process, Stream, Reason} ->
            ?assertMatch({write_failed, a, _}, Reason)
        after 1000 -> error(no_abort) end,
        await(fun() -> lists:all(fun(P) ->
            lists:all(fun(R) -> R =:= retired end, maps:values(maps:get(routes, hls_partition_peer:stats(P))))
        end, maps:values(Peers)) end)
    end).

%% A mismatching gateway never produces an apparently usable host connection.
-spec wrong_identity_retires_partial_attachment_test() -> ok.
wrong_identity_retires_partial_attachment_test() ->
    Deployment = #{devices := Devices} = deployment(),
    Peers = maps:map(fun(D, Binding) ->
        Actual = case D of a -> Binding; b -> Binding#{identity := <<0:256>>} end,
        {ok, Peer} = hls_partition_peer:start(Actual), Peer
    end, Devices),
    Old = process_flag(trap_exit, true),
    try
        ?assertMatch({error, {attachment_failed, error, {identity_response, _}}},
            hls_partition_stream:start_link(Deployment, Peers, #{})),
        await(fun() -> lists:all(fun(P) ->
            lists:all(fun(R) -> R =:= retired end, maps:values(maps:get(routes, hls_partition_peer:stats(P))))
        end, maps:values(Peers)) end)
    after
        [gen_server:stop(P) || P <- maps:values(Peers)],
        receive {'EXIT', _, _} -> ok after 0 -> ok end,
        process_flag(trap_exit, Old)
    end.

%% Losing either physical broker invalidates the complete partition connection.
-spec peer_death_aborts_test() -> ok.
peer_death_aborts_test() ->
    with_connection(#{}, fun(Stream, #{a := A}) ->
        Ref = monitor(process, Stream),
        exit(A, kill),
        receive {'DOWN', Ref, process, Stream, Reason} ->
            ?assertMatch({connection_down, {device_down, killed}}, Reason)
        after 1000 -> error(no_abort) end
    end).

%% Bad event metadata cannot enter the application reducer as a plausible record.
-spec malformed_event_aborts_test() -> ok.
malformed_event_aborts_test() ->
    with_connection(#{}, fun(Stream, #{a := A}) ->
        Ref = monitor(process, Stream),
        ok = hls_partition_peer:emit(A, {{8, 1}, {255, 0, 0}, <<0:32>>}),
        receive {'DOWN', Ref, process, Stream, Reason} ->
            ?assertMatch({invalid_event, a, _, _}, Reason)
        after 1000 -> error(no_abort) end
    end).

%% A normal caller exit still retires its sessions rather than leaving a detached owner.
-spec owner_death_retires_stream_test() -> ok.
owner_death_retires_stream_test() ->
    Deployment = #{devices := Devices} = deployment(),
    Peers = maps:map(fun(_, B) -> {ok, P} = hls_partition_peer:start(B), P end, Devices),
    Parent = self(),
    Owner = spawn(fun() ->
        {ok, Stream} = hls_partition_stream:start_link(Deployment, Peers, #{}),
        Parent ! {owned, self(), Stream},
        receive done -> ok end
    end),
    try
        receive {owned, Owner, Stream} ->
            Ref = monitor(process, Stream),
            Owner ! done,
            receive {'DOWN', Ref, process, Stream, _} -> ok after 1000 -> error(owner_leaked) end
        after 1000 -> error(no_owner) end,
        await(fun() -> lists:all(fun(P) ->
            lists:all(fun(R) -> R =:= retired end, maps:values(maps:get(routes, hls_partition_peer:stats(P))))
        end, maps:values(Peers)) end)
    after [gen_server:stop(P) || P <- maps:values(Peers)] end.

%% Reuse a two-cell topology with real generated codecs and a single control ingress.
-spec deployment() -> map().
deployment() ->
    Spec = #{version => 1, actors => #{}, families => #{cells => #{module => hls_partition_fixture, shape => [2, 1]}},
        ingresses => [{control, {rectangle, [2, 1]}, [{cells, [work], [{family, cells, {embed, [1, 1], [0, 0]}}]}]}],
        externals => [{reports, out, [work]}], routes => [], startup => [],
        route_relations => [{{cells, Port}, [{external, reports}]} || Port <- [left, right, report]]},
    Partition = hls_partition:normalize(hls_topology:normalize(Spec),
        #{{family, cells, [0, 0]} => a, {family, cells, [1, 0]} => b}),
    hls_partition_wire:deployment(Partition).

%% Isolate device models and retire the tested stream before fixture cleanup.
-spec with_connection(map(), fun((pid(), map()) -> term())) -> ok.
with_connection(Options, Fun) ->
    Deployment = #{devices := Devices} = deployment(),
    Peers = maps:map(fun(_, Binding) -> {ok, P} = hls_partition_peer:start(Binding), P end, Devices),
    {ok, Stream} = hls_partition_stream:start_link(Deployment, Peers, Options),
    unlink(Stream),
    try Fun(Stream, Peers), ok
    after
        catch hls_partition_stream:stop(Stream),
        [catch gen_server:stop(P) || P <- maps:values(Peers)]
    end.

%% Select one cell, preserving command order on its device.
-spec command(non_neg_integer(), non_neg_integer()) -> tuple().
command(X, Value) -> {control, cells, {X, 0, X, 0}, {work, Value}}.

%% Construct an unsolicited event using the generated schema selector.
-spec event(pos_integer(), non_neg_integer()) -> tuple().
event(Host, Value) -> {{8, Host}, {hls_partition_fixture:pack_tag(work), 0, 0}, <<Value:32/little>>}.

%% Wait for asynchronous test-broker transitions without assuming scheduler order.
-spec await(fun(() -> boolean())) -> ok.
await(Fun) -> hls_bridge_phi_live:await(Fun, 1000).
