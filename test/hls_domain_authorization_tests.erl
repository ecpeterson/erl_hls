-module(hls_domain_authorization_tests).
-moduledoc "Finite witnesses for manual, single-start supervisor permission and bounded retirement.".
-include_lib("eunit/include/eunit.hrl").

%% Real actors retire between trials; a spent permission cannot manufacture a successor.
-spec native_two_trials_test() -> ok.
native_two_trials_test() ->
    fixture(native, fun(Owner, _Backend, Store) ->
        ?assertEqual({error, manual_replacement_required}, hls_domain:supervise(Owner, a)),
        ?assertEqual({error, automatic_replacement}, hls_domain:authorize(Owner, b)),
        ?assertEqual({error, unknown_domain}, hls_domain:authorize(Owner, missing)),
        {ok, Grant} = hls_domain:authorize(Owner, a),
        ?assertEqual({error, already_authorized}, hls_domain:authorize(Owner, a)),
        ?assertEqual({error, authorized}, hls_domain:activate(Owner, a)),
        ?assertEqual({error, invalid_authorization}, hls_domain:supervise(Owner, a, make_ref())),
        Child = child(Owner, Grant),
        {ok, #{handle := Old}} = hls_domain_instance:await_ready(Child, 2000),
        {ok, Actor} = hls_domain_instance:resolve(Child, actor),
        ok = hls_statem:admit_cast(Actor, {add, 17}),
        ?assertEqual({readout, 17}, hls_statem:call(Actor, {get, 0})),
        ?assertEqual({error, supervised}, hls_domain:authorize(Owner, a)),
        exit(Child, kill),
        ok = hls_domain:retire(Owner, a, 2000),
        ?assertNot(is_process_alive(Actor)),
        ?assertEqual({error, invalid_authorization}, hls_domain:supervise(Owner, a, Grant)),
        ?assertEqual({ok, <<1:64>>}, file:read_file(Store)),
        {ok, NextGrant} = hls_domain:authorize(Owner, a),
        Next = child(Owner, NextGrant),
        try
            {ok, #{handle := New}} = hls_domain_instance:await_ready(Next, 2000),
            ?assertNotEqual(Old, New),
            {ok, NewActor} = hls_domain_instance:resolve(Next, actor),
            ?assertEqual({readout, 0}, hls_statem:call(NewActor, {get, 0})),
            ok = gen_server:stop(Next, shutdown, 2000),
            ok = hls_domain:retire(Owner, a, 2000)
        after stop(Next) end
    end).

%% Even the authorized representative cannot allocate a second incarnation using its first claim.
-spec one_allocation_per_claim_test() -> ok.
one_allocation_per_claim_test() ->
    fixture(model, fun(Owner, _Backend, Store) ->
        {ok, Grant} = hls_domain:authorize(Owner, a),
        {ok, #{phase := unbound}} = hls_domain:supervise(Owner, a, Grant),
        {ok, #{handle := Handle}} = hls_domain:activate(Owner, a),
        ?assertMatch({ok, #{handle := Handle}}, hls_domain:activate(Owner, a)),
        ?assertEqual({error, authorization_spent}, hls_domain:replace(Owner, Handle)),
        ?assertEqual({ok, <<1:64>>}, file:read_file(Store)),
        ok = hls_domain:release(Owner, a),
        ok = hls_domain:retire(Owner, a, 2000),
        ?assertEqual({error, invalid_authorization}, hls_domain:supervise(Owner, a, Grant))
    end).

%% Revocation cancels a grant whose observed reply is still in flight; a newer grant survives it.
-spec delayed_grant_revocation_test() -> ok.
delayed_grant_revocation_test() ->
    fixture(model, fun(Owner, Backend, _Store) ->
        ok = hls_domain_async_fixture:hold(Backend, status),
        Old = gen_server:send_request(Owner, {authorize, a}),
        held(Backend, Owner),
        ok = gen_server:call(Owner, {retire_domain, a}),
        New = gen_server:send_request(Owner, {authorize, a}),
        ok = hls_domain_async_fixture:release(Backend),
        ?assertEqual({reply, {error, authorization_revoked}}, gen_server:receive_response(Old, 1000)),
        {reply, {ok, Grant}} = gen_server:receive_response(New, 1000),
        {ok, _} = hls_domain:supervise(Owner, a, Grant),
        ok = hls_domain:release(Owner, a),
        ok = hls_domain:retire(Owner, a, 2000)
    end).

%% A full management lane cannot consume a grant or leave a phantom reservation.
-spec busy_admission_rolls_back_test() -> ok.
busy_admission_rolls_back_test() ->
    fixture(model, fun(Owner, Backend, _Store) ->
        Requests = fill_lane(Owner, Backend),
        ?assertEqual({error, busy}, hls_domain:authorize(Owner, a)),
        drain_lane(Backend, Requests),
        {ok, Grant} = hls_domain:authorize(Owner, a),
        More = fill_lane(Owner, Backend),
        ?assertEqual({error, busy}, hls_domain:supervise(Owner, a, Grant)),
        drain_lane(Backend, More),
        {ok, _} = hls_domain:supervise(Owner, a, Grant),
        ok = hls_domain:release(Owner, a),
        ok = hls_domain:retire(Owner, a, 2000)
    end).

%% A caller timeout cannot complete a physical fence or reset an independent ready domain.
-spec withheld_fence_preserves_intent_test() -> ok.
withheld_fence_preserves_intent_test() ->
    fixture(model, fun(Owner, Backend, Store) ->
        {ok, _} = hls_domain:activate(Owner, b),
        {ok, Grant} = hls_domain:authorize(Owner, a),
        Child = child(Owner, Grant),
        {ok, #{handle := Handle}} = hls_domain_instance:await_ready(Child, 2000),
        ok = hls_domain_async_fixture:pause(Backend, fence),
        exit(Child, kill),
        ?assertMatch({error, _}, hls_domain:retire(Owner, a, 80)),
        ?assertMatch({ok, #{phase := closing, handle := Handle}}, hls_domain:status(Owner, a)),
        ?assertEqual({error, supervised}, hls_domain:authorize(Owner, a)),
        ?assertMatch({ok, #{phase := ready}}, hls_domain:status(Owner, b)),
        ?assertEqual({ok, <<2:64>>}, file:read_file(Store)),
        ok = hls_domain_async_fixture:advance(Backend),
        ok = hls_domain:retire(Owner, a, 2000),
        {ok, _} = hls_domain:authorize(Owner, a),
        ok = hls_domain:retire(Owner, a, 2000)
    end).

%% Killing an initializing representative retains its admitted target without granting a retry.
-spec initializing_child_death_test() -> ok.
initializing_child_death_test() ->
    fixture(model, fun(Owner, Backend, Store) ->
        ok = hls_domain_async_fixture:pause(Backend, initialize),
        {ok, Grant} = hls_domain:authorize(Owner, a),
        Child = child(Owner, Grant),
        ?assertEqual({error, timeout}, hls_domain_instance:await_ready(Child, 40)),
        exit(Child, kill),
        ?assertMatch({error, _}, hls_domain:retire(Owner, a, 40)),
        ?assertEqual({error, invalid_authorization}, hls_domain:supervise(Owner, a, Grant)),
        ok = hls_domain_async_fixture:advance(Backend),
        ok = hls_domain:retire(Owner, a, 2000),
        ?assertEqual({ok, <<1:64>>}, file:read_file(Store))
    end).

%% An ordinary direct activation cannot be retroactively adopted by a manual permission.
-spec live_domain_cannot_be_authorized_test() -> ok.
live_domain_cannot_be_authorized_test() ->
    fixture(model, fun(Owner, _Backend, _Store) ->
        {ok, _} = hls_domain:activate(Owner, a),
        ?assertEqual({error, not_retired}, hls_domain:authorize(Owner, a)),
        ok = hls_domain:retire(Owner, a, 2000),
        {ok, Grant} = hls_domain:authorize(Owner, a),
        ok = hls_domain:retire(Owner, a, 2000),
        ?assertEqual({error, invalid_authorization}, hls_domain:supervise(Owner, a, Grant))
    end).

%% A fresh owner cannot use a prior owner's in-memory grant, even with the same persistent counter.
-spec owner_restart_loses_grant_test() -> ok.
owner_restart_loses_grant_test() ->
    fixture(model, fun(Owner, Backend, Store) ->
        {ok, Grant} = hls_domain:authorize(Owner, a),
        stop(Owner),
        %% The backend processes the owner's DOWN before attaching again.
        timer:sleep(10),
        {ok, NewOwner} = hls_domain:start_link(#{a => manual}, config(hls_domain_async_fixture, #{a => Backend}, Store)),
        unlink(NewOwner),
        try
            ?assertEqual({error, invalid_authorization}, hls_domain:supervise(NewOwner, a, Grant)),
            {ok, _} = hls_domain:authorize(NewOwner, a)
        after stop(NewOwner) end
    end).

%% Retirement before startup must not forget a still-live representative and admit its delayed call.
-spec delayed_start_after_retirement_test() -> ok.
delayed_start_after_retirement_test() ->
    fixture(model, fun(Owner, _Backend, Store) ->
        {ok, Grant} = hls_domain:authorize(Owner, a),
        Parent = self(),
        Child = spawn(fun() ->
            {ok, _} = hls_domain:supervise(Owner, a, Grant),
            Parent ! claimed,
            receive start -> ok end,
            Parent ! {late_start, hls_domain:activate(Owner, a)},
            ok = hls_domain:release(Owner, a)
        end),
        Monitor = monitor(process, Child),
        receive claimed -> ok after 1000 -> error(no_claim) end,
        ok = gen_server:call(Owner, {retire_domain, a}),
        ?assertMatch({ok, #{phase := unbound}}, hls_domain:status(Owner, a)),
        ?assertEqual({error, supervised}, hls_domain:authorize(Owner, a)),
        Child ! start,
        receive {late_start, Result} -> ?assertEqual({error, supervised}, Result)
        after 1000 -> error(no_late_start) end,
        receive {'DOWN', Monitor, process, Child, normal} -> ok after 1000 -> error(child_survived) end,
        ok = hls_domain:retire(Owner, a, 2000),
        ?assertEqual({ok, <<0:64>>}, file:read_file(Store)),
        {ok, _} = hls_domain:authorize(Owner, a)
    end).

%% Start promptly and let the public readiness API establish the actual incarnation.
-spec child(pid(), hls_domain:authorization()) -> pid().
child(Owner, Grant) ->
    {ok, Pid} = hls_domain_instance:start_link(Owner, a, #{lifetime => supervised, authorization => Grant}),
    unlink(Pid), Pid.

%% Two separate backends demonstrate that waiting in a cannot obstruct b.
-spec fixture(native | model, fun((pid(), pid(), file:filename()) -> term())) -> ok.
fixture(Kind, Fun) ->
    Store = filename:join("/tmp", "hls-grant-" ++ integer_to_list(erlang:unique_integer([positive, monotonic]))),
    ok = hls_domain:create_store(Store),
    {Module, Argument} = case Kind of
        model -> {hls_domain_async_fixture, self()};
        native -> {hls_domain_erts, #{actors => #{actor => #{module => hls_domain_actor_fixture, mailbox_capacity => 4}}}}
    end,
    {ok, A} = Module:start_link(Argument), unlink(A),
    {ok, B} = Module:start_link(Argument), unlink(B),
    {ok, Owner} = hls_domain:start_link(#{a => manual, b => automatic}, config(Module, #{a => A, b => B}, Store)),
    unlink(Owner),
    try Fun(Owner, A, Store), ok
    after stop(Owner), stop(A), stop(B), file:delete(Store) end.

%% Both adapters satisfy the same owner contract.
-spec config(module(), map(), file:filename()) -> hls_domain:backend().
config(Module, Endpoints, Store) -> #{module => Module, endpoints => Endpoints, incarnation_file => Store}.

%% Exactly nine outstanding operations exhaust the bounded lane.
-spec fill_lane(pid(), pid()) -> [gen_server:request_id()].
fill_lane(Owner, Backend) ->
    ok = hls_domain_async_fixture:hold(Backend, status),
    First = gen_server:send_request(Owner, {status, a}), held(Backend, Owner),
    [First | [gen_server:send_request(Owner, {status, a}) || _ <- lists:seq(1, 8)]].

%% Explicit fixture notification orders the race rather than assuming a sleep is enough.
-spec held(pid(), pid()) -> ok.
held(Backend, Owner) -> receive {fixture_held, Backend, status, Owner} -> ok after 1000 -> error(no_held_status) end.

%% Every delayed operation is consumed once before the next test phase.
-spec drain_lane(pid(), [gen_server:request_id()]) -> ok.
drain_lane(Backend, Requests) ->
    ok = hls_domain_async_fixture:release(Backend),
    lists:foreach(fun(R) -> ?assertMatch({reply, {ok, _}}, gen_server:receive_response(R, 1000)) end, Requests).

%% Test teardown tolerates a child/owner already retired by the scenario.
-spec stop(pid()) -> ok.
stop(Pid) -> _ = catch gen_server:stop(Pid, normal, 2000), ok.
