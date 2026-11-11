-module(hls_domain_erts_tests).
-moduledoc "Finite ERTS domain witnesses: native actor failures, acknowledged replacement and silent setup.".
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% A native source exception retires its closed group while independent actors and explicit replacement remain usable.
-spec source_failure_retires_group_test() -> ok.
source_failure_retires_group_test() ->
    {ok, A} = hls_domain_erts:start_link(reply_spec([left, right])),
    {ok, B} = hls_domain_erts:start_link(reply_spec([independent])),
    try
        {ok, AuthorityA} = hls_domain_erts:attach(A, self()),
        {ok, AuthorityB} = hls_domain_erts:attach(B, self()),
        activate(A, AuthorityA, 1),
        activate(B, AuthorityB, 1),
        {ok, Left} = hls_domain_erts:endpoint(A, AuthorityA, 1, left),
        {ok, Right} = hls_domain_erts:endpoint(A, AuthorityA, 1, right),
        {ok, Independent} = hls_domain_erts:endpoint(B, AuthorityB, 1, independent),
        Pending = gen_server:send_request(Left, {wait, 17}),
        _ = hls_statem:info(Left),
        ok = hls_statem:cast(Left, {explode, 0}),
        ?assertMatch({error, {_, Left}}, gen_server:wait_response(Pending, 1000)),
        Failed = await(A, failed),
        ?assertEqual(#{}, maps:get(actors, Failed)),
        ?assertNot(is_process_alive(Left)),
        ?assertNot(is_process_alive(Right)),
        ?assertEqual({report, 0}, hls_statem:call(Independent, {read, 0})),
        ?assertEqual({error, not_ready_or_stale}, hls_domain_erts:endpoint(A, AuthorityA, 1, left)),
        Replace = #domain_input{op = replace, expected = 1, target = 2, transition = 2},
        ?assertMatch(#domain_output{status = accepted}, hls_domain_erts:request(A, AuthorityA, Replace)),
        New = await(A, ready),
        ?assertEqual(2, (maps:get(state, New))#domain_state.current),
        {ok, NewLeft} = hls_domain_erts:endpoint(A, AuthorityA, 2, left),
        ?assertNotEqual(Left, NewLeft),
        #{mailbox := #{generation := 2}} = hls_statem:info(NewLeft),
        ?assertEqual({report, 0}, hls_statem:call(NewLeft, {read, 0})),
        ?assertMatch(#domain_output{status = replay}, hls_domain_erts:request(A, AuthorityA, Replace)),
        {ok, Repeated} = hls_domain_erts:status(A),
        ?assertEqual(2, maps:get(reset_count, Repeated)),
        ?assertEqual({report, 0}, hls_statem:call(Independent, {read, 0}))
    after
        hls_domain_erts:stop(A),
        hls_domain_erts:stop(B)
    end.

%% A queued status request reconciles native actor death even when it precedes the backend DOWN signal.
-spec status_before_down_cannot_publish_dead_actor_test() -> ok.
status_before_down_cannot_publish_dead_actor_test() ->
    {ok, Backend} = hls_domain_erts:start_link(reply_spec([actor, peer])),
    try
        {ok, Authority} = hls_domain_erts:attach(Backend, self()),
        activate(Backend, Authority, 1),
        {ok, Actor} = hls_domain_erts:endpoint(Backend, Authority, 1, actor),
        {ok, Peer} = hls_domain_erts:endpoint(Backend, Authority, 1, peer),
        ok = sys:suspend(Backend),
        Request = gen_server:send_request(Backend, status),
        Monitor = monitor(process, Actor),
        exit(Actor, kill),
        receive {'DOWN', Monitor, process, Actor, killed} -> ok
        after 1000 -> error(actor_not_dead) end,
        ok = sys:resume(Backend),
        {reply, {ok, Snapshot}} = gen_server:wait_response(Request, 1000),
        ?assertEqual(failed, (maps:get(state, Snapshot))#domain_state.phase),
        ?assertEqual(#{}, maps:get(actors, Snapshot)),
        ?assertNot(is_process_alive(Peer)),
        ?assertEqual({error, not_ready_or_stale}, hls_domain_erts:endpoint(Backend, Authority, 1, actor)),
        ?assertEqual(1, maps:get(reset_count, Snapshot))
    after
        catch sys:resume(Backend),
        hls_domain_erts:stop(Backend)
    end.

%% Losing control authority retires endpoints without silently resetting or replacing their incarnation.
-spec owner_loss_fences_without_reset_test() -> ok.
owner_loss_fences_without_reset_test() ->
    {ok, Backend} = hls_domain_erts:start_link(reply_spec([actor])),
    Parent = self(),
    Owner = spawn(fun() ->
        {ok, Authority} = hls_domain_erts:attach(Backend, self()),
        activate(Backend, Authority, 1),
        {ok, Pid} = hls_domain_erts:endpoint(Backend, Authority, 1, actor),
        Parent ! {attached, self(), Pid},
        receive stop -> ok end
    end),
    try
        Actor = receive {attached, Owner, Pid} -> Pid after 3000 -> error(owner_start_timeout) end,
        ?assertEqual({error, owned}, hls_domain_erts:attach(Backend, self())),
        exit(Owner, kill),
        Failed = await(Backend, failed),
        ?assertEqual(1, maps:get(reset_count, Failed)),
        ?assertNot(is_process_alive(Actor)),
        ?assertEqual(#{}, maps:get(actors, Failed)),
        {ok, ReplacementAuthority} = hls_domain_erts:attach(Backend, self()),
        {ok, Before} = hls_domain_erts:status(Backend),
        ?assertEqual(failed, (maps:get(state, Before))#domain_state.phase),
        ?assertEqual(1, maps:get(reset_count, Before)),
        Replace = #domain_input{op = replace, expected = 1, target = 2, transition = 2},
        ?assertMatch(#domain_output{status = accepted},
            hls_domain_erts:request(Backend, ReplacementAuthority, Replace)),
        _ = await(Backend, ready),
        ok
    after
        exit(Owner, kill),
        hls_domain_erts:stop(Backend)
    end.

%% Authority cannot be transferred to another caller or used to manufacture a physical completion acknowledgement.
-spec owner_cannot_forge_completion_test() -> ok.
owner_cannot_forge_completion_test() ->
    {ok, Backend} = hls_domain_erts:start_link(reply_spec([actor])),
    try
        {ok, Authority} = hls_domain_erts:attach(Backend, self()),
        Forged = #domain_input{op = fenced, target = 1, transition = 1},
        ?assertEqual({error, backend_completion_only}, hls_domain_erts:request(Backend, Authority, Forged)),
        {ok, Snapshot} = hls_domain_erts:status(Backend),
        ?assertEqual(unbound, (maps:get(state, Snapshot))#domain_state.phase),
        Parent = self(),
        spawn(fun() -> Parent ! {unauthorized, hls_domain_erts:request(Backend, Authority, #domain_input{})} end),
        receive {unauthorized, Reply} -> ?assertEqual({error, unauthorized}, Reply)
        after 1000 -> error(no_authority_reply) end
    after hls_domain_erts:stop(Backend) end.

%% Effectful startup fails before any actor endpoint or external publication is admitted.
-spec setup_effects_reject_before_publication_test() -> ok.
setup_effects_reject_before_publication_test() ->
    Spec = #{actors => #{actor => #{module => hls_statem_event_fixture, mailbox_capacity => 4}},
        routes => #{actor => #{out => {external, self()}}}, startup => #{actor => [{start, 2}]}},
    {ok, Backend} = hls_domain_erts:start_link(Spec),
    try
        {ok, Authority} = hls_domain_erts:attach(Backend, self()),
        Request = #domain_input{op = activate, target = 1, transition = 1},
        ?assertMatch(#domain_output{status = accepted}, hls_domain_erts:request(Backend, Authority, Request)),
        Failed = await(Backend, failed),
        ?assertEqual(#{}, maps:get(actors, Failed)),
        ?assertEqual({error, not_ready_or_stale}, hls_domain_erts:endpoint(Backend, Authority, 1, actor)),
        receive {'$gen_cast', _} -> error(setup_published_effect) after 0 -> ok end
    after hls_domain_erts:stop(Backend) end.

%% A postponed startup message cannot be mistaken for completed initialization.
-spec setup_postponement_is_not_readiness_test() -> ok.
setup_postponement_is_not_readiness_test() ->
    Spec = #{actors => #{actor => #{module => hls_statem_event_fixture, mailbox_capacity => 4}},
        routes => #{actor => #{out => {external, self()}}}, startup => #{actor => [{later, 9}]}},
    {ok, Backend} = hls_domain_erts:start_link(Spec),
    try
        {ok, Authority} = hls_domain_erts:attach(Backend, self()),
        Request = #domain_input{op = activate, target = 1, transition = 1},
        ?assertMatch(#domain_output{status = accepted}, hls_domain_erts:request(Backend, Authority, Request)),
        Failed = await(Backend, failed),
        ?assertEqual(#{}, maps:get(actors, Failed))
    after hls_domain_erts:stop(Backend) end.

%% Admission acknowledges the finite private mailbox capacity without asserting a bounded outer BEAM mailbox.
-spec acknowledged_private_capacity_test() -> ok.
acknowledged_private_capacity_test() ->
    {ok, Actor} = hls_statem:start_link(hls_statem_event_fixture, [], [{mailbox_capacity, 1}, {generation, 7}]),
    try
        ?assertEqual({error, busy}, hls_statem:admit_cast(Actor, {later, 1})),
        ok = hls_statem:setup(Actor, #{out => self()}, []),
        ?assertEqual(ok, hls_statem:admit_cast(Actor, {later, 1})),
        ?assertEqual({error, busy}, hls_statem:admit_cast(Actor, {later, 2})),
        #{mailbox := #{generation := 7, occupied := 1}, postponed := 1} = hls_statem:info(Actor),
        ?assert(is_process_alive(Actor))
    after hls_statem:stop(Actor) end.

%% Setup cannot adopt ordinary queued work as an initialization sequence.
-spec setup_does_not_reinterpret_queued_input_test() -> ok.
setup_does_not_reinterpret_queued_input_test() ->
    {ok, Actor} = hls_statem:start_link(hls_statem_event_fixture, [], [{mailbox_capacity, 2}]),
    try
        hls_statem:cast(Actor, {later, 1}),
        ?assertEqual({error, setup_not_idle}, hls_statem:setup(Actor, #{out => self()}, [])),
        #{lifecycle := disconnected, mailbox := #{occupied := 1}} = hls_statem:info(Actor),
        ok
    after hls_statem:stop(Actor) end.

%% Give each fixed actor a distinct state machine and a test-observer reply endpoint.
-spec reply_spec([atom()]) -> hls_domain_erts:specification().
reply_spec(Ids) ->
    #{actors => maps:from_list([{Id, #{module => hls_statem_reply_fixture, mailbox_capacity => 4}} || Id <- Ids]),
      routes => maps:from_list([{Id, #{reply => {external, self()}}} || Id <- Ids]), startup => #{}}.

%% Request the first incarnation and wait only for actual ready evidence.
-spec activate(pid(), hls_domain_backend:authority(), hls_nums:u64()) -> ok.
activate(Backend, Authority, Target) ->
    Request = #domain_input{op = activate, target = Target, transition = Target},
    ?assertMatch(#domain_output{status = accepted}, hls_domain_erts:request(Backend, Authority, Request)),
    _ = await(Backend, ready),
    ok.

%% Bound the test observation interval without treating expiration as completion.
-spec await(pid(), hls_domain_lifecycle:phase()) -> hls_domain_erts:snapshot().
await(Backend, Phase) -> await(Backend, Phase, erlang:monotonic_time(millisecond) + 3000).

%% Inspect the actual backend until the named phase or the finite test deadline.
-spec await(pid(), hls_domain_lifecycle:phase(), integer()) -> hls_domain_erts:snapshot().
await(Backend, Phase, Deadline) ->
    {ok, Snapshot = #{state := State}} = hls_domain_erts:status(Backend),
    case State#domain_state.phase of
        Phase -> Snapshot;
        _ ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> receive after 1 -> await(Backend, Phase, Deadline) end;
                false -> error({domain_phase_timeout, Phase, Snapshot})
            end
    end.
