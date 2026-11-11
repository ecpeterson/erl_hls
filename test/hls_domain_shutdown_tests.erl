-module(hls_domain_shutdown_tests).
-moduledoc "Finite native and management-model witnesses for explicit stop and supervisor-owned domain lifetimes.".
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Stopping retires real actors without allocating or initializing a successor; stale stops cannot affect one.
-spec stop_retains_identity_until_explicit_replacement_test() -> ok.
stop_retains_identity_until_explicit_replacement_test() ->
    native(fun(Owner, A, _B, Store) ->
        {ok, _} = hls_domain:activate(Owner, a),
        #{handle := Old} = phase(Owner, a, ready),
        {ok, Actor} = hls_domain:resolve(Owner, Old, actor),
        ok = hls_statem:admit_cast(Actor, {add, 17}),
        ?assertEqual({readout, 17}, hls_statem:call(Actor, {get, 0})),
        {ok, Before} = hls_domain_erts:status(A),
        {ok, Counter} = file:read_file(Store),
        Monitor = monitor(process, Actor),
        {ok, _} = hls_domain:stop(Owner, Old),
        #{handle := Old, actors := Actors} = phase(Owner, a, stopped),
        ?assertEqual(#{}, Actors),
        receive {'DOWN', Monitor, process, Actor, shutdown} -> ok after 1000 -> error(actor_not_retired) end,
        ?assertEqual({error, not_ready}, hls_domain:resolve(Owner, Old, actor)),
        ?assertMatch({ok, #{phase := stopped, handle := Old}}, hls_domain:stop(Owner, Old)),
        ?assertEqual({ok, Counter}, file:read_file(Store)),
        {ok, Stopped} = hls_domain_erts:status(A),
        ?assertEqual(maps:get(reset_count, Before), maps:get(reset_count, Stopped)),
        {ok, _} = hls_domain:replace(Owner, Old),
        #{handle := New} = phase(Owner, a, ready),
        ?assertNotEqual(Old, New),
        ?assertEqual({error, stale}, hls_domain:stop(Owner, Old)),
        {ok, NewActor} = hls_domain:resolve(Owner, New, actor),
        ?assertNotEqual(Actor, NewActor),
        ?assertEqual({readout, 0}, hls_statem:call(NewActor, {get, 0}))
    end).

%% An explicitly owned lifetime survives a killed host child as shutdown intent, not as a healthy reattachment.
-spec killed_supervised_child_is_retired_before_new_child_test() -> ok.
killed_supervised_child_is_retired_before_new_child_test() ->
    native(fun(Owner, _A, _B, _Store) ->
        {ok, _} = hls_domain:activate(Owner, b),
        #{handle := Other} = phase(Owner, b, ready),
        {ok, Independent} = hls_domain:resolve(Owner, Other, actor),
        {ok, Child} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}),
        unlink(Child),
        #{handle := Old} = instance_ready(Child),
        ?assertEqual({error, supervised}, hls_domain:activate(Owner, a)),
        ?assertEqual({error, supervised}, hls_domain:replace(Owner, Old)),
        {ok, Actor} = hls_domain_instance:resolve(Child, actor),
        ok = hls_statem:admit_cast(Actor, {add, 9}),
        ChildMonitor = monitor(process, Child),
        exit(Child, kill),
        receive {'DOWN', ChildMonitor, process, Child, killed} -> ok after 1000 -> error(child_survived) end,
        %% Start immediately: the owner's old DOWN may still be queued behind this new claim.
        {ok, NewChild} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}),
        unlink(NewChild),
        try
            #{handle := New} = instance_ready(NewChild),
            ?assertNotEqual(Old, New),
            ?assertNot(is_process_alive(Actor)),
            {ok, NewActor} = hls_domain_instance:resolve(NewChild, actor),
            ?assertEqual({readout, 0}, hls_statem:call(NewActor, {get, 0})),
            ?assertEqual({ok, Independent}, hls_domain:resolve(Owner, Other, actor)),
            ok = gen_server:stop(NewChild, shutdown, 2000),
            ?assertMatch(#{phase := stopped, handle := New}, phase(Owner, a, stopped))
        after stop(NewChild) end
    end).

%% A withheld physical fence cannot be promoted to stop completion by local child death or a new start.
-spec missing_fence_blocks_new_supervised_incarnation_test() -> ok.
missing_fence_blocks_new_supervised_incarnation_test() ->
    modeled(fun(Owner, Backend, Store) ->
        {ok, Child} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}),
        unlink(Child),
        #{handle := Old} = instance_ready(Child),
        ok = hls_domain_async_fixture:pause(Backend, fence),
        exit(Child, kill),
        phase(Owner, a, closing),
        ?assertEqual({error, supervised}, hls_domain:replace(Owner, Old)),
        {ok, Counter} = file:read_file(Store),
        {ok, WaitingChild} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}),
        unlink(WaitingChild),
        try
            ?assertEqual({error, not_ready}, hls_domain_instance:resolve(WaitingChild, actor)),
            ?assertEqual({ok, Counter}, file:read_file(Store)),
            ?assertMatch({ok, #{phase := closing, handle := Old}}, hls_domain:status(Owner, a)),
            ok = hls_domain_async_fixture:advance(Backend),
            #{handle := New} = instance_ready(WaitingChild),
            ?assertNotEqual(Old, New)
        after stop(WaitingChild) end
    end).

%% Losing a child before startup completion retains the exact admitted target until its retirement is confirmed.
-spec killed_child_during_initialization_cannot_leak_target_test() -> ok.
killed_child_during_initialization_cannot_leak_target_test() ->
    modeled(fun(Owner, Backend, Store) ->
        ok = hls_domain_async_fixture:pause(Backend, initialize),
        {ok, Child} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}),
        unlink(Child),
        #{handle := Initial, target := Target} = phase(Owner, a, initializing),
        ?assertEqual({a, Target}, Initial),
        exit(Child, kill),
        {ok, NewChild} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}),
        unlink(NewChild),
        try
            ?assertEqual({error, not_ready}, hls_domain_instance:resolve(NewChild, actor)),
            ?assertEqual({ok, <<Target:64>>}, file:read_file(Store)),
            ok = hls_domain_async_fixture:advance(Backend),
            #{handle := New} = instance_ready(NewChild),
            ?assertNotEqual(Initial, New)
        after stop(NewChild) end
    end).

%% A rejected claim must not reserve supervision or accidentally acquire a future incarnation.
-spec busy_claim_rolls_back_ownership_test() -> ok.
busy_claim_rolls_back_ownership_test() ->
    modeled(fun(Owner, Backend, _Store) ->
        ok = hls_domain_async_fixture:hold(Backend, status),
        First = gen_server:send_request(Owner, {status, a}),
        receive {fixture_held, Backend, status, Owner} -> ok after 1000 -> error(no_held_status) end,
        Waiting = [gen_server:send_request(Owner, {status, a}) || _ <- lists:seq(1, 8)],
        ?assertEqual({ok, automatic}, hls_domain:policy(Owner, a)),
        ?assertEqual({error, busy}, hls_domain:supervise(Owner, a)),
        ok = hls_domain_async_fixture:release(Backend),
        lists:foreach(fun(Request) -> ?assertMatch({reply, {ok, _}}, gen_server:receive_response(Request, 1000)) end, [First | Waiting]),
        {ok, Child} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}),
        unlink(Child),
        try instance_ready(Child) after stop(Child) end
    end).

%% A queued but unsubmitted startup is withdrawn when its explicit lifetime owner dies.
-spec death_before_queued_startup_does_not_create_orphan_test() -> ok.
death_before_queued_startup_does_not_create_orphan_test() ->
    modeled(fun(Owner, Backend, Store) ->
        Parent = self(),
        Child = spawn(fun() ->
            {ok, _} = hls_domain:supervise(Owner, a),
            Parent ! {claimed, self()},
            receive submit -> ok end,
            _ = gen_server:send_request(Owner, {activate, a}),
            {ok, automatic} = hls_domain:policy(Owner, a),
            Parent ! {startup_queued, self()},
            receive never -> ok end
        end),
        receive {claimed, Child} -> ok after 1000 -> error(claim_not_seen) end,
        ok = hls_domain_async_fixture:hold(Backend, status),
        Status = gen_server:send_request(Owner, {status, a}),
        receive {fixture_held, Backend, status, Owner} -> ok after 1000 -> error(no_held_status) end,
        Child ! submit,
        receive {startup_queued, Child} -> ok after 1000 -> error(startup_not_queued) end,
        Ref = monitor(process, Child), exit(Child, kill),
        receive {'DOWN', Ref, process, Child, killed} -> ok after 1000 -> error(child_survived) end,
        ok = hls_domain_async_fixture:release(Backend),
        ?assertMatch({reply, {ok, _}}, gen_server:receive_response(Status, 1000)),
        ?assertMatch(#{phase := unbound}, phase(Owner, a, unbound)),
        ?assertEqual({ok, <<0:64>>}, file:read_file(Store)),
        {ok, Replacement} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}),
        unlink(Replacement),
        try
            ?assertMatch(#{handle := {a, 1}}, instance_ready(Replacement))
        after stop(Replacement) end
    end).

%% A definitive backend rejection releases an unused startup target; transport uncertainty does not.
-spec rejected_startup_does_not_block_later_claim_test() -> ok.
rejected_startup_does_not_block_later_claim_test() ->
    modeled(fun(Owner, Backend, Store) ->
        ok = hls_domain_async_fixture:reject(Backend),
        OldTrap = process_flag(trap_exit, true),
        try
            {ok, Child} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}),
            receive {'EXIT', Child, {incarnation_rejected, {rejected, invalid}}} -> ok
            after 1000 -> error(rejected_child_survived) end,
            ?assertEqual({ok, <<1:64>>}, file:read_file(Store)),
            {ok, Next} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}),
            unlink(Next),
            try ?assertMatch(#{handle := {a, 2}}, instance_ready(Next)) after stop(Next) end
        after process_flag(trap_exit, OldTrap) end
    end).

%% Stop at the maximum incarnation needs no fresh allocation, unlike replacement.
-spec stop_with_exhausted_identity_space_test() -> ok.
stop_with_exhausted_identity_space_test() ->
    native(fun(Owner, A, B, Store) ->
        {ok, _} = hls_domain:activate(Owner, a),
        #{handle := Old} = phase(Owner, a, ready),
        stop(Owner),
        ok = file:write_file(Store, <<((1 bsl 64) - 1):64>>),
        {ok, NextOwner} = hls_domain:start_link(#{a => automatic, b => automatic}, backend(hls_domain_erts, #{a => A, b => B}, Store)),
        unlink(NextOwner),
        try
            {ok, _} = hls_domain:stop(NextOwner, Old),
            phase(NextOwner, a, stopped),
            ?assertEqual({error, incarnation_exhausted}, hls_domain:replace(NextOwner, Old))
        after stop(NextOwner) end
    end).

%% Reconnection to the same non-ready identity permits shutdown reconciliation without publishing actors or restarting it.
-spec nonready_reattachment_reconciles_stop_test() -> ok.
nonready_reattachment_reconciles_stop_test() ->
    lists:foreach(fun(Wanted) -> modeled(fun(Owner, Backend, Store) ->
        {ok, _} = hls_domain:activate(Owner, a),
        #{handle := Handle} = phase(Owner, a, ready),
        case Wanted of closing -> ok = hls_domain_async_fixture:pause(Backend, fence); stopped -> ok end,
        {ok, _} = hls_domain:stop(Owner, Handle),
        phase(Owner, a, Wanted),
        {ok, Evidence} = hls_domain_async_fixture:status(Backend),
        {ok, Counter} = file:read_file(Store),
        Ref = monitor(process, Backend), exit(Backend, kill),
        receive {'DOWN', Ref, process, Backend, killed} -> ok after 1000 -> error(adapter_survived) end,
        {ok, NewBackend} = hls_domain_async_fixture:start_link(self(), Evidence),
        unlink(NewBackend),
        try
            {ok, Reattached} = hls_domain:reattach(Owner, Handle, NewBackend),
            ?assertMatch(#{phase := Wanted, handle := Handle}, Reattached),
            ?assertEqual(#{}, maps:get(actors, Reattached)),
            ?assertEqual({error, not_ready}, hls_domain:resolve(Owner, Handle, actor)),
            ?assertEqual({ok, Counter}, file:read_file(Store)),
            case Wanted of closing -> ok = hls_domain_async_fixture:advance(NewBackend); stopped -> ok end,
            ?assertMatch(#{phase := stopped, handle := Handle}, phase(Owner, a, stopped)),
            ?assertEqual({ok, Counter}, file:read_file(Store))
        after stop(NewBackend) end
    end) end, [closing, stopped]).

%% A disconnected supervised child preserves its lifetime until explicit shutdown, then reconciles a lost stop response before replacement.
-spec supervised_disconnect_then_stop_reattach_test() -> ok.
supervised_disconnect_then_stop_reattach_test() ->
    Store = store(),
    Proxy = spawn(fun() -> receive finish -> ok end end),
    Initial = #{state => hls_domain_lifecycle:new(), actors => #{actor => Proxy}, fault_reason => none},
    {ok, Backend} = hls_domain_async_fixture:start_link(self(), Initial), unlink(Backend),
    {ok, Owner} = hls_domain:start_link(#{a => automatic}, backend(hls_domain_async_fixture, #{a => Backend}, Store)), unlink(Owner),
    {ok, Child} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}), unlink(Child),
    try
        #{handle := Handle} = instance_ready(Child),
        {ok, Counter} = file:read_file(Store),
        {ok, ReadyEvidence} = hls_domain_async_fixture:status(Backend),
        Ref = monitor(process, Backend), exit(Backend, kill),
        receive {'DOWN', Ref, process, Backend, killed} -> ok after 1000 -> error(adapter_survived) end,
        exit(Proxy, noconnection),
        until(fun() -> case hls_domain_instance:status(Child) of {error, noconnection} -> {ok, unavailable}; _ -> wait end end, 200),
        ?assert(is_process_alive(Child)),
        ?assertEqual({ok, Counter}, file:read_file(Store)),
        ?assertMatch({error, _}, hls_domain:status(Owner, a)),
        ConnectedProxy = spawn(fun() -> receive finish -> ok end end),
        {ok, ConnectedBackend} = hls_domain_async_fixture:start_link(self(), ReadyEvidence#{actors := #{actor => ConnectedProxy}}), unlink(ConnectedBackend),
        try
        ?assertMatch({ok, #{phase := ready, handle := Handle}}, hls_domain:reattach(Owner, Handle, ConnectedBackend)),
        ?assertMatch(#{handle := Handle}, instance_ready(Child)),
        ?assertEqual({ok, Counter}, file:read_file(Store)),
        ok = hls_domain_async_fixture:hold(ConnectedBackend, request),
        Parent = self(),
        Stopper = spawn(fun() -> Parent ! {explicit_stop, self(), catch gen_server:stop(Child, shutdown, infinity)} end),
        receive {fixture_held, ConnectedBackend, request, Owner} -> ok after 1000 -> error(no_stop_submission) end,
        {ok, StoppedEvidence = #{state := #domain_state{phase = stopped}}} = hls_domain_async_fixture:status(ConnectedBackend),
        ConnectedRef = monitor(process, ConnectedBackend), exit(ConnectedBackend, kill),
        receive {'DOWN', ConnectedRef, process, ConnectedBackend, killed} -> ok after 1000 -> error(adapter_survived) end,
        ?assert(is_process_alive(Child)),
        NewProxy = spawn(fun() -> receive finish -> ok end end),
        {ok, NewBackend} = hls_domain_async_fixture:start_link(self(), StoppedEvidence#{actors := #{actor => NewProxy}}), unlink(NewBackend),
        try
            ?assertMatch({ok, #{phase := stopped, handle := Handle}}, hls_domain:reattach(Owner, Handle, NewBackend)),
            receive {explicit_stop, Stopper, ok} -> ok after 1500 -> error(retirement_not_reconciled) end,
            ?assertNot(is_process_alive(Child)),
            ?assertEqual({ok, Counter}, file:read_file(Store)),
            {ok, Replacement} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised}), unlink(Replacement),
            try
                #{handle := New} = instance_ready(Replacement),
                ?assertNotEqual(Handle, New)
            after stop(Replacement) end
        after stop(NewBackend), exit(NewProxy, kill) end
        after stop(ConnectedBackend), exit(ConnectedProxy, kill) end
    after stop(Child), stop(Owner), stop(Backend), exit(Proxy, kill), file:delete(Store) end.

%% Two real actor backends permit independent native progress and actual PID retirement checks.
-spec native(fun((pid(), pid(), pid(), file:filename()) -> term())) -> ok.
native(Fun) ->
    Store = store(),
    Spec = #{actors => #{actor => #{module => hls_domain_actor_fixture, mailbox_capacity => 4}}},
    {ok, A} = hls_domain_erts:start_link(Spec), unlink(A),
    {ok, B} = hls_domain_erts:start_link(Spec), unlink(B),
    {ok, Owner} = hls_domain:start_link(#{a => automatic, b => automatic}, backend(hls_domain_erts, #{a => A, b => B}, Store)),
    unlink(Owner),
    try Fun(Owner, A, B, Store), ok
    after stop(Owner), stop(A), stop(B), file:delete(Store) end.

%% This fixture models management acknowledgements only; native tests above establish real actor termination.
-spec modeled(fun((pid(), pid(), file:filename()) -> term())) -> ok.
modeled(Fun) ->
    Store = store(),
    {ok, Backend} = hls_domain_async_fixture:start_link(self()), unlink(Backend),
    {ok, Owner} = hls_domain:start_link(#{a => automatic}, backend(hls_domain_async_fixture, #{a => Backend}, Store)),
    unlink(Owner),
    try Fun(Owner, Backend, Store), ok
    after stop(Owner), stop(Backend), file:delete(Store) end.

%% Each test gets a non-reused counter file and retains no application state in it.
-spec store() -> file:filename().
store() ->
    Path = filename:join("/tmp", "hls-shutdown-" ++ integer_to_list(erlang:unique_integer([positive, monotonic]))),
    ok = hls_domain:create_store(Path), Path.

%% Both adapters implement the same public owner contract.
-spec backend(module(), map(), file:filename()) -> hls_domain:backend().
backend(Module, Endpoints, Store) -> #{module => Module, endpoints => Endpoints, incarnation_file => Store}.

%% Observe a requested phase with a finite witness deadline, never infer it from elapsed time.
-spec phase(pid(), hls_domain:domain(), hls_domain_lifecycle:phase()) -> hls_domain:snapshot().
phase(Owner, Domain, Wanted) -> until(fun() ->
    case hls_domain:status(Owner, Domain) of {ok, #{phase := Wanted} = Evidence} -> {ok, Evidence}; _ -> wait end
end, 600).

%% Readiness belongs to the child as well as its backend, preventing source-monitor setup races.
-spec instance_ready(pid()) -> hls_domain:snapshot().
instance_ready(Child) -> until(fun() ->
    case hls_domain_instance:status(Child) of #{phase := ready} = Evidence -> {ok, Evidence}; _ -> wait end
end, 600).

%% The bounded wait reports failure if evidence never arrives.
-spec until(fun(() -> {ok, term()} | wait), non_neg_integer()) -> term().
until(_Fun, 0) -> error(evidence_deadline);
until(Fun, Count) -> case Fun() of {ok, Value} -> Value; wait -> timer:sleep(5), until(Fun, Count - 1) end.

%% Test teardown tolerates processes already retired by the scenario.
-spec stop(pid()) -> ok.
stop(Pid) -> _ = catch gen_server:stop(Pid, normal, 2000), ok.
