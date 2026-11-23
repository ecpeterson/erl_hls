-module(hls_domain_recovery_live).
-moduledoc "Finite recovery witness against two actual compiled source networks and a real ERTS distribution peer. Local RTL simulation is not native placement, hardware watchdog or board admission evidence.".
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").
%% External RTL driver entry and peer-side monitor helper.
-export([run/2, watch/2]).

-doc "Runs the matched compiled-domain witness, preserving failure evidence and writing a result only after all assertions and descriptor closures.".
-spec run(file:filename(), normal | bad_initialization) -> ok.
run(Stage, Mode) ->
    Interface = filename:join(Stage, "interface.etf"),
    {ok, A} = hls_domain_rtl_backend:start_link(filename:join(Stage, "domain0"), Interface), unlink(A),
    {ok, B} = hls_domain_rtl_backend:start_link(filename:join(Stage, "domain1"), Interface), unlink(B),
    StoreA = filename:join(Stage, "incarnation-a.bin"),
    StoreB = filename:join(Stage, "incarnation-b.bin"),
    ok = hls_domain_ids:create(StoreA), ok = hls_domain_ids:create(StoreB),
    OwnerA = owner(a, A, StoreA), OwnerB = owner(b, B, StoreB),
    Leases = lists:append([leases(Backend) || Backend <- [A, B]]),
    try
        Evidence = case Mode of
            normal -> normal(Stage, OwnerA, OwnerB, A, B, StoreA);
            bad_initialization -> bad_initialization(OwnerA)
        end,
        stop(OwnerA), stop(OwnerB), stop(A), stop(B),
        ok = file:write_file(filename:join(Stage, "finished"), <<>>, [exclusive]),
        [ok = hls_fabric:await_closed(Lease, 5000) || Lease <- Leases],
        ok = file:write_file(filename:join(Stage, "result.json"), json:encode(Evidence#{passed => true,
            mode => Mode, descriptor_closure => true, evidence => finite_rtl_and_erts_witness}), [exclusive])
    after stop(OwnerA), stop(OwnerB), stop(A), stop(B) end.

%% A startup callback failure must never produce a published application endpoint.
-spec bad_initialization(pid()) -> map().
bad_initialization(Owner) ->
    {ok, _} = hls_domain:activate(Owner, a),
    #{fault := initialization_failure, actors := Actors} = phase(Owner, a, failed),
    0 = map_size(Actors),
    {error, not_ready} = hls_domain:resolve(Owner, a, counter),
    #{initialization_failure_closed => true}.

%% Each domain runs real counter->relay source topology; expected values are public application observations.
-spec normal(file:filename(), pid(), pid(), pid(), pid(), file:filename()) -> map().
normal(Stage, OwnerA, OwnerB, A, _B, StoreA) ->
    NativeHistory = native_history(Stage),
    {ok, _} = hls_domain:activate(OwnerA, a),
    {ok, _} = hls_domain:activate(OwnerB, b),
    #{handle := OldHandle = {a, OldEpoch}} = phase(OwnerA, a, ready),
    #{handle := BHandle} = phase(OwnerB, b, ready),
    {ok, Old} = hls_domain:resolve(OwnerA, OldHandle, counter),
    {ok, Other} = hls_domain:resolve(OwnerB, BHandle, counter),
    {value, Added} = gen_server:call(Old, {add, 7}),
    {value, ReadBack} = gen_server:call(Old, read),
    {value, 23} = gen_server:call(Other, {add, 23}),
    ok = hold(A, true),
    Pending = gen_server:send_request(Old, read),
    _ = pending(A),
    Ref = monitor(process, Old),
    ok = gen_server:cast(Old, explode),
    SourceReason = receive {'DOWN', Ref, process, Old, Why} -> Why after 5000 -> error(no_source_down) end,
    {hls_actor_failure, _Actor, #{source_code := SourceCode}} = SourceReason,
    true = SourceCode > 0,
    {error, {SourceReason, _}} = gen_server:receive_response(Pending, 5000),
    #{phase := failed} = phase(OwnerA, a, failed),
    {value, 23} = gen_server:call(Other, read),
    {ok, Other} = hls_domain:resolve(OwnerB, BHandle, counter),
    {ok, _} = hls_domain:replace(OwnerA, OldHandle),
    #{handle := NewHandle} = phase(OwnerA, a, ready),
    {ok, New} = hls_domain:resolve(OwnerA, NewHandle, counter),
    true = New =/= Old,
    ok = hold(A, false),
    {value, ResetValue} = gen_server:call(New, read),
    NativeHistory = [Added, ReadBack, ResetValue],
    ok = stale_returns(A, New, OldEpoch),
    ok = stale_input(A, New, OldEpoch),
    {OrderedHandle, _Ordered} = ordered_failure(OwnerA, A, NewHandle, New, Other),
    {LaterHandle, Later} = partial_frame(Stage, OwnerA, A, OrderedHandle),
    {value, 0} = gen_server:call(Later, read),
    %% Deliberately lose one completed management reply, then repeat the same old handle.
    ok = hls_domain_rtl_backend:drop_next_request_reply(A),
    {error, simulated_lost_reply} = hls_domain:replace(OwnerA, LaterHandle),
    #{handle := LostReplyHandle} = phase(OwnerA, a, ready),
    {ok, AfterLostReply} = hls_domain:resolve(OwnerA, LostReplyHandle, counter),
    {value, 31} = gen_server:call(AfterLostReply, {add, 31}),
    Before = maps:get(ready_incarnations, hls_domain_rtl_backend:info(A)),
    {ok, _} = hls_domain:replace(OwnerA, LaterHandle),
    #{handle := LostReplyHandle} = phase(OwnerA, a, ready),
    Before = maps:get(ready_incarnations, hls_domain_rtl_backend:info(A)),
    {value, 31} = gen_server:call(AfterLostReply, read),
    %% Owner loss fences A through management; unrelated B remains live.
    OwnerRef = monitor(process, AfterLostReply),
    stop(OwnerA),
    receive {'DOWN', OwnerRef, process, AfterLostReply, noconnection} -> ok
        after 5000 -> error(owner_loss_not_retired) end,
    await(fun() -> case hls_domain_rtl_backend:status(A) of
        {ok, #{state := #domain_state{phase = failed}}} -> true; _ -> false end end),
    {value, 23} = gen_server:call(Other, read),
    NextOwner = owner(a, A, StoreA),
    try
        #{handle := LostReplyHandle} = phase(NextOwner, a, failed),
        {error, not_ready} = hls_domain:resolve(NextOwner, a, counter),
        {ok, _} = hls_domain:replace(NextOwner, LostReplyHandle),
        #{handle := PeerHandle} = phase(NextOwner, a, ready),
        ok = remote_peer(NextOwner, OwnerB, PeerHandle, Other),
        ok = missing_frontier(A, NextOwner),
        {value, 23} = gen_server:call(Other, read)
    after stop(NextOwner) end,
    #{source_failure => true, native_history => NativeHistory, rtl_history => [Added, ReadBack, ResetValue],
        source_modules => [hls_domain_counter, hls_domain_relay], prior_values => [7, 23], terminal_pending_call => true,
        independent_domain => true, stale_application_acknowledgement => true,
        stale_report => true, stale_ingress => true, partial_application_frame_management => true,
        lost_management_reply_reconciled => true, owner_reattachment => true,
        real_peer_virtual_pid_replacement => true,
        accepted_reply_before_source_down => true, missing_frontier_is_connection_uncertainty => true,
        source_code => SourceCode,
        limits => <<"No injectable native link-credit port; full-network reset is exercised, not a separate stale native-credit proof">>}.

%% Hold only transport delivery after public RTL acceptance; a fault snapshot must not overtake its earlier report.
-spec ordered_failure(pid(), pid(), hls_domain:handle(), pid(), pid()) -> {hls_domain:handle(), pid()}.
ordered_failure(Owner, Backend, Handle, Endpoint, Other) ->
    %% The source's publishing-phase failure branch requires a nonzero committed value.
    {value, 13} = gen_server:call(Endpoint, {add, 13}),
    ok = hls_domain_rtl_backend:delivery(Backend, hold),
    #{delivery_received := Before} = hls_domain_rtl_backend:info(Backend),
    Request = gen_server:send_request(Endpoint, read),
    %% The management frontier proves that both admission and source report reached the transport.
    await(fun() -> maps:get(delivery_frontier, hls_domain_rtl_backend:info(Backend)) >= Before + 2 end),
    Ref = monitor(process, Endpoint),
    ok = gen_server:cast(Endpoint, explode),
    phase(Owner, a, failed),
    #{retirement := #{frontier := Frontier}, delivery_received := Received} = hls_domain_rtl_backend:info(Backend),
    true = Frontier > Received,
    true = is_process_alive(Endpoint),
    timeout = gen_server:wait_response(Request, 0),
    receive {'DOWN', Ref, process, Endpoint, _} -> error(early_orderly_retirement) after 0 -> ok end,
    {value, 23} = gen_server:call(Other, read),
    ok = hls_domain_rtl_backend:delivery(Backend, resume),
    ok = reply_before_down(Request, Ref, Endpoint),
    {ok, _} = hls_domain:replace(Owner, Handle),
    #{handle := NextHandle} = phase(Owner, a, ready),
    {ok, Next} = hls_domain:resolve(Owner, NextHandle, counter),
    {value, 0} = gen_server:call(Next, read),
    {NextHandle, Next}.

%% Inspect the actual mailbox signal order, rather than selectively receiving a reply past an earlier DOWN.
-spec reply_before_down(gen_server:request_id(), reference(), pid()) -> ok.
reply_before_down(Request, Ref, Endpoint) ->
    receive
        {'DOWN', Ref, process, Endpoint, Reason} -> error({down_before_accepted_reply, Reason});
        Message ->
            case gen_server:check_response(Message, Request) of
                {reply, {value, 13}} ->
                    receive {'DOWN', Ref, process, Endpoint, {hls_actor_failure, _, _}} -> ok
                        after 5000 -> error(no_ordered_source_down) end;
                no_reply -> reply_before_down(Request, Ref, Endpoint);
                Other -> error({unexpected_ordered_reply, Other})
            end
    after 5000 -> error(accepted_reply_missing) end.

%% An absent delivery frontier cannot justify orderly death, even when the hardware remains otherwise responsive.
-spec missing_frontier(pid(), pid()) -> ok.
missing_frontier(Backend, Owner) ->
    {ok, Endpoint} = hls_domain:resolve(Owner, a, counter),
    Ref = monitor(process, Endpoint),
    BackendRef = monitor(process, Backend),
    {'EXIT', _} = catch hls_domain_rtl_backend:delivery(Backend, missing_frontier),
    receive {'DOWN', Ref, process, Endpoint, noconnection} -> ok
        after 5000 -> error(missing_frontier_not_uncertain) end,
    receive {'DOWN', BackendRef, process, Backend, _} -> ok
        after 5000 -> error(malformed_management_survived) end,
    ok.

%% A stale epoch with the exact current request ID must not free the new admission slot or satisfy its caller.
-spec stale_returns(pid(), pid(), pos_integer()) -> ok.
stale_returns(Backend, Endpoint, OldEpoch) ->
    ok = hold(Backend, true),
    Request = gen_server:send_request(Endpoint, read),
    {Id, _Entry} = pending(Backend),
    Before = maps:get(ignored, hls_domain_rtl_backend:info(Backend)),
    ok = hls_domain_rtl_backend:control(Backend, 5, split(OldEpoch) ++ [Id, 1]),
    ok = hls_domain_rtl_backend:control(Backend, 6, split(OldEpoch) ++ [Id, 999]),
    await(fun() -> maps:get(ignored, hls_domain_rtl_backend:info(Backend)) >= Before + 2 end),
    true = maps:is_key(Id, maps:get(pending, hls_domain_rtl_backend:info(Backend))),
    timeout = gen_server:wait_response(Request, 0),
    ok = hold(Backend, false),
    {reply, {value, 0}} = gen_server:receive_response(Request, 5000),
    ok.

%% The actual hardware incarnation gate rejects a complete stale source command before actor dispatch.
-spec stale_input(pid(), pid(), pos_integer()) -> ok.
stale_input(Backend, Endpoint, OldEpoch) ->
    Before = maps:get(wire_rejected, hls_domain_rtl_backend:info(Backend)),
    ok = hls_domain_rtl_backend:control(Backend, 2, split(OldEpoch) ++ [3, 16#fffffffe, 999]),
    await(fun() -> maps:get(wire_rejected, hls_domain_rtl_backend:info(Backend)) > Before end),
    {value, 0} = gen_server:call(Endpoint, read),
    ok.

%% A physically partial application packet stays in its own parser while management replaces the domain.
-spec partial_frame(file:filename(), pid(), pid(), hls_domain:handle()) -> {hls_domain:handle(), pid()}.
partial_frame(Stage, Owner, Backend, Handle = {a, OldEpoch}) ->
    [] = maps:keys(maps:get(pending, hls_domain_rtl_backend:info(Backend))),
    {ok, File} = file:open(filename:join(Stage, "domain0_application_tx"), [write, binary, raw]),
    [Lo, Hi] = split(OldEpoch),
    Before = maps:get(wire_rejected, hls_domain_rtl_backend:info(Backend)),
    try
        ok = file:write(File, <<0:32/little, ((2 bsl 24) bor 5):32/little, Lo:32/little>>),
        {ok, _} = hls_domain:replace(Owner, Handle),
        #{handle := NextHandle} = phase(Owner, a, ready),
        {ok, Next} = hls_domain:resolve(Owner, NextHandle, counter),
        ok = file:write(File, <<Hi:32/little, 3:32/little, 16#fffffffd:32/little, 888:32/little>>),
        await(fun() -> maps:get(wire_rejected, hls_domain_rtl_backend:info(Backend)) > Before end),
        {NextHandle, Next}
    after file:close(File) end.

%% The managed-node integration uses the RTL-backed endpoints, not a replacement fake hardware model.
-spec remote_peer(pid(), pid(), hls_domain:handle(), pid()) -> ok.
remote_peer(OwnerA, OwnerB, Handle, Other) ->
    hls_test_nodes:distribution(),
    {ok, _} = application:ensure_all_started(crypto),
    [_Local, Host] = string:split(atom_to_list(node()), "@"),
    Name = list_to_atom("rtl_recovery_" ++ integer_to_list(erlang:unique_integer([positive])) ++ "@" ++ Host),
    Services = [#{name => a, domain => #{owner => OwnerA, id => a}}, #{name => b, domain => #{owner => OwnerB, id => b}}],
    {ok, Node} = hls_node:start_link(Name, #{}, Services, #{}), unlink(Node),
    {Peer, Remote} = hls_test_nodes:start_peer(),
    try
        #{a := #{actors := #{counter := VirtualA}}, b := #{actors := #{counter := VirtualB}}} = hls_node:services(Node),
        {value, 41} = erpc:call(Remote, gen_server, call, [VirtualA, {add, 41}]),
        {value, 23} = erpc:call(Remote, gen_server, call, [VirtualB, read]),
        Watcher = erpc:call(Remote, ?MODULE, watch, [VirtualA, self()]),
        receive {watching, Watcher} -> ok after 5000 -> error(no_peer_monitor) end,
        {ok, _} = hls_domain:replace(OwnerA, Handle),
        phase(OwnerA, a, ready),
        {ok, #{actors := #{counter := Fresh}}} = hls_node:publish_domain(Node, a),
        receive {watched_down, Watcher, Reason} -> true = Reason =/= noconnection
            after 5000 -> error(no_peer_retirement) end,
        true = Fresh =/= VirtualA,
        {value, 0} = erpc:call(Remote, gen_server, call, [Fresh, read]),
        {value, 23} = gen_server:call(Other, read),
        {value, 23} = erpc:call(Remote, gen_server, call, [VirtualB, read]),
        ok
    after peer:stop(Peer), catch hls_node:stop(Node) end.

-doc "Observes the actual virtual PID monitor signal in a separate ERTS VM.".
-spec watch(pid(), pid()) -> pid().
watch(Pid, Parent) -> spawn(fun() ->
    Ref = monitor(process, Pid),
    {value, _} = gen_server:call(Pid, read),
    Parent ! {watching, self()},
    receive {'DOWN', Ref, process, Pid, Reason} -> Parent ! {watched_down, self(), Reason}
        after 5000 -> error(no_peer_down) end
end).

%% Hold is explicit simulator backpressure at the network's public output, never an actor-state mutation.
-spec hold(pid(), boolean()) -> ok.
hold(Backend, Enabled) ->
    Value = case Enabled of true -> 1; false -> 0 end,
    ok = hls_domain_rtl_backend:control(Backend, 3, [Value]),
    await(fun() -> case maps:get(controls, hls_domain_rtl_backend:info(Backend)) of [Value | _] -> true; _ -> false end end).

%% Acknowledged ingress with no result gives a concrete outstanding request for stale-return tests.
-spec pending(pid()) -> {non_neg_integer(), map()}.
pending(Backend) ->
    await(fun() -> lists:any(fun(#{admitted := Accepted}) -> Accepted end,
        maps:values(maps:get(pending, hls_domain_rtl_backend:info(Backend)))) end),
    [Entry] = [{Id, Value} || {Id, Value = #{admitted := true}} <- maps:to_list(maps:get(pending, hls_domain_rtl_backend:info(Backend)))],
    Entry.

%% Reattaching the same durable authority never silently creates a new counter file.
-spec owner(atom(), pid(), file:filename()) -> pid().
owner(Domain, Backend, Store) ->
    {ok, Owner} = hls_domain:start_link(#{Domain => manual}, #{module => hls_domain_rtl_backend,
        endpoints => #{Domain => Backend}, incarnation_file => Store}), unlink(Owner), Owner.

%% Current hardware status, rather than a timer prediction, decides when a phase completed.
-spec phase(pid(), atom(), hls_domain_lifecycle:phase()) -> map().
phase(Owner, Domain, Phase) -> phase(Owner, Domain, Phase, 500).
%% Five seconds is a witness deadline, not a hardware latency guarantee.
-spec phase(pid(), atom(), hls_domain_lifecycle:phase(), non_neg_integer()) -> map().
phase(_Owner, _Domain, Phase, 0) -> error({phase_timeout, Phase});
phase(Owner, Domain, Phase, Left) ->
    case hls_domain:status(Owner, Domain) of
        {ok, #{phase := Phase} = State} -> State;
        _ -> receive after 10 -> phase(Owner, Domain, Phase, Left - 1) end
    end.

%% Bound every asynchronous observation and preserve its failure instead of hanging the driver.
-spec await(fun(() -> boolean())) -> ok.
await(Fun) -> await(Fun, 500).
%% The polling loop runs only while a particular observation remains unresolved.
-spec await(fun(() -> boolean()), non_neg_integer()) -> ok.
await(_Fun, 0) -> error(await_timeout);
await(Fun, Left) -> case Fun() of true -> ok; false -> receive after 10 -> await(Fun, Left - 1) end end.

%% Raw descriptor release is verified after both brokers and their outer simulator close.
-spec leases(pid()) -> [reference()].
leases(Backend) ->
    #{management := Management, application := Application} = hls_domain_rtl_backend:info(Backend),
    [begin #{io := #{lease := Lease}} = hls_fabric:info(Broker), Lease end || Broker <- [Management, Application]].

%% Pack explicit incarnation halves for both real hardware envelopes and negative stale-frame injections.
-spec split(pos_integer()) -> [non_neg_integer()].
split(Incarnation) -> [Incarnation band 16#ffffffff, Incarnation bsr 32].

%% Cleanup accepts actors and owners already terminated by a witnessed fault.
-spec stop(pid()) -> ok.
stop(Pid) -> catch gen_server:stop(Pid), ok.

%% Run the exact same source modules as ordinary ERTS actors, comparing only public values across failure/replacement.
-spec native_history(file:filename()) -> [non_neg_integer()].
native_history(Stage) ->
    Spec = #{actors => #{counter => #{module => hls_domain_counter, mailbox_capacity => 4},
        relay => #{module => hls_domain_relay, mailbox_capacity => 2}},
        routes => #{counter => #{out => {actor, relay}}, relay => #{out => {external, self()}}}},
    {ok, Backend} = hls_domain_erts:start_link(Spec), unlink(Backend),
    Store = filename:join(Stage, "native-incarnation.bin"),
    ok = hls_domain_ids:create(Store),
    {ok, Owner} = hls_domain:start_link(#{native => manual}, #{module => hls_domain_erts,
        endpoints => #{native => Backend}, incarnation_file => Store}), unlink(Owner),
    try
        {ok, _} = hls_domain:activate(Owner, native),
        #{handle := Handle} = phase(Owner, native, ready),
        {ok, Counter} = hls_domain:resolve(Owner, Handle, counter),
        ok = hls_statem:admit_cast(Counter, {add, 1, 7}),
        First = report(1),
        ok = hls_statem:admit_cast(Counter, {read, 2, 0}),
        Second = report(2),
        Ref = monitor(process, Counter),
        _ = catch hls_statem:admit_cast(Counter, {explode, 3, 0}),
        Failure = receive {'DOWN', Ref, process, Counter, Why} -> Why
            after 5000 -> error(native_source_survived_failure) end,
        phase(Owner, native, failed),
        {ok, _} = hls_domain:replace(Owner, Handle),
        phase(Owner, native, ready),
        {ok, Fresh} = hls_domain:resolve(Owner, native, counter),
        ok = hls_statem:admit_cast(Fresh, {read, 4, 0}),
        After = report(4),
        History = [First, Second, After],
        ok = file:write_file(filename:join(Stage, "native-history.etf"),
            term_to_binary(#{values => History, failure => Failure}), [exclusive]),
        History
    after stop(Owner), stop(Backend) end.

%% The native relay publishes the same request-correlated record observed at the RTL external port.
-spec report(non_neg_integer()) -> non_neg_integer().
report(Id) -> receive {'$gen_cast', {value, Id, Value}} -> Value
    after 5000 -> error({native_report_timeout, Id}) end.
