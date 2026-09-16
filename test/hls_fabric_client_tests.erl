-module(hls_fabric_client_tests).
-include_lib("eunit/include/eunit.hrl").

ownership_test_() ->
    [{atom_to_list(Kind), {timeout, 30, fun() ->
        with_client(Kind, fun(Client, Fabric) ->
            saturation(Kind, Client, Fabric),
            reply_validation(Kind, Client, Fabric),
            timeout_and_death(Kind, Client, Fabric)
        end)
    end}} || Kind <- [application, debug]].

saturation(Kind, Client, Fabric) ->
    Capacity = capacity(Kind),
    %% More than two complete ID cycles, with out-of-order completion. Values
    %% identify owners independently of wire IDs, exposing overwrite/misreply.
    lists:foreach(fun(Round) ->
        Base = length(phi_memory_fabric_fixture:sends(Fabric)),
        Requests = [{I, async(fun() -> call(Kind, Client, Round * 1000 + I, infinity) end)}
            || I <- lists:seq(1, Capacity)],
        All = phi_memory_fabric_fixture:await_sends(Fabric, Base + Capacity, 5000),
        Frames = lists:nthtail(Base, All),
        ?assertEqual(lists:seq(0, Capacity - 1), lists:sort([Tx || {_, {_, Tx, _}, _} <- Frames])),
        ?assertMatch(#{pending := Capacity, available := 0}, hls_fabric:client_info(Client)),
        ?assertEqual({error, transaction_limit}, call(Kind, Client, 99999, 1000)),
        ?assertEqual(All, phi_memory_fabric_fixture:sends(Fabric)),
        case Kind of
            application ->
                %% Successful casts are silent, but a failed one may reply.
                %% Neither consumes a call slot, even with all slots occupied.
                [gen_server:cast(Client, {set, 0, V, 0}) || V <- lists:seq(1, 300)],
                ?assertMatch(#{pending := Capacity}, hls_fabric:client_info(Client)),
                AfterCasts = phi_memory_fabric_fixture:await_sends(Fabric, length(All) + 300, 5000),
                Casts = lists:nthtail(length(All), AfterCasts),
                ?assertEqual(300, length(Casts)),
                ?assert(lists:all(fun({_, {_, Tx, _}, _}) -> Tx =:= 255 end, Casts)),
                deliver(Fabric, 1, 255, <<1:32/little>>),
                ?assertMatch(#{pending := Capacity, available := 0}, synced_info(Client, Fabric));
            debug -> ok
        end,
        %% Complete odd/even positions in reverse order, unrelated to submission.
        Permuted = lists:reverse([F || {N, F} <- lists:enumerate(Frames), N rem 2 =:= 1]) ++
            lists:reverse([F || {N, F} <- lists:enumerate(Frames), N rem 2 =:= 0]),
        [reply(Kind, Fabric, Frame) || Frame <- Permuted],
        [expect(Ref, success(Kind, Round * 1000 + I)) || {I, Ref} <- Requests],
        ?assertMatch(#{pending := 0, abandoned := 0, available := Capacity},
            synced_info(Client, Fabric))
    end, lists:seq(1, 3)).

reply_validation(Kind, Client, Fabric) ->
    {Ref, Frame = {_, {_, Tx, _}, _}} = send_one(Kind, Client, Fabric, 44, infinity),
    Ignored = maps:get(ignored_replies, hls_fabric:client_info(Client)),
    %% Wrong route, reserved flags, unknown tag, and an unowned ID must not
    %% consume the real request. The broker normally filters wrong routes.
    gen_server:cast(Client, {'$hls_fabric_frame', make_ref(), {2, 0}, {reply_tag(Kind), Tx, 0}, <<44:32/little>>}),
    gen_server:cast(Client, {'$hls_fabric_frame', make_ref(), {1, 0}, {reply_tag(Kind), Tx, 1}, <<44:32/little>>}),
    deliver(Fabric, 126, Tx, <<44:32/little>>),
    deliver(Fabric, reply_tag(Kind), (Tx + 1) rem capacity(Kind), <<44:32/little>>),
    case Kind of
        debug -> deliver(Fabric, 16#83, Tx, <<>>); % known but wrong query reply
        application -> deliver(Fabric, reply_tag(Kind), Tx, <<1, 2>>) % truncated record
    end,
    ?assertMatch(#{pending := 1}, synced_info(Client, Fabric)),
    ?assertEqual(Ignored + 5, maps:get(ignored_replies, hls_fabric:client_info(Client))),
    reply(Kind, Fabric, Frame),
    expect(Ref, success(Kind, 44)),
    reply(Kind, Fabric, Frame), % duplicate before reuse owns no slot
    ?assertMatch(#{pending := 0}, synced_info(Client, Fabric)),
    ?assertEqual(Ignored + 6, maps:get(ignored_replies, hls_fabric:client_info(Client))),
    {ErrorRef, {_, {_, ErrorTx, _}, _}} = send_one(Kind, Client, Fabric, 45, infinity),
    deliver(Fabric, error_tag(Kind), ErrorTx, <<1:32/little>>),
    case Kind of
        application -> expect(ErrorRef, {error, {remote_error, function_clause}});
        debug -> expect(ErrorRef, {error, #{reason => {debug_error, 1}, raw => <<1:32/little>>}})
    end.

timeout_and_death(Kind, Client, Fabric) ->
    %% gen_server:call timeout deactivates its reply alias but does not notify
    %% the proxy or cancel device work. Keep that caller alive to test this.
    {TimedOut, TimedFrame} = send_one(Kind, Client, Fabric, 51, 20),
    receive {result, TimedOut, {exit, {timeout, _}}} -> ok after 1000 -> error(no_timeout) end,
    ?assertMatch(#{pending := 1, abandoned := 0}, hls_fabric:client_info(Client)),
    {Dead, DeadFrame} = send_one(Kind, Client, Fabric, 52, infinity),
    exit(Dead, kill),
    await_info(Client, fun(#{abandoned := N}) -> N =:= 1 end),
    %% Exhaust everything else: neither timeout nor death authorizes reuse.
    Capacity = capacity(Kind),
    Base = length(phi_memory_fabric_fixture:sends(Fabric)),
    Refs = [{V, async(fun() -> call(Kind, Client, V, infinity) end)}
        || V <- lists:seq(100, 100 + Capacity - 3)],
    All = phi_memory_fabric_fixture:await_sends(Fabric, Base + Capacity - 2, 5000),
    LiveFrames = lists:nthtail(Base, All),
    ?assertEqual({error, transaction_limit}, call(Kind, Client, 999, 1000)),
    case Kind of
        application ->
            {_, {_, TimedTx, _}, _} = TimedFrame,
            {_, {_, DeadTx, _}, _} = DeadFrame,
            [deliver(Fabric, regsvc:pack_tag(read), Tx, <<51:32/little>>)
                || Tx <- [TimedTx, DeadTx]],
            ?assertMatch(#{available := 0, abandoned := 1}, synced_info(Client, Fabric));
        debug -> ok
    end,
    %% The late old reply releases exactly its own slot. The next request may
    %% now reuse it, while the other abandoned request remains unavailable.
    reply(Kind, Fabric, TimedFrame),
    ?assertMatch(#{available := 1, abandoned := 1}, synced_info(Client, Fabric)),
    ?assertEqual({message_queue_len, 0}, hls_debug:info(TimedOut, message_queue_len)),
    TimedOut ! finish,
    {New, NewFrame = {_, {_, NewTx, _}, _}} = send_one(Kind, Client, Fabric, 53, infinity),
    {_, {_, OldTx, _}, _} = TimedFrame,
    ?assertEqual(OldTx, NewTx),
    reply(Kind, Fabric, DeadFrame),
    reply(Kind, Fabric, NewFrame),
    expect(New, success(Kind, 53)),
    [reply(Kind, Fabric, F) || F <- LiveFrames],
    [expect(Ref, success(Kind, V)) || {V, Ref} <- Refs],
    ?assertMatch(#{pending := 0, abandoned := 0, available := Capacity}, synced_info(Client, Fabric)).

broker_death_test_() ->
    [{atom_to_list(Kind), fun() -> with_client(Kind, fun(Client, Fabric) ->
        {A, _} = send_one(Kind, Client, Fabric, 1, infinity),
        {B, _} = send_one(Kind, Client, Fabric, 2, infinity),
        unlink(Fabric),
        exit(Fabric, kill),
        expect(A, {error, {transport_down, killed}}),
        expect(B, {error, {transport_down, killed}}),
        ?assertMatch(#{status := {down, killed}, pending := 0, available := 0},
            hls_fabric:client_info(Client)),
        ?assertEqual({error, {transport_down, killed}}, call(Kind, Client, 3, 1000))
    end) end} || Kind <- [application, debug]].

send_failure_test_() ->
    [{atom_to_list(Kind), fun() -> with_client(Kind, fun(Client, Fabric) ->
        {First, _} = send_one(Kind, Client, Fabric, 1, infinity),
        phi_memory_fabric_fixture:fail_next_send(Fabric, eio),
        Expected = {error, {transport_down, {send_failed, eio}}},
        ?assertEqual(Expected, call(Kind, Client, 2, 1000)),
        expect(First, Expected),
        %% The fixture remains alive to check that failure closes this client
        %% independently of whether the broker sends a subsequent DOWN.
        ?assertEqual(Expected, call(Kind, Client, 3, 1000)),
        ?assertEqual(1, length(phi_memory_fabric_fixture:sends(Fabric))),
        ?assertMatch(#{pending := 0, available := 0, status := {down, _}},
            hls_fabric:client_info(Client))
    end) end} || Kind <- [application, debug]].

initial_send_failure_test_() ->
    [{atom_to_list(Kind), fun() -> with_client(Kind, fun(Client, Fabric) ->
        phi_memory_fabric_fixture:fail_next_send(Fabric, eio),
        ?assertEqual({error, {transport_down, {send_failed, eio}}}, call(Kind, Client, 1, 1000)),
        ?assertMatch(#{pending := 0, available := 0, status := {down, _}},
            hls_fabric:client_info(Client))
    end) end} || Kind <- [application, debug]].

broker_dies_during_send_test_() ->
    [{atom_to_list(Kind), fun() -> with_client(Kind, fun(Client, Fabric) ->
        {First, _} = send_one(Kind, Client, Fabric, 1, infinity),
        phi_memory_fabric_fixture:hold_next_send(Fabric),
        {Sending, _} = send_one(Kind, Client, Fabric, 2, infinity),
        unlink(Fabric),
        exit(Fabric, kill),
        [receive {result, Ref, Result} ->
            Ref ! finish,
            ?assertMatch({error, {transport_down, killed}}, Result)
        after 1000 -> error(send_did_not_fail) end || Ref <- [First, Sending]],
        ?assertMatch(#{pending := 0, available := 0, status := {down, _}},
            hls_fabric:client_info(Client))
    end) end} || Kind <- [application, debug]].

not_sent_preserves_other_ownership_test_() ->
    [{atom_to_list(Kind), fun() -> with_client(Kind, fun(Client, Fabric) ->
        {First, Frame} = send_one(Kind, Client, Fabric, 1, infinity),
        phi_memory_fabric_fixture:fail_next_send(Fabric, {not_sent, tx_limit}),
        ?assertEqual({error, {not_sent, tx_limit}}, call(Kind, Client, 2, 1000)),
        ?assertMatch(#{status := up, pending := 1, rejected_requests := 1}, hls_fabric:client_info(Client)),
        {Next, NextFrame} = send_one(Kind, Client, Fabric, 3, infinity),
        reply(Kind, Fabric, NextFrame),
        reply(Kind, Fabric, Frame),
        expect(First, success(Kind, 1)),
        expect(Next, success(Kind, 3)),
        ?assertMatch(#{status := up, pending := 0}, hls_fabric:client_info(Client))
    end) end} || Kind <- [application, debug]].

reply_before_write_completion_test_() ->
    [{atom_to_list(Kind), fun() -> with_client(Kind, fun(Client, Fabric) ->
        phi_memory_fabric_fixture:hold_next_send(Fabric),
        {First, Frame} = send_one(Kind, Client, Fabric, 1, infinity),
        reply(Kind, Fabric, Frame),
        expect(First, success(Kind, 1)),
        ?assertMatch(#{status := up, pending := 0, transmitting := 1}, hls_fabric:client_info(Client)),
        {Next, NextFrame} = send_one(Kind, Client, Fabric, 2, infinity),
        phi_memory_fabric_fixture:release_sends(Fabric),
        reply(Kind, Fabric, NextFrame),
        expect(Next, success(Kind, 2)),
        ?assertMatch(#{status := up, pending := 0, transmitting := 0}, synced_info(Client, Fabric))
    end) end} || Kind <- [application, debug]].

cast_overload_is_observable_test() ->
    with_client(application, fun(Client, Fabric) ->
        phi_memory_fabric_fixture:hold_sends(Fabric),
        {First, _} = send_one(application, Client, Fabric, 1, infinity),
        #{transmit_capacity := Capacity} = hls_fabric:client_info(Client),
        [gen_server:cast(Client, {set, 0, I, 0}) || I <- lists:seq(1, Capacity)],
        expect(First, {error, {transport_down, {cast_not_sent, tx_limit}}}),
        ?assertMatch(#{status := {down, {cast_not_sent, tx_limit}}, pending := 0, transmitting := 0},
            hls_fabric:client_info(Client)),
        ?assertEqual(Capacity, length(phi_memory_fabric_fixture:await_sends(Fabric, Capacity, 1000))),
        gen_server:cast(Client, {set, 0, 999, 0}),
        ?assertMatch(#{status := {down, _}}, hls_fabric:client_info(Client)),
        ?assertEqual(Capacity, length(phi_memory_fabric_fixture:sends(Fabric)))
    end).

cpu_info_test() ->
    {ok, Client} = regsvc:start_link(),
    try ?assertEqual(none, hls_fabric:client_info(Client))
    after hls_gs:stop(Client) end.

per_request_reply_sets_test() ->
    with_client({application, hls_reply_fixture}, fun(Client, Fabric) ->
        Read = async(fun() -> gen_server:call(Client, {read, 0}) end),
        [{_, {_, ReadTx, _}, _}] = phi_memory_fabric_fixture:await_sends(Fabric, 1, 1000),
        Query = async(fun() -> gen_server:call(Client, {query, 1, 23}) end),
        [_, {_, {_, QueryTx, _}, _}] = phi_memory_fabric_fixture:await_sends(Fabric, 2, 1000),
        Tag = fun hls_reply_fixture:pack_tag/1,
        %% A record allowed for one live request is not allowed for another.
        %% All of these carry owned IDs and correct routes/flags.
        deliver(Fabric, Tag(large), ReadTx, <<23:32/little, 7:32/little>>),
        deliver(Fabric, Tag(wrong), QueryTx, <<23:32/little>>),
        deliver(Fabric, Tag(read), ReadTx, <<0:32/little>>),
        deliver(Fabric, Tag(ledger), ReadTx, <<7:32/little>>),
        deliver(Fabric, Tag(small), ReadTx, <<7:32/little, 99:32/little>>),
        deliver(Fabric, Tag(small), ReadTx, <<7, 0>>),
        deliver(Fabric, Tag(error), ReadTx, <<>>),
        deliver(Fabric, Tag(error), ReadTx, <<15, 0>>),
        deliver(Fabric, Tag(error), ReadTx, <<15:32/little, 99:32/little>>),
        ?assertMatch(#{pending := 2, ignored_replies := 9}, synced_info(Client, Fabric)),
        ?assertEqual({error, {invalid_request, call, change}},
            gen_server:call(Client, {change, 99})),
        ?assertEqual({error, {invalid_request, call, wrong}},
            gen_server:call(Client, {wrong, 99})),
        ?assertEqual(2, length(phi_memory_fabric_fixture:sends(Fabric))),
        deliver(Fabric, Tag(large), QueryTx, <<23:32/little, 7:32/little>>),
        expect(Query, {large, 23, 7}),
        ?assertMatch(#{pending := 1}, synced_info(Client, Fabric)),
        deliver(Fabric, Tag(small), ReadTx, <<7:32/little>>),
        expect(Read, {small, 7}),
        Error = async(fun() -> gen_server:call(Client, {query, 2, 99}) end),
        [_, _, {_, {_, ErrorTx, _}, _}] = phi_memory_fabric_fixture:await_sends(Fabric, 3, 1000),
        deliver(Fabric, Tag(error), ErrorTx, <<15:32/little>>),
        expect(Error, {error, {remote_error, reply_contract}}),
        Small = async(fun() -> gen_server:call(Client, {query, 0, 101}) end),
        [_, _, _, {_, {_, SmallTx, _}, _}] = phi_memory_fabric_fixture:await_sends(Fabric, 4, 1000),
        deliver(Fabric, Tag(small), SmallTx, <<101:32/little>>),
        expect(Small, {small, 101}),
        ?assertMatch(#{pending := 0, ignored_replies := 9}, synced_info(Client, Fabric))
    end).

dense_application_payload_test() ->
    with_client({application, hls_logical_fixture}, fun(Client, Fabric) ->
        Ref = async(fun() -> gen_server:call(Client, {step, true, 7, -129}) end),
        [{_, {_, Tx, _}, Payload}] = phi_memory_fabric_fixture:await_sends(Fabric, 1, 1000),
        ?assertEqual(<<1:1, 7:3, -129:9/little, 0:19>>, Payload),
        Tag = hls_logical_fixture:pack_tag(result),
        %% Only the final word's trailing padding is ignored, not missing or extra words.
        [deliver(Fabric, Tag, Tx, Wrong) || Wrong <- [<<>>, <<255, 23>>, <<0:64>>]],
        ?assertMatch(#{pending := 1, ignored_replies := 3}, synced_info(Client, Fabric)),
        deliver(Fabric, Tag, Tx, <<1:1, 7:3, -129:9/little, -1:19>>),
        expect(Ref, {result, true, 7, -129}),
        ?assertMatch(#{pending := 0}, synced_info(Client, Fabric))
    end).

with_client(Kind, Run) ->
    {ok, Fabric} = phi_memory_fabric_fixture:start_link(),
    {ok, Client} = case Kind of
        application -> hls_gs:start_link(regsvc, [], [{fabric, Fabric, 1}]);
        {application, Module} -> hls_gs:start_link(Module, [], [{fabric, Fabric, 1}]);
        debug -> hls_debug:start_link(undefined, {fabric, Fabric, 1})
    end,
    try Run(Client, Fabric)
    after
        gen_server:stop(Client),
        case is_process_alive(Fabric) of true -> gen_server:stop(Fabric); false -> ok end
    end.

capacity(application) -> 255;
capacity(debug) -> 256.
call(application, Client, Value, Timeout) -> gen_server:call(Client, {ping, Value}, Timeout);
call(debug, Client, Value, Timeout) -> hls_debug:query(Client, 1, <<Value:32/little>>, Timeout).
success(application, Value) -> {ack, Value};
success(debug, Value) -> {ok, <<Value:32/little>>}.
reply_tag(application) -> regsvc:pack_tag(ack);
reply_tag(debug) -> 16#81.
error_tag(application) -> regsvc:pack_tag(error);
error_tag(debug) -> 16#ff.
reply(Kind, Fabric, {_, {_, Tx, _}, Payload}) -> deliver(Fabric, reply_tag(Kind), Tx, Payload).
deliver(Fabric, Tag, Tx, Payload) ->
    ok = phi_memory_fabric_fixture:deliver(Fabric, {1, 0}, {Tag, Tx, 0}, Payload).

async(Fun) ->
    Parent = self(),
    spawn(fun() ->
        Monitor = monitor(process, Parent),
        Result = try Fun() catch exit:Reason -> {exit, Reason} end,
        Parent ! {result, self(), Result},
        receive finish -> ok; {'DOWN', Monitor, process, Parent, _} -> ok end
    end).
expect(Ref, Expected) ->
    receive {result, Ref, Actual} -> Ref ! finish, ?assertEqual(Expected, Actual)
    after 5000 -> error({missing_reply, Ref}) end.
send_one(Kind, Client, Fabric, Value, Timeout) ->
    Count = length(phi_memory_fabric_fixture:sends(Fabric)),
    Ref = async(fun() -> call(Kind, Client, Value, Timeout) end),
    Frames = phi_memory_fabric_fixture:await_sends(Fabric, Count + 1, 5000),
    {Ref, lists:last(Frames)}.

%% Messages from different senders need an explicit barrier. The fabric sends
%% this call after its preceding reply casts, so observing it orders the probe.
synced_info(_Client, Fabric) ->
    phi_memory_fabric_fixture:client_info(Fabric, {1, 0}).

await_info(Client, Predicate) -> await_info(Client, Predicate, 1000).
await_info(Client, Predicate, 0) -> error({client_status_timeout, Predicate, hls_fabric:client_info(Client)});
await_info(Client, Predicate, Tries) ->
    Info = hls_fabric:client_info(Client),
    case Predicate(Info) of
        true -> Info;
        false -> receive after 1 -> ok end, await_info(Client, Predicate, Tries - 1)
    end.
