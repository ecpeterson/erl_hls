-module(hls_domain_channel_instance_tests).
-include_lib("eunit/include/eunit.hrl").
-behaviour(supervisor).
-export([init/1]).

%% Acceptance followed by reply loss is confirmed through inspection, never another bind.
-spec lost_reply_confirms_same_generation_test() -> ok.
lost_reply_confirms_same_generation_test() ->
    with_instance(drop_bind_once, fun(Instance, Backend, _A, _B) ->
        Ready = await_ready(Instance, 100),
        ?assertMatch(#{generation := 1, source_incarnation := 10, destination_incarnation := 20}, Ready),
        ?assertEqual(1, maps:get(binds, gen_server:call(Backend, stats))),
        ?assertEqual(0, maps:get(fences, gen_server:call(Backend, stats)))
    end).

%% An ordered observation of the exact closed pre-bind state permits one checked control retry.
-spec lost_unexecuted_bind_retries_only_management_test() -> ok.
lost_unexecuted_bind_retries_only_management_test() ->
    with_instance(drop_unexecuted_once, fun(Instance, Backend, A, B) ->
        ?assertMatch(#{generation := 1}, await_ready(Instance, 100)),
        ?assertEqual(1, maps:get(binds, gen_server:call(Backend, stats))),
        ?assertEqual(0, maps:get(fences, gen_server:call(Backend, stats))),
        ?assertEqual(0, gen_server:call(A, mutations)),
        ?assertEqual(0, gen_server:call(B, mutations))
    end).

%% A lost unexecuted fence is retried only after exact ordered active-binding evidence.
-spec lost_unexecuted_fence_retries_only_management_test() -> ok.
lost_unexecuted_fence_retries_only_management_test() ->
    A = spawn(fun() -> owner(a, 10, true, 0) end),
    B = spawn(fun() -> owner(b, 20, true, 0) end),
    Previous = (cold())#{generation => 1, source_incarnation => 9, destination_incarnation => 19, active => true},
    Backend = spawn(fun() -> backend(drop_fence_unexecuted_once, Previous, #{binds => 0, fences => 0, inspections => 0}, current) end),
    {ok, Instance} = hls_domain_channel_instance:start_link(Backend, 0, {A, a}, {B, b}, options()),
    unlink(Instance),
    try
        ?assertMatch(#{generation := 2}, await_ready(Instance, 100)),
        ?assertMatch(#{binds := 1, fences := 1}, gen_server:call(Backend, stats)),
        ?assertEqual(0, gen_server:call(A, mutations)),
        ?assertEqual(0, gen_server:call(B, mutations))
    after catch gen_server:stop(Instance), exit(Backend, kill), exit(A, kill), exit(B, kill) end.

%% Queue saturation is a known pre-admission rejection and cannot fail the supervision group.
-spec busy_before_admission_retries_without_replacement_test() -> ok.
busy_before_admission_retries_without_replacement_test() ->
    with_instance(busy_bind_once, fun(Instance, Backend, _A, _B) ->
        ?assertMatch(#{generation := 1}, await_ready(Instance, 100)),
        ?assertEqual(1, maps:get(binds, gen_server:call(Backend, stats))),
        ?assertEqual(0, maps:get(fences, gen_server:call(Backend, stats)))
    end).

%% Unavailable transport or owner reads never request replacement or replay application work.
-spec uncertainty_keeps_representative_alive_test() -> ok.
uncertainty_keeps_representative_alive_test() ->
    with_instance(normal, fun(Instance, Backend, A, _B) ->
        _ = await_ready(Instance, 100),
        ok = gen_server:call(Backend, {status_result, {error, noconnection}}),
        await_unavailable(Instance, 100),
        timer:sleep(50),
        ?assert(is_process_alive(Instance)),
        ?assertMatch(#{binds := 1, fences := 0, inspections := Reads} when Reads < 30,
            gen_server:call(Backend, stats)),
        ok = gen_server:call(Backend, {status_result, current}),
        ok = gen_server:call(A, {available, false}),
        await_unavailable(Instance, 100),
        ?assert(is_process_alive(Instance)),
        ?assertEqual(0, gen_server:call(A, mutations))
    end).

%% Explicit replacement of a dead adapter preserves one exact surviving channel binding.
-spec explicit_transport_reattach_preserves_binding_test() -> ok.
explicit_transport_reattach_preserves_binding_test() ->
    with_instance(normal, fun(Instance, Backend, _A, _B) ->
        Ready = await_ready(Instance, 100),
        exit(Backend, kill),
        await_unavailable(Instance, 100),
        New = spawn(fun() -> backend(normal, maps:remove(phase, Ready), #{binds => 0, fences => 0, inspections => 0}, current) end),
        try
            ?assertEqual(ok, hls_domain_channel_instance:reattach(Instance, New)),
            ?assertMatch(#{generation := 1}, await_ready(Instance, 100)),
            ?assertMatch(#{binds := 0, fences := 0}, gen_server:call(New, stats))
        after exit(New, kill) end
    end).

%% A different channel pair cannot be silently adopted after transport loss.
-spec incompatible_reattach_rejects_without_mutation_test() -> ok.
incompatible_reattach_rejects_without_mutation_test() ->
    with_instance(normal, fun(Instance, Backend, _A, _B) ->
        Ready = await_ready(Instance, 100),
        exit(Backend, kill), await_unavailable(Instance, 100),
        Other = (maps:remove(phase, Ready))#{generation => 2, source_incarnation => 11, destination_incarnation => 21},
        New = spawn(fun() -> backend(normal, Other, #{binds => 0, fences => 0, inspections => 0}, current) end),
        try
            ?assertEqual({error, incompatible_binding}, hls_domain_channel_instance:reattach(Instance, New)),
            ?assert(is_process_alive(Instance)),
            ?assertMatch(#{binds := 0, fences := 0}, gen_server:call(New, stats))
        after exit(New, kill) end
    end).

%% The unchanged ordinary OTP child specification resolves a replacement adapter by local name.
-spec supervised_restart_after_named_reattach_test() -> ok.
supervised_restart_after_named_reattach_test() ->
    Name = hls_channel_instance_restart_fixture,
    A = spawn(fun() -> owner(a, 10, true, 0) end),
    B = spawn(fun() -> owner(b, 20, true, 0) end),
    Old = spawn(fun() -> backend(normal, cold(), #{binds => 0, fences => 0, inspections => 0}, current) end),
    true = register(Name, Old),
    Child = #{id => channel, start => {hls_domain_channel_instance, start_link,
        [Name, 0, {A, a}, {B, b}, options()]}, restart => permanent, shutdown => 1000, type => worker},
    {ok, Supervisor} = supervisor:start_link(?MODULE, Child), unlink(Supervisor),
    try
        [{channel, First, worker, _}] = supervisor:which_children(Supervisor),
        Ready = await_ready(First, 100),
        exit(Old, kill), await_unavailable(First, 100),
        New = spawn(fun() -> backend(normal, maps:remove(phase, Ready), #{binds => 0, fences => 0, inspections => 0}, current) end),
        true = register(Name, New),
        try
            ?assertEqual(ok, hls_domain_channel_instance:reattach(First, Name)),
            _ = await_ready(First, 100),
            ok = gen_server:call(A, {incarnation, 11}),
            ok = gen_server:call(B, {incarnation, 21}),
            ok = supervisor:terminate_child(Supervisor, channel),
            {ok, Second} = supervisor:restart_child(Supervisor, channel),
            ?assert(Second =/= First),
            ?assertMatch(#{generation := 2, source_incarnation := 11, destination_incarnation := 21},
                await_ready(Second, 100)),
            ?assertMatch(#{binds := 1, fences := 1}, gen_server:call(New, stats))
        after exit(New, kill) end
    after catch gen_server:stop(Supervisor), exit(Old, kill), exit(A, kill), exit(B, kill) end.

-doc "Returns an ordinary OTP child specification unchanged across adapter replacement.".
-spec init(supervisor:child_spec()) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init(Child) -> {ok, {#{strategy => one_for_one, intensity => 3, period => 10}, [Child]}}.

%% Loss during accepted initial binding reconciles the pending pair on a new adapter.
-spec reattach_interrupted_bind_test() -> ok.
reattach_interrupted_bind_test() ->
    Parent = self(),
    A = spawn(fun() -> owner(a, 10, true, 0) end),
    B = spawn(fun() -> owner(b, 20, true, 0) end),
    Backend = spawn(fun() -> interrupted_backend(Parent) end),
    {ok, Instance} = hls_domain_channel_instance:start_link(Backend, 0, {A, a}, {B, b}, options()),
    unlink(Instance),
    try
        Snapshot = receive {accepted_before_loss, Backend, Value} -> Value after 1000 -> error(no_bind) end,
        await_unavailable(Instance, 100),
        New = spawn(fun() -> backend(normal, Snapshot, #{binds => 0, fences => 0, inspections => 0}, current) end),
        try
            ?assertEqual(ok, hls_domain_channel_instance:reattach(Instance, New)),
            ?assertMatch(#{generation := 1}, await_ready(Instance, 100)),
            ?assertEqual(0, maps:get(binds, gen_server:call(New, stats)))
        after exit(New, kill) end
    after catch gen_server:stop(Instance), exit(A, kill), exit(B, kill), exit(Backend, kill) end.

%% A fresh session excluding the old transport can also prove that initial binding never happened.
-spec reattach_unexecuted_bind_test() -> ok.
reattach_unexecuted_bind_test() ->
    Parent = self(),
    A = spawn(fun() -> owner(a, 10, true, 0) end),
    B = spawn(fun() -> owner(b, 20, true, 0) end),
    Backend = spawn(fun() -> unexecuted_backend(Parent) end),
    {ok, Instance} = hls_domain_channel_instance:start_link(Backend, 0, {A, a}, {B, b}, options()),
    unlink(Instance),
    try
        receive {lost_before_execution, Backend} -> ok after 1000 -> error(no_bind) end,
        await_unavailable(Instance, 100),
        New = spawn(fun() -> backend(normal, cold(), #{binds => 0, fences => 0, inspections => 0}, current) end),
        try
            ?assertEqual(ok, hls_domain_channel_instance:reattach(Instance, New)),
            ?assertMatch(#{generation := 1}, await_ready(Instance, 100)),
            ?assertMatch(#{binds := 1, fences := 0}, gen_server:call(New, stats)),
            ?assertEqual(0, gen_server:call(A, mutations)),
            ?assertEqual(0, gen_server:call(B, mutations))
        after exit(New, kill) end
    after catch gen_server:stop(Instance), exit(A, kill), exit(B, kill), exit(Backend, kill) end.

%% All observations use public APIs against isolated native fixture processes.
-spec with_instance(atom(), fun((pid(), pid(), pid(), pid()) -> term())) -> ok.
with_instance(Mode, Fun) ->
    A = spawn(fun() -> owner(a, 10, true, 0) end),
    B = spawn(fun() -> owner(b, 20, true, 0) end),
    Backend = spawn(fun() -> backend(Mode, cold(), #{binds => 0, fences => 0, inspections => 0}, current) end),
    {ok, Instance} = hls_domain_channel_instance:start_link(Backend, 0, {A, a}, {B, b}, options()),
    unlink(Instance),
    try Fun(Instance, Backend, A, B), ok
    after catch gen_server:stop(Instance), exit(Backend, kill), exit(A, kill), exit(B, kill) end.

%% These short deadlines exercise missing acknowledgements without depending on device timing.
-spec options() -> hls_domain_channel_instance:options().
options() -> #{poll_ms => 5, request_timeout_ms => 30}.

%% Mock deployment owners accept status only; mutation counts expose accidental lifecycle control.
-spec owner(atom(), pos_integer(), boolean(), non_neg_integer()) -> no_return().
owner(Domain, Incarnation, Available, Mutations) ->
    receive
        {'$gen_call', From, {status, Domain}} ->
            Reply = case Available of true -> {ok, #{phase => ready, handle => {Domain, Incarnation}}}; false -> {error, noconnection} end,
            gen_server:reply(From, Reply), owner(Domain, Incarnation, Available, Mutations);
        {'$gen_call', From, {incarnation, Value}} -> gen_server:reply(From, ok), owner(Domain, Value, Available, Mutations);
        {'$gen_call', From, {available, Value}} -> gen_server:reply(From, ok), owner(Domain, Incarnation, Value, Mutations);
        {'$gen_call', From, mutations} -> gen_server:reply(From, Mutations), owner(Domain, Incarnation, Available, Mutations);
        {'$gen_call', From, _} -> gen_server:reply(From, {error, forbidden}), owner(Domain, Incarnation, Available, Mutations + 1)
    end.

%% The management fixture models complete command acceptance and independent reply delivery.
-spec backend(atom(), map(), map(), current | {error, noconnection}) -> no_return().
backend(Mode, Snapshot, Stats, StatusResult) ->
    receive
        {'$gen_call', From = {Owner, _}, {attach, 0, Owner}} ->
            gen_server:reply(From, {ok, make_ref()}), backend(Mode, Snapshot, Stats, StatusResult);
        {'$gen_call', From, {status, 0}} ->
            Reply = case StatusResult of current -> {ok, Snapshot}; _ -> StatusResult end,
            gen_server:reply(From, Reply), backend(Mode, Snapshot, Stats#{inspections := maps:get(inspections, Stats) + 1}, StatusResult);
        {'$gen_call', From, {request, _, 0, {bind, Expected, Source, Destination}}} ->
            case Mode of
                busy_bind_once -> gen_server:reply(From, {error, busy}), backend(normal, Snapshot, Stats, StatusResult);
                drop_unexecuted_once -> backend(normal, Snapshot, Stats, StatusResult);
                _ ->
                    Next = Snapshot#{generation => Expected + 1, source_incarnation => Source, destination_incarnation => Destination,
                        active => true, status => accepted},
                    case Mode of drop_bind_once -> ok; _ -> gen_server:reply(From, {ok, Next}) end,
                    backend(normal, Next, Stats#{binds := maps:get(binds, Stats) + 1}, StatusResult)
            end;
        {'$gen_call', From, {request, _, 0, {fence, _}}} ->
            case Mode of
                drop_fence_unexecuted_once -> backend(normal, Snapshot, Stats, StatusResult);
                _ ->
                    Next = Snapshot#{active => false}, gen_server:reply(From, {ok, Next}),
                    backend(Mode, Next, Stats#{fences := maps:get(fences, Stats) + 1}, StatusResult)
            end;
        {'$gen_call', From, {status_result, Value}} -> gen_server:reply(From, ok), backend(Mode, Snapshot, Stats, Value);
        {'$gen_call', From, stats} -> gen_server:reply(From, Stats), backend(Mode, Snapshot, Stats, StatusResult)
    end.

%% Stop the local adapter immediately after accepting a bind, before its acknowledgement.
-spec interrupted_backend(pid()) -> no_return().
interrupted_backend(Parent) ->
    receive
        {'$gen_call', From = {Owner, _}, {attach, 0, Owner}} -> gen_server:reply(From, {ok, make_ref()}), interrupted_backend(Parent);
        {'$gen_call', From, {status, 0}} -> gen_server:reply(From, {ok, cold()}), interrupted_backend(Parent);
        {'$gen_call', _From, {request, _, 0, {bind, Expected, Source, Destination}}} ->
            Snapshot = (cold())#{generation => Expected + 1, source_incarnation => Source, destination_incarnation => Destination, active => true},
            Parent ! {accepted_before_loss, self(), Snapshot}, exit(simulated_transport_loss)
    end.

%% Simulate adapter loss before accepting its command; no remote binding effect exists.
-spec unexecuted_backend(pid()) -> no_return().
unexecuted_backend(Parent) ->
    receive
        {'$gen_call', From = {Owner, _}, {attach, 0, Owner}} -> gen_server:reply(From, {ok, make_ref()}), unexecuted_backend(Parent);
        {'$gen_call', From, {status, 0}} -> gen_server:reply(From, {ok, cold()}), unexecuted_backend(Parent);
        {'$gen_call', _From, {request, _, 0, {bind, _, _, _}}} ->
            Parent ! {lost_before_execution, self()}, exit(simulated_transport_loss)
    end.

%% The cold device has never assigned either endpoint or a channel generation.
-spec cold() -> hls_domain_channel_wire:snapshot().
cold() -> #{status => ok, generation => 0, source_incarnation => 0, destination_incarnation => 0,
    packet_sequence => 0, active => false, fault => false}.

%% Bounded waiting distinguishes asynchronous startup from an unresponsive coordinator.
-spec await_ready(pid(), non_neg_integer()) -> map().
await_ready(_Instance, 0) -> error(not_ready);
await_ready(Instance, Remaining) ->
    case hls_domain_channel_instance:status(Instance) of
        #{phase := ready} = Snapshot -> Snapshot;
        _ -> timer:sleep(5), await_ready(Instance, Remaining - 1)
    end.

%% Transport uncertainty is observable while the supervisor child remains alive.
-spec await_unavailable(pid(), non_neg_integer()) -> ok.
await_unavailable(_Instance, 0) -> error(not_unavailable);
await_unavailable(Instance, Remaining) ->
    case hls_domain_channel_instance:status(Instance) of
        {error, noconnection} -> ok;
        _ -> timer:sleep(5), await_unavailable(Instance, Remaining - 1)
    end.
