-module(hls_domain_reattach_tests).
-moduledoc "Finite host-controller reconnection witnesses; retained fixture snapshots model hardware identity, not physical persistence.".
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Reattachment preserves identity and the counter, while the other domain and owner remain usable.
-spec same_incarnation_reattachment_is_ordered_and_independent_test() -> ok.
same_incarnation_reattachment_is_ordered_and_independent_test() ->
    with_domains(fun(Owner, A, B, Store) ->
        {ok, #{handle := {a, Id} = Handle}} = hls_domain:activate(Owner, a),
        {ok, Evidence} = hls_domain_async_fixture:status(A),
        {ok, Candidate} = hls_domain_async_fixture:start_link(self(), Evidence), unlink(Candidate),
        try
            ?assertEqual({error, backend_still_alive}, hls_domain:reattach(Owner, Handle, Candidate)),
            stop(A),
            ?assertEqual({error, backend_already_bound}, hls_domain:reattach(Owner, Handle, B)),
            ok = hls_domain_async_fixture:hold(Candidate, attach),
            Reconnect = gen_server:send_request(Owner, {reattach, a, Id, Candidate}),
            held(Candidate, attach, Owner),
            Resolve = gen_server:send_request(Owner, {resolve, Handle, actor}),
            ?assertEqual(timeout, gen_server:wait_response(Resolve, 0)),
            ?assertMatch({ok, #{phase := unbound}}, hls_domain:status(Owner, b)),
            ok = hls_domain_async_fixture:release(Candidate),
            ?assertMatch({reply, {ok, #{phase := ready, handle := Handle}}}, response(Reconnect)),
            ?assertEqual({reply, {ok, self()}}, response(Resolve)),
            ?assertEqual({ok, <<Id:64>>}, file:read_file(Store)),
            ?assert(is_process_alive(Owner))
        after stop(Candidate) end
    end).

%% Asynchronous probes in different domain lanes cannot reserve one candidate twice.
-spec concurrent_domains_cannot_alias_candidate_test() -> ok.
concurrent_domains_cannot_alias_candidate_test() ->
    with_domains(fun(Owner, A, B, _Store) ->
        {ok, #{handle := {a, Id}}} = hls_domain:activate(Owner, a),
        {ok, Evidence} = hls_domain_async_fixture:status(A),
        {ok, Candidate} = hls_domain_async_fixture:start_link(self(), Evidence), unlink(Candidate),
        try
            stop(A), stop(B),
            ok = hls_domain_async_fixture:hold(Candidate, status),
            First = gen_server:send_request(Owner, {reattach, a, Id, Candidate}),
            held(Candidate, status, Owner),
            ?assertEqual({error, backend_already_bound},
                hls_domain:reattach(Owner, {b, Id}, Candidate)),
            ok = hls_domain_async_fixture:release(Candidate),
            ?assertMatch({reply, {ok, #{handle := {a, Id}}}}, response(First))
        after stop(Candidate) end
    end).

%% A candidate with a different identity cannot acquire authority or replace the old binding.
-spec mismatching_incarnation_does_not_bind_test() -> ok.
mismatching_incarnation_does_not_bind_test() ->
    with_domains(fun(Owner, A, _B, Store) ->
        {ok, #{handle := {a, Id} = Handle}} = hls_domain:activate(Owner, a),
        {ok, Evidence = #{state := State}} = hls_domain_async_fixture:status(A),
        Mismatch = Evidence#{state := State#domain_state{current = Id + 1}},
        {ok, Candidate} = hls_domain_async_fixture:start_link(self(), Mismatch), unlink(Candidate),
        try
            stop(A),
            ?assertEqual({error, incarnation_not_ready}, hls_domain:reattach(Owner, Handle, Candidate)),
            ?assertMatch({error, {unavailable, _}}, hls_domain:status(Owner, a)),
            ?assertMatch({ok, _}, hls_domain_async_fixture:attach(Candidate, self())),
            ?assertEqual({ok, <<Id:64>>}, file:read_file(Store))
        after stop(Candidate) end
    end).

%% Losing the final observation leaves an inspectable new binding and does not imply a reset.
-spec lost_confirmation_requires_reconciliation_test() -> ok.
lost_confirmation_requires_reconciliation_test() ->
    with_domains(fun(Owner, A, _B, Store) ->
        {ok, #{handle := {a, Id} = Handle}} = hls_domain:activate(Owner, a),
        {ok, Evidence} = hls_domain_async_fixture:status(A),
        {ok, Candidate} = hls_domain_async_fixture:start_link(self(), Evidence), unlink(Candidate),
        {ok, Next} = hls_domain_async_fixture:start_link(self(), Evidence), unlink(Next),
        try
            stop(A),
            ok = hls_domain_async_fixture:hold(Candidate, attach),
            Reconnect = gen_server:send_request(Owner, {reattach, a, Id, Candidate}),
            held(Candidate, attach, Owner),
            ok = hls_domain_async_fixture:hold(Candidate, status),
            ok = hls_domain_async_fixture:release(Candidate),
            held(Candidate, status, Owner),
            stop(Candidate),
            ?assertMatch({reply, {error, {unavailable, _}}}, response(Reconnect)),
            ?assertMatch({error, {unavailable, _}}, hls_domain:status(Owner, a)),
            ?assertMatch({ok, #{handle := Handle}}, hls_domain:reattach(Owner, Handle, Next)),
            ?assertEqual({ok, <<Id:64>>}, file:read_file(Store))
        after stop(Candidate), stop(Next) end
    end).

%% A representative survives transport-only proxy loss, then binds monitors to confirmed same-incarnation proxies.
-spec instance_waits_for_explicit_reattachment_test() -> ok.
instance_waits_for_explicit_reattachment_test() ->
    with_domains(fun(Owner, A, _B, Store) ->
        {ok, #{handle := {a, Id} = Handle}} = hls_domain:activate(Owner, a),
        {ok, Evidence} = hls_domain_async_fixture:status(A),
        FirstProxy = spawn(fun proxy/0),
        NextProxy = spawn(fun proxy/0),
        {ok, First} = hls_domain_async_fixture:start_link(self(), Evidence#{actors := #{actor => FirstProxy}}),
        unlink(First),
        {ok, Next} = hls_domain_async_fixture:start_link(self(), Evidence#{actors := #{actor => NextProxy}}),
        unlink(Next),
        stop(A),
        {ok, _} = hls_domain:reattach(Owner, Handle, First),
        {ok, Instance} = hls_domain_instance:start_link(Owner, a), unlink(Instance),
        try
            await_instance(Instance, fun(Status) -> is_map(Status) end, 200),
            ?assertEqual({ok, FirstProxy}, hls_domain_instance:resolve(Instance, actor)),
            stop(First),
            exit(FirstProxy, noconnection),
            await_instance(Instance, fun(Status) -> Status =:= {error, noconnection} end, 200),
            ?assertEqual({error, noconnection}, hls_domain_instance:resolve(Instance, actor)),
            ?assert(is_process_alive(Instance)),
            ?assertEqual({ok, <<Id:64>>}, file:read_file(Store)),
            {ok, _} = hls_domain:reattach(Owner, Handle, Next),
            await_instance(Instance, fun(Status) -> is_map(Status) end, 200),
            ?assertEqual({ok, NextProxy}, hls_domain_instance:resolve(Instance, actor)),
            #{handle := Handle} = hls_domain_instance:status(Instance),
            Monitor = monitor(process, Instance),
            exit(NextProxy, actual_actor_failure),
            receive {'DOWN', Monitor, process, Instance,
                {domain_actor_down, NextProxy, actual_actor_failure}} -> ok
            after 1000 -> error(actor_failure_not_reported) end,
            ?assertEqual({ok, <<Id:64>>}, file:read_file(Store))
        after stop(Instance), stop(First), stop(Next), exit(FirstProxy, kill), exit(NextProxy, kill) end
    end).

%% Exercise the real owner-call deadline once while the instance is already disconnected.
-spec unavailable_observer_timeout_test_() -> term().
unavailable_observer_timeout_test_() ->
    {timeout, 10, fun unavailable_observer_timeout/0}.

%% A blocked owner cannot turn transport uncertainty into representative death or replacement.
-spec unavailable_observer_timeout() -> ok.
unavailable_observer_timeout() ->
    with_domains(fun(Owner, A, _B, Store) ->
        {ok, #{handle := {a, Id} = Handle}} = hls_domain:activate(Owner, a),
        {ok, Evidence} = hls_domain_async_fixture:status(A),
        FirstProxy = spawn(fun proxy/0),
        NextProxy = spawn(fun proxy/0),
        {ok, First} = hls_domain_async_fixture:start_link(self(), Evidence#{actors := #{actor => FirstProxy}}),
        unlink(First),
        {ok, Next} = hls_domain_async_fixture:start_link(self(), Evidence#{actors := #{actor => NextProxy}}),
        unlink(Next),
        stop(A),
        {ok, _} = hls_domain:reattach(Owner, Handle, First),
        {ok, Instance} = hls_domain_instance:start_link(Owner, a), unlink(Instance),
        try
            await_instance(Instance, fun(Status) -> is_map(Status) end, 200),
            ok = hls_domain_async_fixture:hold(First, status),
            exit(FirstProxy, noconnection),
            held(First, status, Owner),
            %% Suspend only after the watcher is waiting, forcing its own call deadline to fire.
            ok = sys:suspend(Owner),
            ?assertEqual({error, noconnection}, gen_server:call(Instance, status, 6500)),
            ?assert(is_process_alive(Instance)),
            ?assertEqual({ok, <<Id:64>>}, file:read_file(Store)),
            stop(First),
            ok = sys:resume(Owner),
            {ok, _} = hls_domain:reattach(Owner, Handle, Next),
            await_instance(Instance, fun(Status) -> is_map(Status) end, 200),
            ?assertEqual({ok, NextProxy}, hls_domain_instance:resolve(Instance, actor)),
            ?assertEqual({ok, <<Id:64>>}, file:read_file(Store))
        after
            catch sys:resume(Owner), stop(Instance), stop(First), stop(Next),
            exit(FirstProxy, kill), exit(NextProxy, kill)
        end
    end).

%% Only identity and process lifetime matter to this host-observer fixture.
-spec proxy() -> ok.
proxy() -> receive stop -> ok end.

%% Observe availability with a finite witness horizon; elapsed time never establishes readiness.
-spec await_instance(pid(), fun((term()) -> boolean()), non_neg_integer()) -> ok.
await_instance(_Instance, _Predicate, 0) -> error(instance_observation_timeout);
await_instance(Instance, Predicate, Left) ->
    case Predicate(hls_domain_instance:status(Instance)) of
        true -> ok;
        false -> receive after 5 -> await_instance(Instance, Predicate, Left - 1) end
    end.

%% Exact owner identity is asserted at deliberately delayed backend stages.
-spec held(pid(), atom(), pid()) -> ok.
held(Backend, Kind, Owner) ->
    receive {fixture_held, Backend, Kind, ActualCaller} -> ?assertEqual(Owner, ActualCaller)
    after 1000 -> error({backend_not_reached, Kind}) end.

%% Finite checks await an already admitted operation rather than resubmitting it.
-spec response(gen_server:request_id()) -> term().
response(Request) -> gen_server:receive_response(Request, 1000).

%% Each witness owns separate controllers and a fresh counter; it never synthesizes hardware evidence.
-spec with_domains(fun((pid(), pid(), pid(), file:filename()) -> Result)) -> Result.
with_domains(Fun) ->
    Store = filename:join("/tmp", "hls-domain-reattach-" ++
        integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
        integer_to_list(erlang:unique_integer([positive]))),
    ok = hls_domain:create_store(Store),
    {ok, A} = hls_domain_async_fixture:start_link(self()), unlink(A),
    {ok, B} = hls_domain_async_fixture:start_link(self()), unlink(B),
    {ok, Owner} = hls_domain:start_link(#{a => automatic, b => manual},
        #{module => hls_domain_async_fixture, endpoints => #{a => A, b => B}, incarnation_file => Store}),
    unlink(Owner),
    try Fun(Owner, A, B, Store)
    after stop(Owner), stop(A), stop(B), file:delete(Store) end.

%% Teardown tolerates endpoints deliberately terminated during the witness.
-spec stop(pid()) -> ok.
stop(Pid) -> catch gen_server:stop(Pid), ok.
