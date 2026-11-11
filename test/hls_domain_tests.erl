-module(hls_domain_tests).
-include_lib("eunit/include/eunit.hrl").

%% Whole-domain replacement reconnects source routes and preserves an independent domain.
-spec explicit_activation_and_independent_replacement_test() -> ok.
explicit_activation_and_independent_replacement_test() ->
    with_domains(fun(Owner, A, _B, _Store) ->
        ?assertMatch({ok, #{phase := unbound}}, hls_domain:status(Owner, a)),
        ?assertEqual({error, not_ready}, hls_domain:resolve(Owner, a, source)),
        {ok, _} = hls_domain:activate(Owner, a),
        {ok, _} = hls_domain:activate(Owner, b),
        #{handle := OldA} = ready(Owner, a),
        #{handle := OldB} = ready(Owner, b),
        {ok, Source} = hls_domain:resolve(Owner, OldA, source),
        {ok, Sink} = hls_domain:resolve(Owner, OldA, sink),
        {ok, Independent} = hls_domain:resolve(Owner, OldB, source),
        ok = hls_statem:admit_cast(Source, {forward, 7}),
        wait_value(Sink, 7),
        ok = hls_statem:admit_cast(Independent, {add, 11}),
        ?assertEqual({readout, 11}, hls_statem:call(Independent, {get, 0})),
        {ok, Before} = hls_domain_erts:status(A),
        {ok, _} = hls_domain:replace(Owner, OldA),
        #{handle := NewA} = ready(Owner, a),
        ?assertNotEqual(OldA, NewA),
        ?assertNot(is_process_alive(Source)),
        ?assertNot(is_process_alive(Sink)),
        ?assertEqual({error, not_ready}, hls_domain:resolve(Owner, OldA, source)),
        {ok, NewSink} = hls_domain:resolve(Owner, NewA, sink),
        ?assertEqual({readout, 0}, hls_statem:call(NewSink, {get, 0})),
        ?assertEqual({ok, Independent}, hls_domain:resolve(Owner, OldB, source)),
        ?assertEqual({readout, 11}, hls_statem:call(Independent, {get, 0})),
        {ok, _} = hls_domain:replace(Owner, OldA),
        {ok, After} = hls_domain_erts:status(A),
        ?assertEqual(maps:get(reset_count, Before) + 1, maps:get(reset_count, After))
    end).

%% Replaying a completed transition returns complete endpoint evidence for supervisor binding.
-spec completed_transition_replay_retains_ready_actors_test() -> ok.
completed_transition_replay_retains_ready_actors_test() ->
    with_domains(fun(Owner, _A, _B, _Store) ->
        {ok, _} = hls_domain:activate(Owner, a),
        #{handle := Old, actors := InitialActors} = ready(Owner, a),
        ?assertEqual(2, map_size(InitialActors)),
        ?assertMatch({ok, #{phase := ready, handle := Old, actors := InitialActors}},
            hls_domain:activate(Owner, a)),
        {ok, _} = hls_domain:replace(Owner, Old),
        #{handle := New, actors := NewActors} = ready(Owner, a),
        ?assertNotEqual(Old, New),
        ?assertNotEqual(InitialActors, NewActors),
        ?assertMatch({ok, #{phase := ready, handle := New, actors := NewActors}},
            hls_domain:replace(Owner, Old))
    end).

%% A delayed observation cannot silently move a bound instance to its replacement.
-spec instance_does_not_follow_replacement_test() -> ok.
instance_does_not_follow_replacement_test() ->
    with_domains(fun(Owner, _A, _B, _Store) ->
        {ok, Child} = hls_domain_instance:start_link(Owner, a),
        unlink(Child),
        try
            {ok, _Actor} = instance_actor(Child, source, 200),
            #{handle := Old} = hls_domain_instance:status(Child),
            {monitors, Before} = process_info(Child, monitors),
            Child ! observe,
            ?assertMatch(#{phase := ready, handle := Old}, hls_domain_instance:status(Child)),
            ?assertEqual({monitors, Before}, process_info(Child, monitors)),
            %% Queue the observation ahead of the old actor DOWN messages deterministically.
            ok = sys:suspend(Child),
            Child ! observe,
            {ok, _} = hls_domain:replace(Owner, Old),
            #{handle := New} = ready(Owner, a),
            Monitor = monitor(process, Child),
            ok = sys:resume(Child),
            receive
                {'DOWN', Monitor, process, Child, {domain_replaced, Old, New}} -> ok
            after 1000 -> error(instance_followed_replacement)
            end
        after
            catch sys:resume(Child),
            stop(Child)
        end
    end).

%% A lost caller response must observe the same retained replacement, never another reset.
-spec lost_reply_does_not_repeat_reset_test() -> ok.
lost_reply_does_not_repeat_reset_test() ->
    with_domains(fun(Owner, A, _B, _Store) ->
        {ok, _} = hls_domain:activate(Owner, a),
        #{handle := {a, Activation} = Old} = ready(Owner, a),
        {ok, Before} = hls_domain_erts:status(A),
        _ = catch gen_server:call(Owner, {replace, a, Activation}, 0),
        {ok, Retried} = hls_domain:replace(Owner, Old),
        #{handle := {a, Target}} = ready(Owner, a),
        ?assertEqual(Target, maps:get(target, Retried)),
        {ok, After} = hls_domain_erts:status(A),
        ?assertEqual(maps:get(reset_count, Before) + 1, maps:get(reset_count, After))
    end).

%% Entry failure preserves earlier effects but discards its own proposed publication.
-spec failure_does_not_publish_computed_effects_or_replay_retained_calls_test() -> ok.
failure_does_not_publish_computed_effects_or_replay_retained_calls_test() ->
    with_domains(fun(Owner, _A, _B, _Store) ->
        {ok, _} = hls_domain:activate(Owner, a),
        {ok, _} = hls_domain:activate(Owner, b),
        #{handle := Old} = ready(Owner, a),
        ready(Owner, b),
        {ok, Sink} = hls_domain:resolve(Owner, Old, sink),
        {ok, Independent} = hls_domain:resolve(Owner, b, source),
        Hold = gen_server:send_request(Sink, {hold, 0}),
        %% Same-sender admission orders this effect after the retained request.
        ok = hls_statem:admit_cast(Sink, {forward, 7}),
        receive {'$gen_cast', {add, 7}} -> ok after 1000 -> error(missing_prior_effect) end,
        Ref = monitor(process, Sink),
        ok = hls_statem:cast(Sink, {explode, 1}),
        receive {'DOWN', Ref, process, Sink, _} -> ok after 1000 -> error(no_source_failure) end,
        receive {'$gen_cast', {add, 999}} -> error(failed_entry_published) after 0 -> ok end,
        wait_phase(Owner, a, failed),
        ?assertMatch({error, _}, gen_server:receive_response(Hold, 1000)),
        ?assertEqual({readout, 0}, hls_statem:call(Independent, {get, 0})),
        {ok, _} = hls_domain:replace(Owner, Old),
        ready(Owner, a),
        {ok, NewSink} = hls_domain:resolve(Owner, a, sink),
        ?assertEqual({readout, 0}, hls_statem:call(NewSink, {get, 0}))
    end).

%% Persistent identity allocation is exclusive and refuses wrap after owner restart.
-spec store_exhaustion_and_exclusive_ownership_test() -> ok.
store_exhaustion_and_exclusive_ownership_test() ->
    with_domains(fun(Owner, A, B, Store) ->
        ?assertEqual(undefined, global:whereis_name({hls_domain, filename:absname(Store)})),
        ?assertEqual({error, eexist}, hls_domain:create_store(Store)),
        ?assertMatch({error, activation_store_owned},
            hls_domain:start_link(#{a => automatic, b => manual}, backend(A, B, Store))),
        {ok, _} = hls_domain:activate(Owner, a),
        #{handle := Old} = ready(Owner, a),
        stop(Owner),
        ok = file:write_file(Store, <<((1 bsl 64) - 1):64>>),
        {ok, NextOwner} = hls_domain:start_link(#{a => automatic, b => manual}, backend(A, B, Store)),
        unlink(NextOwner),
        try ?assertEqual({error, activation_exhausted}, hls_domain:replace(NextOwner, Old))
        after stop(NextOwner) end
    end).

%% Aliasing automatic and manual domain names cannot bypass either isolation or reset policy.
-spec duplicate_domain_controllers_reject_test() -> ok.
duplicate_domain_controllers_reject_test() ->
    Previous = process_flag(trap_exit, true),
    Store = filename:join("/tmp", "hls-domain-alias-" ++ integer_to_list(erlang:system_time(nanosecond)) ++
        "-" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = hls_domain:create_store(Store),
    {ok, Controller} = hls_domain_erts:start_link(spec()),
    unlink(Controller),
    Result = hls_domain:start_link(#{a => automatic, b => manual}, backend(Controller, Controller, Store)),
    try
        ?assertEqual({error, invalid_domain_catalog}, Result),
        ?assertMatch({ok, #{reset_count := 0, actors := #{}}}, hls_domain_erts:status(Controller)),
        %% Rejection occurs before taking any controller authority or burning an identity.
        ?assertMatch({ok, _}, hls_domain_erts:attach(Controller, self())),
        ?assertEqual({ok, <<0:64>>}, file:read_file(Store))
    after
        case Result of {ok, LeakedOwner} -> unlink(LeakedOwner), stop(LeakedOwner); _ -> ok end,
        stop(Controller),
        file:delete(Store),
        process_flag(trap_exit, Previous)
    end.

%% A supervisor child cannot turn a manual deployment policy into reset permission.
-spec manual_policy_is_not_an_automatic_reset_permission_test() -> ok.
manual_policy_is_not_an_automatic_reset_permission_test() ->
    with_domains(fun(Owner, _A, B, _Store) ->
        Previous = process_flag(trap_exit, true),
        try
            {ok, Child} = hls_domain_instance:start_link(Owner, b),
            receive {'EXIT', Child, manual_replacement_required} -> ok
            after 1000 -> error(manual_policy_ignored) end
        after process_flag(trap_exit, Previous) end,
        ?assertMatch({ok, #{reset_count := 0}}, hls_domain_erts:status(B))
    end).

%% Ordinary OTP restart replaces failed actors, but a lost host representative only reattaches.
-spec supervisor_replaces_failed_domain_but_attaches_after_representative_loss_test() -> ok.
supervisor_replaces_failed_domain_but_attaches_after_representative_loss_test() ->
    with_domains(fun(Owner, A, _B, _Store) ->
        {ok, _} = hls_domain:activate(Owner, b),
        #{handle := OtherHandle} = ready(Owner, b),
        {ok, Other} = hls_domain:resolve(Owner, OtherHandle, source),
        {ok, Supervisor} = hls_domain_supervisor_fixture:start_link(Owner, a),
        unlink(Supervisor),
        try
            #{handle := OldHandle} = ready(Owner, a),
            Child = instance_child(Supervisor, none, 200),
            {ok, OldActor} = instance_actor(Child, source, 200),
            Child ! {'DOWN', make_ref(), process, self(), stale_notification},
            ?assertMatch(#{phase := ready}, hls_domain_instance:status(Child)),
            {ok, Before} = hls_domain_erts:status(A),
            exit(Child, kill),
            AttachedChild = instance_child(Supervisor, Child, 200),
            ?assertEqual({ok, OldActor}, instance_actor(AttachedChild, source, 200)),
            {ok, Reattached} = hls_domain_erts:status(A),
            ?assertEqual(maps:get(reset_count, Before), maps:get(reset_count, Reattached)),
            ok = hls_statem:cast(OldActor, {explode, 0}),
            ReplacementChild = instance_child(Supervisor, AttachedChild, 200),
            {ok, NewActor} = instance_actor(ReplacementChild, source, 200),
            ?assertNotEqual(OldActor, NewActor),
            ?assertNotEqual(OldHandle, maps:get(handle, hls_domain_instance:status(ReplacementChild))),
            ?assertEqual({ok, Other}, hls_domain:resolve(Owner, OtherHandle, source)),
            {ok, After} = hls_domain_erts:status(A),
            ?assertEqual(maps:get(reset_count, Before) + 1, maps:get(reset_count, After))
        after stop(Supervisor) end
    end).

%% Observe a distinct permanent child within a bounded test interval.
-spec instance_child(pid(), none | pid(), non_neg_integer()) -> pid().
instance_child(_Supervisor, _Previous, 0) -> error(no_supervised_child);
instance_child(Supervisor, Previous, Left) ->
    case supervisor:which_children(Supervisor) of
        [{instance, Pid, worker, _}] when is_pid(Pid), Pid =/= Previous -> Pid;
        _ -> receive after 5 -> instance_child(Supervisor, Previous, Left - 1) end
    end.

%% Child startup is asynchronous; wait for its captured ready incarnation.
-spec instance_actor(pid(), term(), non_neg_integer()) -> {ok, pid()}.
instance_actor(_Child, _Actor, 0) -> error(instance_not_ready);
instance_actor(Child, Actor, Left) ->
    case hls_domain_instance:resolve(Child, Actor) of
        {ok, _} = Result -> Result;
        {error, not_ready} -> receive after 5 -> instance_actor(Child, Actor, Left - 1) end
    end.

%% Own isolated native backends and an exclusive temporary store for each witness.
-spec with_domains(fun((pid(), pid(), pid(), file:filename()) -> Result)) -> Result.
with_domains(Fun) ->
    Previous = process_flag(trap_exit, true),
    Store = filename:join("/tmp", "hls-domain-" ++ integer_to_list(erlang:system_time(nanosecond)) ++
        "-" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = hls_domain:create_store(Store),
    {ok, A} = hls_domain_erts:start_link(spec()), unlink(A),
    {ok, B} = hls_domain_erts:start_link(spec()), unlink(B),
    {ok, Owner} = hls_domain:start_link(#{a => automatic, b => manual}, backend(A, B, Store)), unlink(Owner),
    try Fun(Owner, A, B, Store)
    after stop(Owner), stop(A), stop(B), file:delete(Store), process_flag(trap_exit, Previous) end.

%% Both domains use the same backend API, with distinct mutable actor state.
-spec backend(pid(), pid(), file:filename()) -> hls_domain:backend().
backend(A, B, Store) ->
    #{module => hls_domain_erts, endpoints => #{a => A, b => B}, activation_file => Store}.

%% Connect the source to its sink and the sink's output to the test observer.
-spec spec() -> hls_domain_erts:specification().
spec() ->
    Actor = #{module => hls_domain_actor_fixture, mailbox_capacity => 4},
    #{actors => #{source => Actor, sink => Actor},
        routes => #{source => #{out => {actor, sink}, reply => {external, self()}},
            sink => #{out => {external, self()}, reply => {external, self()}}}, startup => #{}}.

%% Readiness is backend evidence, never an elapsed-time guess.
-spec ready(pid(), atom()) -> hls_domain:snapshot().
ready(Owner, Domain) -> wait_phase(Owner, Domain, ready).

%% Bound observation of one requested lifecycle phase.
-spec wait_phase(pid(), atom(), atom()) -> hls_domain:snapshot().
wait_phase(Owner, Domain, Phase) -> wait_phase(Owner, Domain, Phase, 200).
%% Each poll inspects the surviving deployment owner.
-spec wait_phase(pid(), atom(), atom(), non_neg_integer()) -> hls_domain:snapshot().
wait_phase(_Owner, _Domain, Phase, 0) -> error({phase_timeout, Phase});
wait_phase(Owner, Domain, Phase, Left) ->
    case hls_domain:status(Owner, Domain) of
        {ok, #{phase := Phase} = Status} -> Status;
        _ -> receive after 5 -> wait_phase(Owner, Domain, Phase, Left - 1) end
    end.

%% Wait for cross-actor source effects to reach the receiver, retaining its public call path.
-spec wait_value(pid(), non_neg_integer()) -> ok.
wait_value(Pid, Value) -> wait_value(Pid, Value, 200).
%% Reject missing progress after the test's finite observation budget.
-spec wait_value(pid(), non_neg_integer(), non_neg_integer()) -> ok.
wait_value(_Pid, Value, 0) -> error({value_timeout, Value});
wait_value(Pid, Value, Left) ->
    case hls_statem:call(Pid, {get, 0}) of
        {readout, Value} -> ok;
        _ -> receive after 5 -> wait_value(Pid, Value, Left - 1) end
    end.

%% Cleanup accepts actors already retired by the failure under test.
-spec stop(pid()) -> term().
stop(Pid) -> case is_process_alive(Pid) of true -> catch gen_server:stop(Pid); false -> ok end.
