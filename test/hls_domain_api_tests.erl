-module(hls_domain_api_tests).
-moduledoc "Finite native witnesses for prepared OTP startup and confirmed public stop.".
-include_lib("eunit/include/eunit.hrl").

%% A retained child specification admits one incarnation; external preparation is not an OTP restart callback.
-spec prepared_child_spec_is_single_use_test() -> ok.
prepared_child_spec_is_single_use_test() ->
    fixture(fun(Owner) ->
        {ok, Startup} = hls_domain_instance:prepare(Owner, compute),
        Child = start(Startup),
        {ok, #{handle := Old}} = hls_domain_instance:await_ready(Child, 2000),
        {ok, Actor} = hls_domain_instance:resolve(Child, actor),
        ok = hls_statem:admit_cast(Actor, {add, 17}),
        ?assertEqual({readout, 17}, hls_statem:call(Actor, {get, 0})),
        ok = gen_server:stop(Child, shutdown, 2000),
        ok = hls_domain:stop(Owner, Old, 2000),
        ?assertNot(is_process_alive(Actor)),
        Reused = start(Startup),
        ?assertMatch({error, _}, hls_domain_instance:await_ready(Reused, 2000)),
        {ok, NextStartup} = hls_domain_instance:prepare(Owner, compute),
        Next = start(NextStartup),
        {ok, #{handle := New}} = hls_domain_instance:await_ready(Next, 2000),
        ?assertNotEqual(Old, New),
        ok = gen_server:stop(Next, shutdown, 2000),
        ok = hls_domain:stop(Owner, compute, 2000)
    end).

%% A stale exact stop may neither cancel the successor's prepared startup nor stop its actors.
-spec stale_stop_preserves_successor_startup_test() -> ok.
stale_stop_preserves_successor_startup_test() ->
    fixture(fun(Owner) ->
        {ok, First} = hls_domain_instance:prepare(Owner, compute),
        A = start(First),
        {ok, #{handle := Old}} = hls_domain_instance:await_ready(A, 2000),
        ok = gen_server:stop(A, shutdown, 2000),
        {ok, Second} = hls_domain_instance:prepare(Owner, compute),
        B = start(Second),
        {ok, #{handle := Current = {compute, NewID}}} = hls_domain_instance:await_ready(B, 2000),
        {compute, OldID} = Old,
        ?assertEqual({error, {incarnation_changed, OldID, NewID}}, hls_domain:stop(Owner, Old, 1000)),
        ?assertMatch({ok, #{phase := ready, handle := Current}}, hls_domain:status(Owner, compute)),
        ok = gen_server:stop(B, shutdown, 2000),
        {ok, Third} = hls_domain_instance:prepare(Owner, compute),
        ?assertEqual({error, {incarnation_changed, OldID, NewID}}, hls_domain:stop(Owner, Old, 1000)),
        C = start(Third),
        ?assertMatch({ok, #{phase := ready}}, hls_domain_instance:await_ready(C, 2000)),
        ok = gen_server:stop(C, shutdown, 2000)
    end).

%% Unused preparation is revoked by either the selected current lifetime or a matching exact handle.
-spec confirmed_stop_revokes_unused_startup_test() -> ok.
confirmed_stop_revokes_unused_startup_test() ->
    fixture(fun(Owner) ->
        {ok, Cancelled} = hls_domain_instance:prepare(Owner, compute),
        ok = hls_domain:stop(Owner, compute, 1000),
        Rejected = start(Cancelled),
        ?assertMatch({error, _}, hls_domain_instance:await_ready(Rejected, 2000)),
        {ok, Fresh} = hls_domain_instance:prepare(Owner, compute),
        Child = start(Fresh),
        {ok, #{handle := Handle}} = hls_domain_instance:await_ready(Child, 2000),
        ok = gen_server:stop(Child, shutdown, 2000),
        {ok, CancelledAgain} = hls_domain_instance:prepare(Owner, compute),
        ok = hls_domain:stop(Owner, Handle, 1000),
        RejectedAgain = start(CancelledAgain),
        ?assertMatch({error, _}, hls_domain_instance:await_ready(RejectedAgain, 2000)),
        ?assertEqual({error, unknown_domain}, hls_domain:stop(Owner, missing, 1000))
    end).

%% The owner cannot follow a leaked prepared descriptor into another owner's identity space.
-spec owner_death_invalidates_prepared_startup_test() -> ok.
owner_death_invalidates_prepared_startup_test() ->
    fixture(fun(Owner) ->
        {ok, Startup} = hls_domain_instance:prepare(Owner, compute),
        ok = gen_server:stop(Owner),
        Rejected = start(Startup),
        ?assertMatch({error, _}, hls_domain_instance:await_ready(Rejected, 1000))
    end).

%% Readiness is asynchronous even for rejected descriptor reuse; unlink before observing failure.
-spec start(hls_domain_instance:startup()) -> pid().
start(Startup) ->
    {ok, Child} = hls_domain_instance:start_link(Startup),
    unlink(Child), Child.

%% A real source actor exercises the public facade, adapter and native backend together.
-spec fixture(fun((pid()) -> term())) -> ok.
fixture(Fun) ->
    Store = filename:join("/tmp", "hls-domain-api-" ++ integer_to_list(erlang:unique_integer([positive, monotonic]))),
    ok = hls_domain_counter:create(Store),
    {ok, Backend} = hls_domain_erts:start_link(#{actors => #{actor => #{module => hls_domain_actor_fixture, mailbox_capacity => 4}}}),
    unlink(Backend),
    {ok, Owner} = hls_domain:start_link(#{compute => manual}, #{module => hls_domain_erts, endpoints => #{compute => Backend}, incarnation_file => Store}),
    unlink(Owner),
    try Fun(Owner), ok
    after
        _ = catch gen_server:stop(Owner),
        _ = catch gen_server:stop(Backend),
        file:delete(Store)
    end.
