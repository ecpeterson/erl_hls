-module(hls_recovery_profile_tests).
-moduledoc "Finite recovery-interface witnesses using source actors and native ERTS; no physical-device or logical-error-correction claim.".
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").
-include("hls_recovery_profile.hrl").

%% A single profile request survives repetition, rejects conflicts and emits exactly one observed digital effect.
-spec bounded_profile_protocol_test() -> ok.
bounded_profile_protocol_test() ->
    {Backend, Authority, Actor, Policy} = start(),
    try
        ?assertMatch(#profile_status{status = ?PROFILE_UNKNOWN, epoch = 0},
            hls_recovery_policy_fixture:observe(Policy, 1, 0)),
        ?assertMatch(#profile_status{status = ?PROFILE_INVALID},
            hls_recovery_policy_fixture:select(Policy, 9, 0, 2)),
        ?assertMatch(#profile_status{status = ?PROFILE_PENDING, epoch = 0},
            hls_recovery_policy_fixture:select(Policy, 1, 0, 1)),
        ?assertMatch(#profile_status{status = ?PROFILE_PENDING, epoch = 0},
            hls_recovery_policy_fixture:select(Policy, 1, 0, 1)),
        ?assertMatch(#profile_status{status = ?PROFILE_INVALID},
            hls_recovery_policy_fixture:select(Policy, 1, 0, 0)),
        ?assertMatch(#profile_status{status = ?PROFILE_BUSY},
            hls_recovery_policy_fixture:select(Policy, 2, 0, 0)),
        ok = hls_recovery_policy_fixture:apply_profile(Policy, 1, 0),
        ?assertMatch(#profile_applied{request = 1, epoch = 1, profile = 1, enabled = 16#fe}, effect()),
        ?assertMatch(#profile_status{status = ?PROFILE_APPLIED, epoch = 1, enabled = 16#fe},
            hls_recovery_policy_fixture:select(Policy, 1, 0, 1)),
        ok = hls_recovery_policy_fixture:apply_profile(Policy, 1, 0),
        %% The direct reply follows all earlier effects from this actor to this observer.
        ?assertMatch(#profile_status{status = ?PROFILE_APPLIED},
            hls_statem:call(Actor, #query_profile{request = 1, epoch = 0})),
        no_effect(),
        ?assertMatch(#profile_status{status = ?PROFILE_STALE},
            hls_recovery_policy_fixture:select(Policy, 2, 0, 0)),
        ?assertMatch(#profile_status{status = ?PROFILE_PENDING, epoch = 1},
            hls_recovery_policy_fixture:select(Policy, 2, 1, 0)),
        ?assertMatch(#profile_status{status = ?PROFILE_UNKNOWN, epoch = 1},
            hls_recovery_policy_fixture:observe(Policy, 1, 0)),
        ok = hls_recovery_policy_fixture:apply_profile(Policy, 2, 1),
        ?assertMatch(#profile_applied{request = 2, epoch = 2, profile = 0, enabled = 0}, effect()),
        {ok, Snapshot} = hls_domain_erts:status(Backend),
        ?assertEqual(1, maps:get(reset_count, Snapshot)),
        ?assertMatch({ok, Actor}, hls_domain_erts:endpoint(Backend, Authority, 1, actuator))
    after stop(Backend, Policy) end.

%% A delayed trigger cannot apply a newer transition which happens to reuse its request ID.
-spec stale_apply_cannot_follow_reused_request_test() -> ok.
stale_apply_cannot_follow_reused_request_test() ->
    {Backend, _Authority, Actor, Policy} = start(),
    try
        ?assertMatch(#profile_status{status = ?PROFILE_PENDING},
            hls_recovery_policy_fixture:select(Policy, 1, 0, 1)),
        ok = hls_recovery_policy_fixture:apply_profile(Policy, 1, 0),
        ?assertMatch(#profile_applied{request = 1, epoch = 1}, effect()),
        ?assertMatch(#profile_status{status = ?PROFILE_PENDING},
            hls_recovery_policy_fixture:select(Policy, 2, 1, 0)),
        ok = hls_recovery_policy_fixture:apply_profile(Policy, 2, 1),
        ?assertMatch(#profile_applied{request = 2, epoch = 2}, effect()),
        ?assertMatch(#profile_status{status = ?PROFILE_PENDING, epoch = 2},
            hls_recovery_policy_fixture:select(Policy, 1, 2, 1)),
        %% This is the original request's delayed trigger, not authorization for epoch 2.
        ok = hls_recovery_policy_fixture:apply_profile(Policy, 1, 0),
        ?assertMatch(#profile_status{status = ?PROFILE_PENDING, epoch = 2, profile = 0},
            hls_statem:call(Actor, #query_profile{request = 1, epoch = 2})),
        no_effect(),
        ?assertMatch(#profile_status{status = ?PROFILE_INVALID, epoch = 2},
            hls_recovery_policy_fixture:select(Policy, 1, 0, 1)),
        ?assertMatch(#profile_status{status = ?PROFILE_UNKNOWN},
            hls_recovery_policy_fixture:observe(Policy, 1, 0)),
        ?assertMatch(#profile_status{status = ?PROFILE_PENDING},
            hls_recovery_policy_fixture:observe(Policy, 1, 2)),
        ok = hls_recovery_policy_fixture:apply_profile(Policy, 1, 2),
        ?assertMatch(#profile_applied{request = 1, epoch = 3, profile = 1}, effect())
    after stop(Backend, Policy) end.

%% Only selected input dependencies invalidate the logical result; late faults do not undo an applied effect.
-spec conditional_validity_is_not_digital_completion_test() -> ok.
conditional_validity_is_not_digital_completion_test() ->
    {Backend, _Authority, Actor, Policy} = start(),
    try
        ok = hls_recovery_policy_fixture:result(Policy, common, {ok, 1}),
        ok = hls_recovery_policy_fixture:result(Policy, deferred, {error, missing}),
        ok = hls_recovery_policy_fixture:branch(Policy, simple),
        ?assertMatch(#{logical := {ok, 1}}, hls_recovery_policy_fixture:status(Policy)),
        ok = hls_recovery_policy_fixture:branch(Policy, extended),
        ?assertMatch(#{logical := unavailable}, hls_recovery_policy_fixture:status(Policy)),
        ok = hls_recovery_policy_fixture:result(Policy, deferred, {ok, 0}),
        ?assertMatch(#{logical := {ok, 1}}, hls_recovery_policy_fixture:status(Policy)),
        ?assertMatch(#profile_status{status = ?PROFILE_PENDING},
            hls_recovery_policy_fixture:select(Policy, 1, 0, 1)),
        ok = hls_recovery_policy_fixture:apply_profile(Policy, 1, 0),
        ?assertMatch(#profile_applied{request = 1, epoch = 1}, effect()),
        %% Late evidence invalidates a required result; the already accepted effect is not undone.
        ok = hls_recovery_policy_fixture:result(Policy, common, {error, late_fault}),
        ?assertMatch(#{control := available, logical := unavailable, held := 16#ff},
            hls_recovery_policy_fixture:status(Policy)),
        ?assertMatch(#profile_status{status = ?PROFILE_APPLIED, epoch = 1, profile = 1},
            hls_statem:call(Actor, #query_profile{request = 1, epoch = 0})),
        no_effect()
    after stop(Backend, Policy) end.

%% Replacing a failed controller neither releases its host reservation nor silently rebinds an application operation.
-spec controller_replacement_does_not_release_resources_test() -> ok.
controller_replacement_does_not_release_resources_test() ->
    {Backend, Authority, Actor, Policy} = start(),
    try
        ?assertEqual({error, occupied}, hls_recovery_policy_fixture:reserve(Policy, 1)),
        ?assertMatch(#profile_status{status = ?PROFILE_PENDING},
            hls_recovery_policy_fixture:select(Policy, 1, 0, 1)),
        ok = hls_recovery_policy_fixture:apply_profile(Policy, 1, 0),
        ?assertMatch(#profile_applied{request = 1, epoch = 1, enabled = 16#fe}, effect()),
        Monitor = monitor(process, Actor),
        ?assertMatch({'EXIT', _}, (catch hls_statem:admit_cast(Actor, #controller_failure{reason = 1}))),
        receive {'DOWN', Monitor, process, Actor, _} -> ok after 1000 -> error(actor_not_retired) end,
        _ = await_phase(Backend, failed),
        await_control_loss(Policy, erlang:monotonic_time(millisecond) + 1000),
        ?assertEqual({error, occupied}, hls_recovery_policy_fixture:reserve(Policy, 1)),
        ?assertMatch(#{held := 16#ff}, hls_recovery_policy_fixture:status(Policy)),
        Replace = #domain_input{op = replace, expected = 1, target = 2, transition = 2},
        ?assertMatch(#domain_output{status = accepted}, hls_domain_erts:request(Backend, Authority, Replace)),
        _ = await_phase(Backend, ready),
        {ok, Replacement} = hls_domain_erts:endpoint(Backend, Authority, 2, actuator),
        ?assertNotEqual(Actor, Replacement),
        ?assertEqual({error, not_ready_or_stale}, hls_domain_erts:endpoint(Backend, Authority, 1, actuator)),
        ?assertEqual({error, unavailable}, hls_recovery_policy_fixture:select(Policy, 2, 1, 0)),
        ?assertEqual({error, occupied}, hls_recovery_policy_fixture:reserve(Policy, 16#ff)),
        %% New controller state cannot reconstruct the physical outcome of its predecessor.
        ?assertMatch(#profile_status{status = ?PROFILE_UNKNOWN, epoch = 0},
            hls_statem:call(Replacement, #query_profile{request = 1, epoch = 0})),
        no_effect(),
        {ok, Snapshot} = hls_domain_erts:status(Backend),
        ?assertEqual(2, maps:get(reset_count, Snapshot))
    after stop(Backend, Policy) end.

%% This checks source admissibility, separately from the ERTS interface histories above.
-spec source_actuator_is_lowerable_test() -> ok.
source_actuator_is_lowerable_test() ->
    Generated = iolist_to_binary(xls_parse:to_xls("apps/hls_fabric/test/hls_recovery_actuator_fixture.erl")),
    ?assert(byte_size(Generated) > 0).

%% Activate a real source controller and attach a separate host policy to its exact native endpoint.
-spec start() -> {pid(), hls_domain_backend:authority(), pid(), pid()}.
start() ->
    Spec = #{actors => #{actuator => #{module => hls_recovery_actuator_fixture, mailbox_capacity => 4}},
        routes => #{actuator => #{effect => {external, self()}, reply => {external, self()}}}, startup => #{}},
    {ok, Backend} = hls_domain_erts:start_link(Spec),
    {ok, Authority} = hls_domain_erts:attach(Backend, self()),
    Request = #domain_input{op = activate, target = 1, transition = 1},
    ?assertMatch(#domain_output{status = accepted}, hls_domain_erts:request(Backend, Authority, Request)),
    _ = await_phase(Backend, ready),
    {ok, Actor} = hls_domain_erts:endpoint(Backend, Authority, 1, actuator),
    {ok, Policy} = hls_recovery_policy_fixture:start_link(Actor),
    {Backend, Authority, Actor, Policy}.

%% Retire policy and controller processes after a completed finite witness.
-spec stop(pid(), pid()) -> ok.
stop(Backend, Policy) ->
    hls_recovery_policy_fixture:stop(Policy),
    hls_domain_erts:stop(Backend).

%% Observe one actuator output within the test budget.
-spec effect() -> #profile_applied{}.
effect() ->
    receive {'$gen_cast', Event = #profile_applied{}} -> Event
    after 1000 -> error(missing_profile_effect) end.

%% Reject duplicate publication after an ordering barrier from the same source actor.
-spec no_effect() -> ok.
no_effect() ->
    receive {'$gen_cast', #profile_applied{}} -> error(unexpected_profile_replay)
    after 0 -> ok end.

%% Bound observation of the actual lifecycle controller.
-spec await_phase(pid(), hls_domain_lifecycle:phase()) -> hls_domain_erts:snapshot().
await_phase(Backend, Phase) ->
    await_phase(Backend, Phase, erlang:monotonic_time(millisecond) + 3000).

%% Require named phase evidence rather than inferring readiness from elapsed time.
-spec await_phase(pid(), hls_domain_lifecycle:phase(), integer()) -> hls_domain_erts:snapshot().
await_phase(Backend, Phase, Deadline) ->
    {ok, Snapshot = #{state := State}} = hls_domain_erts:status(Backend),
    case State#domain_state.phase of
        Phase -> Snapshot;
        _ ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> receive after 1 -> await_phase(Backend, Phase, Deadline) end;
                false -> error({profile_domain_timeout, Phase, Snapshot})
            end
    end.

%% Wait for the host policy to consume its independent native actor monitor.
-spec await_control_loss(pid(), integer()) -> ok.
await_control_loss(Policy, Deadline) ->
    case hls_recovery_policy_fixture:status(Policy) of
        #{control := unavailable} -> ok;
        _ ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> receive after 1 -> await_control_loss(Policy, Deadline) end;
                false -> error(control_loss_timeout)
            end
    end.
