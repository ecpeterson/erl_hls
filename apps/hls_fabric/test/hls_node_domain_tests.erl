-module(hls_node_domain_tests).
-moduledoc "Real second-node witnesses for managed incarnation publication and failure isolation.".
-include_lib("eunit/include/eunit.hrl").

%% Helpers executed by the separate ERTS peer, with its real distribution monitors.
-export([failure_sequence/2, watch/2, stale/1, batch/2, saturate/2, independent_calls/2, interrupted_call/2]).

%% Exercise the actual lifecycle owner, source actors and external PID connection together.
-spec managed_domain_peer_test_() -> term().
managed_domain_peer_test_() -> {timeout, 45, fun() -> with_domains(fun(Owner) ->
    {ok, _} = hls_domain:activate(Owner, a),
    {ok, _} = hls_domain:activate(Owner, b),
    #{handle := OldHandle} = phase(Owner, a, ready),
    phase(Owner, b, ready),
    {ok, LocalA} = hls_domain:resolve(Owner, OldHandle, worker),
    Name = name(),
    Services = [#{name => D, domain => #{owner => Owner, id => D}} || D <- [a, b]],
    {ok, Device} = hls_node:start_link(Name, #{}, Services, #{queue_limit => 4}),
    unlink(Device),
    {Peer, Remote} = hls_test_nodes:start_peer(),
    try
        #{creation := Creation} = hls_node:info(Device),
        #{a := Old = #{actors := #{worker := A}}, b := Other = #{actors := #{worker := B}}} = hls_node:services(Device),
        ?assertEqual({ok, Old}, hls_node:publish_domain(Device, a)),
        ?assertEqual({ok, Other}, hls_node:publish_domain(Device, b)),
        ?assertEqual({error, unknown_managed_domain}, hls_node:publish_domain(Device, missing)),
        ?assertEqual({report, 23}, erpc:call(Remote, ?MODULE, batch, [B, 23])),
        Worker = erpc:call(Remote, ?MODULE, failure_sequence, [A, self()]),
        receive {armed, Worker, {report, 7}} -> ok after 5000 -> error(sequence_not_ready) end,
        Ref = monitor(process, LocalA),
        Worker ! fail,
        NativeReason = receive {'DOWN', Ref, process, LocalA, Reason} -> Reason
            after 5000 -> error(local_actor_not_retired) end,
        receive {failed, Worker, {error, {CallReason, _}}, RemoteReason} ->
            ?assertEqual(NativeReason, CallReason),
            ?assertEqual(NativeReason, RemoteReason),
            ?assertNotEqual(noconnection, RemoteReason)
        after 5000 -> error(no_remote_actor_failure) end,
        phase(Owner, a, failed),
        ?assertEqual({error, not_ready}, hls_node:publish_domain(Device, a)),
        ?assertEqual({report, 23}, erpc:call(Remote, gen_server, call, [B, {read, 0}])),
        ?assertEqual({ok, Other}, hls_node:publish_domain(Device, b)),
        {ok, _} = hls_domain:replace(Owner, OldHandle),
        #{handle := NewHandle} = phase(Owner, a, ready),
        {ok, New = #{domain := NewHandle, actors := #{worker := NewA}}} = hls_node:publish_domain(Device, a),
        ?assertNotEqual(A, NewA),
        ?assertEqual(Creation, maps:get(creation, hls_node:info(Device))),
        ?assertEqual({ok, New}, hls_node:publish_domain(Device, a)),
        ?assertEqual(noproc, erpc:call(Remote, ?MODULE, stale, [A])),
        ?assertEqual({report, 0}, erpc:call(Remote, gen_server, call, [NewA, {read, 0}])),
        ?assertEqual({report, 5}, erpc:call(Remote, ?MODULE, batch, [NewA, 5])),
        ?assertEqual({report, 23}, erpc:call(Remote, gen_server, call, [B, {read, 0}])),
        Watcher = erpc:call(Remote, ?MODULE, watch, [B, self()]),
        receive {watching, Watcher} -> ok after 5000 -> error(no_remote_monitor) end,
        true = erpc:call(Remote, erlang, disconnect_node, [Name]),
        receive {watched_down, Watcher, noconnection} -> ok
            after 5000 -> error(connection_loss_not_distinguished) end,
        await(fun() -> maps:size(maps:get(connections, hls_node:info(Device))) =:= 0 end),
        ?assertEqual({report, 23}, erpc:call(Remote, gen_server, call, [B, {read, 0}])),
        ?assertEqual(New, maps:get(a, hls_node:services(Device)))
    after peer:stop(Peer), catch hls_node:stop(Device) end
end) end}.

%% Production proxies and a real ERTS peer exercise reconnection; the retained actor state here is a host fixture, not RTL.
-spec disconnected_incarnation_peer_test_() -> term().
disconnected_incarnation_peer_test_() -> {timeout, 30, fun() -> with_domains(fun(NativeOwner) ->
    {ok, _} = hls_domain:activate(NativeOwner, b),
    phase(NativeOwner, b, ready),
    Store = spawn(fun() -> retained_actor(0, 0) end),
    Backend = spawn(fun() -> endpoint_backend(Store) end),
    {ok, Endpoint} = hls_domain_endpoint:start(Backend, worker, 1, #{call => 4, cast => 4}),
    Snapshot = #{phase => ready, handle => {a, 1}, actors => #{worker => Endpoint}},
    Owner = spawn(fun() -> mutable_status_owner(Snapshot) end),
    Name = name(),
    Services = [#{name => a, domain => #{owner => Owner, id => a}},
        #{name => b, domain => #{owner => NativeOwner, id => b}}],
    {ok, Device} = hls_node:start_link(Name, #{}, Services, #{queue_limit => 4}), unlink(Device),
    {Peer, Remote} = hls_test_nodes:start_peer(),
    try
        #{a := Handle = #{actors := #{worker := A}}, b := #{actors := #{worker := B}}} = hls_node:services(Device),
        Observer = erpc:call(Remote, ?MODULE, interrupted_call, [A, self()]),
        receive {uncertain_ready, Observer, {report, 5}} -> ok
            after 5000 -> error(no_uncertain_call) end,
        Ref = monitor(process, Endpoint),
        exit(Backend, kill),
        receive {'DOWN', Ref, process, Endpoint, noconnection} -> ok
            after 5000 -> error(no_proxy_disconnect) end,
        receive {uncertain, Observer, {error, {noconnection, _}}, noconnection} -> ok
            after 5000 -> error(no_remote_disconnect) end,
        ?assertEqual(noconnection, erpc:call(Remote, ?MODULE, stale, [A])),
        ?assertEqual({report, 0}, erpc:call(Remote, gen_server, call, [B, {read, 0}])),
        %% A peer connecting after endpoint death must still see disconnection, not a fabricated actor death.
        true = erpc:call(Remote, erlang, disconnect_node, [Name]),
        await(fun() -> map_size(maps:get(connections, hls_node:info(Device))) =:= 0 end),
        ?assertEqual(noconnection, erpc:call(Remote, ?MODULE, stale, [A])),
        failed_reattach_candidate(Device, Owner, Snapshot, Store, Remote, A, Handle),
        FreshBackend = spawn(fun() -> endpoint_backend(Store) end),
        {ok, FreshEndpoint} = hls_domain_endpoint:start(FreshBackend, worker, 1, #{call => 4, cast => 4}),
        try
            ok = gen_server:call(Owner, {snapshot, Snapshot#{actors := #{worker => FreshEndpoint}}}),
            ?assertEqual({error, changed_incarnation_endpoints}, hls_node:publish_domain(Device, a)),
            ?assertEqual({ok, Handle}, hls_node:reattach_domain(Device, a)),
            ?assertEqual({ok, Handle}, hls_node:reattach_domain(Device, a)),
            ?assertEqual(Handle, maps:get(a, hls_node:services(Device))),
            ?assertEqual({report, 5}, erpc:call(Remote, gen_server, call, [A, {read, 0}])),
            ?assertEqual({5, 1}, gen_server:call(Store, inspect)),
            FreshObserver = erpc:call(Remote, ?MODULE, watch, [A, self()]),
            receive {watching, FreshObserver} -> ok after 5000 -> error(no_fresh_monitor) end,
            Observer ! check_old_monitor,
            receive {old_monitor_stayed_terminal, Observer} -> ok
                after 5000 -> error(old_monitor_revived) end,
            exit(FreshBackend, kill),
            receive {watched_down, FreshObserver, noconnection} -> ok
                after 5000 -> error(fresh_monitor_not_active) end
        after exit(FreshBackend, kill), stop(FreshEndpoint) end
    after
        peer:stop(Peer), catch hls_node:stop(Device),
        [exit(P, kill) || P <- [Owner, Backend, Store]], stop(Endpoint)
    end
end) end}.

%% A same-shaped endpoint cannot resurrect an actor which terminated for an application reason.
-spec terminal_incarnation_reattach_rejected_test() -> ok.
terminal_incarnation_reattach_rejected_test() ->
    OldEndpoint = spawn(fun idle/0),
    Ref = monitor(process, OldEndpoint), exit(OldEndpoint, kill),
    receive {'DOWN', Ref, process, OldEndpoint, killed} -> ok after 1000 -> error(old_endpoint_alive) end,
    Fresh = spawn(fun idle/0),
    Owner = spawn(fun() -> status_owner(#{phase => ready, handle => {a, 1}, actors => #{worker => Fresh}}) end),
    Service = #{name => a, domain => #{owner => Owner, id => a}},
    Old = [#{identity => worker, endpoint => OldEndpoint, endpoint_status => {down, source_failure}}],
    try ?assertEqual({error, old_endpoints_not_disconnected},
        hls_node_domain:reattachment(Service, Old, #{domain => {a, 1}}))
    after exit(Owner, kill), exit(Fresh, kill) end.

%% A saturated application connection cannot consume unbounded endpoint requests or block local management.
-spec bounded_pending_peer_test_() -> term().
bounded_pending_peer_test_() -> {timeout, 30, fun() -> with_domains(fun(Owner) ->
    {ok, _} = hls_domain:activate(Owner, a),
    #{handle := Handle} = phase(Owner, a, ready),
    Service = #{name => a, domain => #{owner => Owner, id => a}},
    {ok, Device} = hls_node:start_link(name(), #{}, [Service], #{queue_limit => 2}), unlink(Device),
    {Peer, Remote} = hls_test_nodes:start_peer(),
    try
        #{a := #{actors := #{worker := A}}} = hls_node:services(Device),
        Worker = erpc:call(Remote, ?MODULE, saturate, [A, self()]),
        receive {submitted, Worker} -> ok after 5000 -> error(no_pending_requests) end,
        await(fun() -> case maps:keys(maps:get(connections, hls_node:info(Device))) of
            [Connection] -> maps:get(domain_pending, gen_server:call(Connection, info)) =:= 2;
            _ -> false end end),
        ?assertMatch({ok, #{phase := ready}}, hls_domain:status(Owner, a)),
        {ok, _} = hls_domain:replace(Owner, Handle),
        phase(Owner, a, ready),
        {ok, #{actors := #{worker := NewA}}} = hls_node:publish_domain(Device, a),
        receive {drained, Worker, Results} ->
            ?assertEqual(5, length(Results)),
            ?assert(lists:all(fun(Result) -> case Result of {error, _} -> true; {reply, {error, busy}} -> true; _ -> false end end, Results))
        after 5000 -> error(pending_calls_survived_retirement) end,
        ?assertEqual({report, 0}, erpc:call(Remote, gen_server, call, [NewA, {read, 0}]))
    after peer:stop(Peer), catch hls_node:stop(Device) end
end) end}.

%% Unfinished calls consume their actor's slots, never another actor's admission or a release cast.
-spec independent_completion_peer_test_() -> term().
independent_completion_peer_test_() -> {timeout, 30, fun() -> with_domains(fun(Owner) ->
    [{ok, _} = hls_domain:activate(Owner, D) || D <- [a, b]],
    [phase(Owner, D, ready) || D <- [a, b]],
    Services = [#{name => D, domain => #{owner => Owner, id => D}} || D <- [a, b]],
    {ok, Device} = hls_node:start_link(name(), #{}, Services, #{queue_limit => 2}), unlink(Device),
    {Peer, Remote} = hls_test_nodes:start_peer(),
    try
        #{a := #{actors := #{worker := A}}, b := #{actors := #{worker := B}}} = hls_node:services(Device),
        ?assertEqual({{report, 0}, [{reply, {report, 7}}, {reply, {report, 11}}], {report, 18}},
            erpc:call(Remote, ?MODULE, independent_calls, [A, B], 10000))
    after peer:stop(Peer), catch hls_node:stop(Device) end
end) end}.

%% A newer status cannot authorize reusing storage whose old endpoint is still alive.
-spec live_old_endpoint_rejected_test() -> ok.
live_old_endpoint_rejected_test() ->
    Endpoint = spawn(fun idle/0),
    Fresh = spawn(fun idle/0),
    Snapshot = #{phase => ready, handle => {a, 2}, actors => #{worker => Fresh}},
    Owner = spawn(fun() -> status_owner(Snapshot) end),
    Service = #{name => a, domain => #{owner => Owner, id => a}},
    Old = [#{identity => worker, endpoint => Endpoint}],
    try
        ?assertEqual({error, old_endpoints_alive}, hls_node_domain:replacement(Service, Old, #{domain => {a, 1}})),
        ?assertEqual({error, changed_incarnation_endpoints}, hls_node_domain:replacement(Service, Old, #{domain => {a, 2}})),
        ?assertEqual({error, stale_incarnation}, hls_node_domain:replacement(Service, Old, #{domain => {a, 3}}))
    after [exit(P, kill) || P <- [Owner, Endpoint, Fresh]] end,
    ok.

%% Enrollment consults the owner's real unbound state rather than fabricating ready endpoints.
-spec unready_enrollment_rejected_test_() -> term().
unready_enrollment_rejected_test_() -> {timeout, 15, fun() -> with_domains(fun(Owner) ->
    Service = #{name => a, domain => #{owner => Owner, id => a}},
    ?assertEqual({error, not_ready}, hls_node_domain:snapshot(Service)),
    Parent = self(),
    {Starter, Ref} = spawn_monitor(fun() ->
        process_flag(trap_exit, true),
        Parent ! {self(), hls_node:start_link(name(), #{}, [Service], #{})}
    end),
    receive {Starter, Result} -> ?assertMatch({error, _}, Result)
        after 5000 -> error(no_start_result) end,
    receive {'DOWN', Ref, process, Starter, normal} -> ok
        after 5000 -> error(start_not_rejected) end,
    ?assertMatch({ok, #{phase := unbound}}, hls_domain:status(Owner, a))
end) end}.

-doc "Completes earlier work, retains one call, then induces source failure from the same remote sender.".
-spec failure_sequence(pid(), pid()) -> pid().
failure_sequence(Pid, Parent) -> spawn(fun() ->
    Ref = monitor(process, Pid),
    ?assertEqual({report, 7}, batch(Pid, 7)),
    Hold = gen_server:send_request(Pid, {wait, 11}),
    ?assertEqual({report, 7}, gen_server:call(Pid, {read, 0})),
    Parent ! {armed, self(), {report, 7}},
    receive fail -> ok after 5000 -> error(no_failure_command) end,
    gen_server:cast(Pid, {explode, 0}),
    Reply = gen_server:receive_response(Hold, 5000),
    Reason = receive {'DOWN', Ref, process, Pid, Why} -> Why
        after 5000 -> error(no_remote_down) end,
    Parent ! {failed, self(), Reply, Reason}
end).

-doc "Installs a real peer-side monitor and reports the delivered terminal reason.".
-spec watch(pid(), pid()) -> pid().
watch(Pid, Parent) -> spawn(fun() ->
    Ref = monitor(process, Pid),
    %% A round trip ensures monitor setup precedes a requested disconnect.
    {report, _} = gen_server:call(Pid, {read, 0}),
    Parent ! {watching, self()},
    receive {'DOWN', Ref, process, Pid, Reason} -> Parent ! {watched_down, self(), Reason}
        after 5000 -> error(no_watched_down) end
end).

-doc "Checks that an old external PID is absent; sending a stale cast must not retarget its successor.".
-spec stale(pid()) -> term().
stale(Pid) ->
    Ref = monitor(process, Pid),
    gen_server:cast(Pid, {wait, 99}),
    receive {'DOWN', Ref, process, Pid, Reason} -> Reason
        after 5000 -> error(stale_endpoint_survived) end.

-doc "Runs one retained-call/release exchange from one sender, preserving distribution order.".
-spec batch(pid(), non_neg_integer()) -> term().
batch(Pid, Value) ->
    Request = gen_server:send_request(Pid, {wait, Value}),
    gen_server:cast(Pid, {release, 0}),
    {reply, Reply} = gen_server:receive_response(Request, 5000),
    Reply.

-doc "Submits more retained calls than the adapter bound; retirement must reject every old call without replay.".
-spec saturate(pid(), pid()) -> pid().
saturate(Pid, Parent) -> spawn(fun() ->
    Requests = [gen_server:send_request(Pid, {wait, I}) || I <- lists:seq(1, 5)],
    Parent ! {submitted, self()},
    Results = [gen_server:receive_response(Request, 5000) || Request <- Requests],
    Parent ! {drained, self(), Results}
end).

-doc "Retains both A callers, checks excess rejection and independent B progress, then releases A through the same peer.".
-spec independent_calls(pid(), pid()) -> tuple().
independent_calls(A, B) ->
    Requests = [gen_server:send_request(A, {wait, N}) || N <- [7, 11]],
    ?assertEqual({error, busy}, gen_server:call(A, {read, 0}, 3000)),
    Other = gen_server:call(B, {read, 0}, 3000),
    %% The acknowledgement belongs to cast admission, not either occupied retained-call slot.
    ok = gen_server:call(A, {'$hls_domain_cast', {release, 0}}, 3000),
    Results = [gen_server:receive_response(R, 3000) || R <- Requests],
    {Other, Results, gen_server:call(A, {read, 0}, 3000)}.

%% Each source domain is independently controlled; the finite callback fixture belongs to this repository.
-spec with_domains(fun((pid()) -> term())) -> term().
with_domains(Fun) ->
    hls_test_nodes:distribution(),
    {ok, _} = application:ensure_all_started(crypto),
    Store = filename:join("/tmp", "hls-node-domain-" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = hls_domain_ids:create(Store),
    Spec = #{actors => #{worker => #{module => hls_statem_reply_fixture, mailbox_capacity => 4}},
        routes => #{worker => #{reply => {external, self()}}}},
    {ok, A} = hls_domain_erts:start_link(Spec), unlink(A),
    {ok, B} = hls_domain_erts:start_link(Spec), unlink(B),
    {ok, Owner} = hls_domain:start_link(#{a => manual, b => manual},
        #{module => hls_domain_erts, endpoints => #{a => A, b => B}, incarnation_file => Store}), unlink(Owner),
    try Fun(Owner) after stop(Owner), stop(A), stop(B), file:delete(Store) end.

%% Bounded status polling observes actual lifecycle work, never substitutes a guessed completion.
-spec phase(pid(), atom(), atom()) -> map().
phase(Owner, Domain, Phase) -> phase(Owner, Domain, Phase, 200).
%% Poll no more than the finite test deadline.
-spec phase(pid(), atom(), atom(), non_neg_integer()) -> map().
phase(_Owner, _Domain, Phase, 0) -> error({phase_timeout, Phase});
phase(Owner, Domain, Phase, Left) ->
    case hls_domain:status(Owner, Domain) of
        {ok, #{phase := Phase} = Status} -> Status;
        _ -> receive after 5 -> phase(Owner, Domain, Phase, Left - 1) end
    end.

%% Test-only wait for independent asynchronous distribution teardown.
-spec await(fun(() -> boolean())) -> ok.
await(Fun) -> await(Fun, 200).
%% Stop a failed asynchronous observation rather than leaving the suite waiting.
-spec await(fun(() -> boolean()), non_neg_integer()) -> ok.
await(_Fun, 0) -> error(await_timeout);
await(Fun, Left) -> case Fun() of true -> ok; false -> receive after 5 -> await(Fun, Left - 1) end end.

%% Use a unique EPMD name on the current host without depending on a fixed port.
-spec name() -> node().
name() ->
    [_Local, Host] = string:split(atom_to_list(node()), "@"),
    list_to_atom("domain_fpga_" ++ integer_to_list(erlang:unique_integer([positive])) ++ "@" ++ Host).

%% Minimal intentionally lying owner tests a rejected publication precondition, not lifecycle behavior.
-spec status_owner(map()) -> no_return().
status_owner(Snapshot) ->
    receive {'$gen_call', From, {status, a}} -> gen_server:reply(From, {ok, Snapshot}), status_owner(Snapshot) end.

%% Passive fixture endpoints establish actual liveness for the negative publication test.
-spec idle() -> no_return().
idle() -> receive stop -> idle() end.

%% Cleanup must also accept endpoints already retired by the tested source fault.
-spec stop(pid()) -> ok.
stop(Pid) -> catch gen_server:stop(Pid), ok.


-doc "Observes accepted but unfinished work, then checks that its old monitor stays terminal after reconnect.".
-spec interrupted_call(pid(), pid()) -> pid().
interrupted_call(Pid, Parent) -> spawn(fun() ->
    Ref = monitor(process, Pid),
    Request = gen_server:send_request(Pid, {add_wait, 5}),
    Read = gen_server:call(Pid, {read, 0}),
    Parent ! {uncertain_ready, self(), Read},
    Result = gen_server:receive_response(Request, 5000),
    Reason = receive {'DOWN', Ref, process, Pid, Why} -> Why
        after 5000 -> error(missing_old_down) end,
    Parent ! {uncertain, self(), Result, Reason},
    receive check_old_monitor -> ok after 5000 -> error(no_old_monitor_check) end,
    receive {'DOWN', Ref, process, Pid, _} -> error(duplicate_old_monitor_down)
        after 50 -> Parent ! {old_monitor_stayed_terminal, self()} end
end).

%% This fake device survives the host backend and records admissions, making replay visible to the witness.
-spec retained_actor(non_neg_integer(), non_neg_integer()) -> no_return().
retained_actor(Value, Count) ->
    receive
        {execute, Backend, Endpoint, Ref, call, {add_wait, Delta}} ->
            Endpoint ! {domain_admitted, Backend, Ref},
            retained_actor(Value + Delta, Count + 1);
        {execute, Backend, Endpoint, Ref, call, {read, 0}} ->
            Endpoint ! {domain_admitted, Backend, Ref},
            Endpoint ! {domain_result, Backend, Ref, {report, Value}},
            retained_actor(Value, Count);
        {'$gen_call', From, inspect} ->
            gen_server:reply(From, {Value, Count}), retained_actor(Value, Count)
    end.

%% The real endpoint monitors this disposable host adapter; application state lives independently in the fixture.
-spec endpoint_backend(pid()) -> no_return().
endpoint_backend(Store) ->
    receive {'$gen_cast', {application, Endpoint, Ref, worker, 1, Mode, Message}} ->
        Store ! {execute, self(), Endpoint, Ref, Mode, Message}, endpoint_backend(Store)
    end.

%% A fixture owner supplies authoritative ready snapshots; real owner/backend reconciliation is covered separately.
-spec mutable_status_owner(map()) -> no_return().
mutable_status_owner(Snapshot) ->
    receive
        {'$gen_call', From, {status, a}} ->
            gen_server:reply(From, {ok, Snapshot}), mutable_status_owner(Snapshot);
        {'$gen_call', From, {snapshot, Fresh}} ->
            gen_server:reply(From, ok), mutable_status_owner(Fresh)
    end.


%% Suspend the peer at publication so a fresh proxy is already gone before its monitor is installed.
-spec failed_reattach_candidate(pid(), pid(), map(), pid(), node(), pid(), map()) -> ok.
failed_reattach_candidate(Device, Owner, Snapshot, Store, Remote, Actor, Handle) ->
    Backend = spawn(fun() -> endpoint_backend(Store) end),
    {ok, Endpoint} = hls_domain_endpoint:start(Backend, worker, 1, #{call => 4, cast => 4}),
    Ref = monitor(process, Endpoint),
    ok = gen_server:call(Owner, {snapshot, Snapshot#{actors := #{worker => Endpoint}}}),
    [Connection] = maps:keys(maps:get(connections, hls_node:info(Device))),
    #{name := Name} = hls_node:info(Device),
    Manager = hls_node:local_manager(Name),
    ok = sys:suspend(Connection),
    Parent = self(),
    Publisher = spawn(fun() -> Parent ! {candidate_published, self(), hls_node:reattach_domain(Device, a)} end),
    try
        %% This is scheduling control for the host witness, not a device-state observation.
        await(fun() -> maps:get(publication, sys:get_state(Manager)) =/= none end),
        exit(Backend, kill),
        receive {'DOWN', Ref, process, Endpoint, noconnection} -> ok
            after 1000 -> error(candidate_survived) end
    after sys:resume(Connection) end,
    try
        receive {candidate_published, Publisher, Result} -> ?assertEqual({ok, Handle}, Result)
            after 5000 -> error(candidate_publication_hung) end,
        ?assertEqual(noconnection, erpc:call(Remote, ?MODULE, stale, [Actor]))
    after exit(Publisher, kill), exit(Backend, kill), stop(Endpoint) end.
