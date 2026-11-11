-module(hls_domain_async_tests).
-include_lib("eunit/include/eunit.hrl").

%% A withheld status response in A must not block actual management of B.
-spec slow_status_is_independent_test() -> ok.
slow_status_is_independent_test() ->
    with_domains(fun(Owner, A, _B, _Store) ->
        ok = hls_domain_async_fixture:hold(A, status),
        Waiting = gen_server:send_request(Owner, {status, a}),
        held(A, status, Owner),
        ?assertMatch({ok, #{phase := unbound}}, hls_domain:status(Owner, b)),
        ?assertMatch({ok, #{phase := ready}}, hls_domain:activate(Owner, b)),
        ?assertEqual(timeout, gen_server:wait_response(Waiting, 0)),
        ?assertEqual({ok, manual}, hls_domain:policy(Owner, a)),
        ok = hls_domain_async_fixture:release(A),
        ?assertMatch({reply, {ok, #{phase := unbound}}}, response(Waiting))
    end).

%% Resolution's second stage preserves owner authority without blocking another domain.
-spec slow_endpoint_is_independent_test() -> ok.
slow_endpoint_is_independent_test() ->
    with_domains(fun(Owner, A, _B, _Store) ->
        {ok, #{handle := Handle}} = hls_domain:activate(Owner, a),
        ok = hls_domain_async_fixture:hold(A, endpoint),
        Waiting = gen_server:send_request(Owner, {resolve, Handle, actor}),
        held(A, endpoint, Owner),
        ?assertMatch({ok, #{phase := unbound}}, hls_domain:status(Owner, b)),
        ?assertEqual(timeout, gen_server:wait_response(Waiting, 0)),
        ok = hls_domain_async_fixture:release(A),
        ?assertEqual({reply, {ok, self()}}, response(Waiting))
    end).

%% Concurrent allocation remains durable and unique, with complete FIFO operations within A.
-spec slow_transition_preserves_order_and_unique_ids_test() -> ok.
slow_transition_preserves_order_and_unique_ids_test() ->
    with_domains(fun(Owner, A, _B, Store) ->
        ok = hls_domain_async_fixture:hold(A, request),
        First = gen_server:send_request(Owner, {activate, a}),
        held(A, request, Owner),
        {ok, <<FirstId:64>>} = file:read_file(Store),
        BeforeReplacement = gen_server:send_request(Owner, {status, a}),
        Replacement = gen_server:send_request(Owner, {replace, a, FirstId}),
        {ok, #{handle := {b, OtherId}}} = hls_domain:activate(Owner, b),
        ?assert(OtherId > FirstId),
        ?assertEqual({ok, <<OtherId:64>>}, file:read_file(Store)),
        ?assertEqual(timeout, gen_server:wait_response(BeforeReplacement, 0)),
        ok = hls_domain_async_fixture:release(A),
        ?assertMatch({reply, {ok, #{handle := {a, FirstId}, phase := ready}}}, response(First)),
        ?assertMatch({reply, {ok, #{handle := {a, FirstId}, phase := ready}}}, response(BeforeReplacement)),
        {reply, {ok, #{handle := {a, LastId}, phase := ready}}} = response(Replacement),
        ?assert(LastId > OtherId),
        ?assertEqual({ok, <<LastId:64>>}, file:read_file(Store)),
        ?assertMatch({ok, #{handle := {a, LastId}}}, hls_domain:replace(Owner, {a, FirstId})),
        ?assertEqual({ok, <<LastId:64>>}, file:read_file(Store))
    end).

%% Nine retained calls are allowed per domain; the next rejects before reaching any backend.
-spec per_domain_queue_bound_test() -> ok.
per_domain_queue_bound_test() ->
    with_domains(fun(Owner, A, _B, Store) ->
        ok = hls_domain_async_fixture:hold(A, status),
        Active = gen_server:send_request(Owner, {status, a}),
        held(A, status, Owner),
        Queued = [gen_server:send_request(Owner, {status, a}) || _ <- lists:seq(1, 8)],
        ?assertEqual({error, busy}, hls_domain:activate(Owner, a)),
        ?assertEqual({ok, <<0:64>>}, file:read_file(Store)),
        ?assertMatch({ok, #{phase := unbound}}, hls_domain:status(Owner, b)),
        ok = hls_domain_async_fixture:release(A),
        lists:foreach(fun(Request) ->
            ?assertMatch({reply, {ok, #{phase := unbound}}}, response(Request))
        end, [Active | Queued]),
        ?assertMatch({ok, #{phase := ready}}, hls_domain:activate(Owner, a))
    end).

%% A backend death releases its pending queue with unavailable evidence, not owner death.
-spec backend_failure_is_confined_test() -> ok.
backend_failure_is_confined_test() ->
    with_domains(fun(Owner, A, _B, _Store) ->
        ok = hls_domain_async_fixture:hold(A, status),
        First = gen_server:send_request(Owner, {status, a}),
        held(A, status, Owner),
        Second = gen_server:send_request(Owner, {status, a}),
        ?assertEqual({ok, manual}, hls_domain:policy(Owner, a)),
        exit(A, kill),
        ?assertMatch({reply, {error, {unavailable, _}}}, response(First)),
        ?assertMatch({reply, {error, {unavailable, _}}}, response(Second)),
        ?assertMatch({ok, #{phase := ready}}, hls_domain:activate(Owner, b)),
        ?assert(is_process_alive(Owner))
    end).

%% Stopping the actual owner retires active/queued calls and triggers backend owner monitors.
-spec owner_shutdown_retires_pending_management_test() -> ok.
owner_shutdown_retires_pending_management_test() ->
    with_domains(fun(Owner, A, B, Store) ->
        ok = hls_domain_async_fixture:hold(A, request),
        First = gen_server:send_request(Owner, {activate, a}),
        held(A, request, Owner),
        Second = gen_server:send_request(Owner, {status, a}),
        ?assertEqual({ok, manual}, hls_domain:policy(Owner, a)),
        {ok, <<Burned:64>>} = file:read_file(Store),
        ok = gen_server:stop(Owner),
        ?assertEqual({reply, {error, {owner_stopped, normal}}}, response(First)),
        ?assertEqual({reply, {error, {owner_stopped, normal}}}, response(Second)),
        owner_down(A, Owner),
        owner_down(B, Owner),
        ok = hls_domain_async_fixture:release(A),
        {ok, Replacement} = start_owner(A, B, Store),
        unlink(Replacement),
        try
            {ok, #{handle := {a, Next}}} = hls_domain:replace(Replacement, {a, Burned}),
            ?assert(Next > Burned),
            ?assertEqual({ok, <<Next:64>>}, file:read_file(Store))
        after stop(Replacement) end
    end).

%% Exercise the actual five-second deadline once; this is no application/physical recovery proof.
-spec timeout_preserves_uncertain_transition_test_() -> term().
timeout_preserves_uncertain_transition_test_() ->
    {timeout, 10, fun timeout_preserves_uncertain_transition/0}.

%% A withheld successful disposition burns its ID; late delivery cannot affect another request.
-spec timeout_preserves_uncertain_transition() -> ok.
timeout_preserves_uncertain_transition() ->
    with_domains(fun(Owner, A, _B, Store) ->
        ok = hls_domain_async_fixture:hold(A, request),
        First = gen_server:send_request(Owner, {activate, a}),
        held(A, request, Owner),
        {ok, <<Burned:64>>} = file:read_file(Store),
        ?assertEqual({reply, {error, {unavailable, timeout}}},
            gen_server:receive_response(First, 6500)),
        ?assertMatch({ok, #{handle := {a, Burned}, phase := ready}}, hls_domain:activate(Owner, a)),
        ok = hls_domain_async_fixture:release(A),
        ?assertMatch({ok, #{handle := {a, Burned}, phase := ready}}, hls_domain:status(Owner, a)),
        ?assertEqual({ok, <<Burned:64>>}, file:read_file(Store)),
        ?assertMatch({ok, #{phase := unbound}}, hls_domain:status(Owner, b))
    end).

%% Fixture notification is sent only after a selected request has reached its backend.
-spec held(pid(), atom(), pid()) -> ok.
held(Backend, Kind, Owner) ->
    receive {fixture_held, Backend, Kind, ActualCaller} -> ?assertEqual(Owner, ActualCaller)
    after 1000 -> error({backend_not_reached, Kind}) end.

%% The monitored PID must remain the deployment owner, never a transient request worker.
-spec owner_down(pid(), pid()) -> ok.
owner_down(Backend, Owner) ->
    receive {fixture_owner_down, Backend, Owner, normal} -> ok
    after 1000 -> error(owner_not_observed) end.

%% A response must arrive promptly once its deliberately withheld stage has been released.
-spec response(gen_server:request_id()) -> term().
response(Request) -> gen_server:receive_response(Request, 1000).

%% Each finite witness owns two controllers and one explicitly commissioned counter file.
-spec with_domains(fun((pid(), pid(), pid(), file:filename()) -> Result)) -> Result.
with_domains(Fun) ->
    Store = filename:join("/tmp", "hls-domain-async-" ++
        integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
        integer_to_list(erlang:unique_integer([positive]))),
    ok = hls_domain:create_store(Store),
    {ok, A} = hls_domain_async_fixture:start_link(self()), unlink(A),
    {ok, B} = hls_domain_async_fixture:start_link(self()), unlink(B),
    {ok, Owner} = start_owner(A, B, Store), unlink(Owner),
    try Fun(Owner, A, B, Store)
    after stop(Owner), stop(A), stop(B), file:delete(Store) end.

%% All authority-bearing callbacks use the real owner PID through the behavior contract.
-spec start_owner(pid(), pid(), file:filename()) -> gen_server:start_ret().
start_owner(A, B, Store) ->
    hls_domain:start_link(#{a => manual, b => manual}, #{module => hls_domain_async_fixture,
        endpoints => #{a => A, b => B}, incarnation_file => Store}).

%% Failed fixtures may already be dead; teardown never restarts or replays them.
-spec stop(pid()) -> ok.
stop(Pid) -> catch gen_server:stop(Pid), ok.
