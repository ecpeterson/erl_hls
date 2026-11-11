-module(hls_recovery_application).
-moduledoc "One supervised profile application exercised unchanged through native or RTL-backed domains and a real ERTS distribution peer. Assertions use public effects, lifecycle handles and process signals, not simulator state.".
-include("hls_recovery_profile.hrl").

%% Backend-neutral scenario and helpers executed in the real peer VM.
-export([run/5, start_policy/1, fail_source/1, stale_pid/1]).

-doc "Exercises domains a and b exposing actuator; a must explicitly allow automatic replacement of this reset-safe simulated controller. Devices outlive every incarnation. Options select node configuration only, not application semantics.".
-spec run(pid(), pid(), pid(), pid(), map()) -> map().
run(OwnerA, OwnerB, DeviceA, DeviceB, Options) ->
    {ok, automatic} = hls_domain:policy(OwnerA, a),
    {ok, Supervisor} = hls_recovery_supervisor:start_link(OwnerA, a),
    unlink(Supervisor),
    try
        {FirstChild, #{handle := FirstHandle}} = instance(Supervisor, none),
        #{handle := OtherHandle} = ensure_ready(OwnerB, b),
        {ok, FirstEndpoint} = hls_domain:resolve(OwnerA, FirstHandle, actuator),
        {ok, OtherEndpoint} = hls_domain:resolve(OwnerB, OtherHandle, actuator),
        ok = hls_recovery_device_model:bind(DeviceA, FirstHandle, FirstEndpoint),
        ok = hls_recovery_device_model:bind(DeviceB, OtherHandle, OtherEndpoint),
        hls_test_nodes:distribution(),
        {ok, _} = application:ensure_all_started(crypto),
        Services = [#{name => a, domain => #{owner => OwnerA, id => a}},
            #{name => b, domain => #{owner => OwnerB, id => b}}],
        {ok, Node} = hls_node:start_link(node_name(), #{}, Services,
            maps:get(node_options, Options, #{})),
        unlink(Node),
        {Peer, Remote} = hls_test_nodes:start_peer(),
        try
            #{a := #{actors := #{actuator := A}}, b := #{actors := #{actuator := B}}} = hls_node:services(Node),
            PolicyA = erpc:call(Remote, ?MODULE, start_policy, [A]),
            PolicyB = erpc:call(Remote, ?MODULE, start_policy, [B]),
            try
                profiles(PolicyA, DeviceA),
                independent_profile(PolicyB, DeviceB),
                recover(OwnerA, OwnerB, Node, Remote, Supervisor, FirstChild,
                    FirstHandle, A, PolicyA, PolicyB, DeviceA, DeviceB)
            after stop(PolicyA), stop(PolicyB) end
        after peer:stop(Peer), catch hls_node:stop(Node) end
    after stop(Supervisor) end.

%% Profile acceptance, digital effects and logical validity are three distinct observations.
-spec profiles(pid(), pid()) -> ok.
profiles(Policy, Device) ->
    #profile_status{status = ?PROFILE_UNKNOWN, epoch = 0} = hls_recovery_policy_fixture:observe(Policy, 1, 0),
    #profile_status{status = ?PROFILE_INVALID} = hls_recovery_policy_fixture:select(Policy, 9, 0, 2),
    #profile_status{status = ?PROFILE_PENDING, epoch = 0} = hls_recovery_policy_fixture:select(Policy, 1, 0, 1),
    #profile_status{status = ?PROFILE_PENDING, epoch = 0} = hls_recovery_policy_fixture:select(Policy, 1, 0, 1),
    #profile_status{status = ?PROFILE_BUSY} = hls_recovery_policy_fixture:select(Policy, 2, 0, 0),
    ok = hls_recovery_policy_fixture:apply_profile(Policy, 1, 0),
    #profile_status{status = ?PROFILE_APPLIED, epoch = 1, enabled = 16#fe} = hls_recovery_policy_fixture:observe(Policy, 1, 0),
    First = #profile_applied{request = 1, epoch = 1, profile = 1, enabled = 16#fe},
    [First] = effects(Device, 1),
    ok = hls_recovery_policy_fixture:apply_profile(Policy, 1, 0),
    #profile_status{status = ?PROFILE_APPLIED} = hls_recovery_policy_fixture:observe(Policy, 1, 0),
    #profile_status{status = ?PROFILE_STALE} = hls_recovery_policy_fixture:select(Policy, 2, 0, 0),
    ok = hls_recovery_policy_fixture:result(Policy, common, {ok, 1}),
    ok = hls_recovery_policy_fixture:result(Policy, deferred, {error, unused_input}),
    ok = hls_recovery_policy_fixture:branch(Policy, simple),
    #{logical := {ok, 1}} = hls_recovery_policy_fixture:status(Policy),
    ok = hls_recovery_policy_fixture:branch(Policy, extended),
    #{logical := unavailable} = hls_recovery_policy_fixture:status(Policy),
    ok = hls_recovery_policy_fixture:result(Policy, common, {error, late_fault}),
    #{control := available, logical := unavailable, held := 16#ff} = hls_recovery_policy_fixture:status(Policy),
    {error, occupied} = hls_recovery_device_model:reserve(Device, 1),
    [First] = maps:get(effects, hls_recovery_device_model:snapshot(Device)),
    ok.

%% Unrelated controller work supplies a persistent progress observation during A's failures.
-spec independent_profile(pid(), pid()) -> ok.
independent_profile(Policy, Device) ->
    #profile_status{status = ?PROFILE_PENDING} = hls_recovery_policy_fixture:select(Policy, 17, 0, 0),
    ok = hls_recovery_policy_fixture:apply_profile(Policy, 17, 0),
    #profile_status{status = ?PROFILE_APPLIED, epoch = 1} = hls_recovery_policy_fixture:observe(Policy, 17, 0),
    [#profile_applied{request = 17, epoch = 1, profile = 0, enabled = 0}] = effects(Device, 1),
    ok.

%% An ordinary supervisor replaces failed controller state, but never the external device or the old policy's assumptions.
-spec recover(pid(), pid(), pid(), node(), pid(), pid(), hls_domain:handle(), pid(), pid(), pid(), pid(), pid()) -> map().
recover(OwnerA, OwnerB, Node, Remote, Supervisor, FirstChild, FirstHandle,
        A, OldPolicy, OtherPolicy, DeviceA, DeviceB) ->
    {ok, #{handle := BHandle}} = hls_domain:status(OwnerB, b),
    #profile_status{status = ?PROFILE_PENDING, epoch = 1} = hls_recovery_policy_fixture:select(OldPolicy, 2, 1, 0),
    Reason = erpc:call(Remote, ?MODULE, fail_source, [A]),
    true = Reason =/= noconnection andalso Reason =/= noproc,
    {SecondChild, #{handle := SecondHandle}} = instance(Supervisor, FirstChild),
    true = SecondHandle =/= FirstHandle,
    ok = device_down(DeviceA, FirstHandle),
    {ok, SecondEndpoint} = hls_domain:resolve(OwnerA, SecondHandle, actuator),
    ok = hls_recovery_device_model:bind(DeviceA, SecondHandle, SecondEndpoint),
    {ok, #{actors := #{actuator := FreshA}}} = hls_node:publish_domain(Node, a),
    true = FreshA =/= A,
    noproc = erpc:call(Remote, ?MODULE, stale_pid, [A]),
    await(fun() -> maps:get(control, hls_recovery_policy_fixture:status(OldPolicy)) =:= unavailable end),
    {error, unavailable} = hls_recovery_policy_fixture:select(OldPolicy, 3, 0, 0),
    {error, occupied} = hls_recovery_policy_fixture:reserve(OldPolicy, 1),
    {error, occupied} = hls_recovery_device_model:reserve(DeviceA, 16#ff),
    FirstEffects = maps:get(effects, hls_recovery_device_model:snapshot(DeviceA)),
    1 = length(FirstEffects),
    NewPolicy = erpc:call(Remote, ?MODULE, start_policy, [FreshA]),
    try
        #profile_status{status = ?PROFILE_UNKNOWN, epoch = 0} = hls_recovery_policy_fixture:observe(NewPolicy, 2, 1),
        ok = hls_recovery_policy_fixture:apply_profile(NewPolicy, 2, 1),
        #profile_status{status = ?PROFILE_UNKNOWN, epoch = 0} = hls_recovery_policy_fixture:observe(NewPolicy, 2, 1),
        FirstEffects = maps:get(effects, hls_recovery_device_model:snapshot(DeviceA)),
        %% Losing only the host representative consumes a supervisor restart but does not reset hardware.
        {ok, LocalA} = hls_domain:resolve(OwnerA, SecondHandle, actuator),
        exit(SecondChild, kill),
        {_ThirdChild, #{handle := SecondHandle}} = instance(Supervisor, SecondChild),
        {ok, LocalA} = hls_domain:resolve(OwnerA, SecondHandle, actuator),
        {ok, #{actors := #{actuator := FreshA}}} = hls_node:publish_domain(Node, a),
        #profile_status{status = ?PROFILE_PENDING, epoch = 0} = hls_recovery_policy_fixture:select(NewPolicy, 3, 0, 0),
        ok = hls_recovery_policy_fixture:apply_profile(NewPolicy, 3, 0),
        #profile_status{status = ?PROFILE_APPLIED, epoch = 1} = hls_recovery_policy_fixture:observe(NewPolicy, 3, 0),
        FinalEffects = effects(DeviceA, 2),
        ExpectedEffects = FirstEffects ++ [#profile_applied{request = 3, epoch = 1, profile = 0, enabled = 0}],
        ExpectedEffects = FinalEffects,
        %% Third restart within the intensity window terminates the supervisor; no hidden reset loop remains.
        SupervisorMonitor = monitor(process, Supervisor),
        LastReason = erpc:call(Remote, ?MODULE, fail_source, [FreshA]),
        true = LastReason =/= noconnection andalso LastReason =/= noproc,
        receive {'DOWN', SupervisorMonitor, process, Supervisor, shutdown} -> ok
            after 5000 -> error(restart_intensity_not_enforced) end,
        #{phase := failed, handle := SecondHandle} = phase(OwnerA, a, failed),
        ok = device_down(DeviceA, SecondHandle),
        [{effect, _}, {down, FirstHandle, _}, {effect, _}, {down, SecondHandle, _}] =
            maps:get(observations, hls_recovery_device_model:snapshot(DeviceA)),
        {error, not_ready} = hls_domain:resolve(OwnerA, a, actuator),
        #profile_status{status = ?PROFILE_APPLIED, epoch = 1} = hls_recovery_policy_fixture:observe(OtherPolicy, 17, 0),
        {ok, #{handle := BHandle}} = hls_domain:status(OwnerB, b),
        [_] = maps:get(effects, hls_recovery_device_model:snapshot(DeviceB)),
        FinalEffects = maps:get(effects, hls_recovery_device_model:snapshot(DeviceA)),
        #{profile_history => [effect_map(E) || E <- FinalEffects], independent_domain => true,
          unchanged_remote_policy => true, real_erts_peer => true,
          automatic_replacement => true, representative_reattachment => true,
          restart_intensity => true, resource_ownership_survives => true,
          external_effects_survive => true, effect_before_down => true, unused_failed_branch => true,
          stale_endpoint_retired => true, stale_trigger_inert => true,
          evidence => finite_recovery_application_witness}
    after stop(NewPolicy) end.

-doc "Starts the identical host policy in the real peer VM; only its actor endpoint varies by deployment.".
-spec start_policy(pid()) -> pid().
start_policy(Actor) ->
    {ok, Policy} = hls_recovery_policy_fixture:start_link(Actor),
    unlink(Policy),
    Policy.

-doc "Observes an actual source failure through a virtual PID; the query establishes a monitor/call ordering boundary.".
-spec fail_source(pid()) -> term().
fail_source(Actor) ->
    Ref = monitor(process, Actor),
    #profile_status{} = hls_statem:call(Actor, #query_profile{request = 0, epoch = 0}),
    gen_server:cast(Actor, #controller_failure{reason = 1}),
    receive {'DOWN', Ref, process, Actor, Reason} -> Reason
        after 5000 -> error(source_did_not_fail) end.

-doc "An old virtual PID must report noproc and cannot redirect an application command to its successor.".
-spec stale_pid(pid()) -> term().
stale_pid(Actor) ->
    Ref = monitor(process, Actor),
    gen_server:cast(Actor, #apply_profile{request = 2, epoch = 1}),
    receive {'DOWN', Ref, process, Actor, Reason} -> Reason
        after 5000 -> error(stale_pid_survived) end.

%% Readiness may be asynchronous; startup never treats a successful submission as completion.
-spec ensure_ready(pid(), hls_domain:domain()) -> hls_domain:snapshot().
ensure_ready(Owner, Domain) ->
    case hls_domain:status(Owner, Domain) of
        {ok, #{phase := unbound}} -> {ok, _} = hls_domain:activate(Owner, Domain);
        {ok, _} -> ok
    end,
    phase(Owner, Domain, ready).

%% Return one named observation within the finite test budget.
-spec phase(pid(), hls_domain:domain(), hls_domain_lifecycle:phase()) -> hls_domain:snapshot().
phase(Owner, Domain, Phase) ->
    await(fun() -> case hls_domain:status(Owner, Domain) of
        {ok, #{phase := Phase}} -> true; _ -> false end end),
    {ok, Snapshot = #{phase := Phase}} = hls_domain:status(Owner, Domain),
    Snapshot.

%% Wait for a new representative's acknowledged incarnation rather than elapsed time.
-spec instance(pid(), none | pid()) -> {pid(), hls_domain:snapshot()}.
instance(Supervisor, Previous) ->
    Deadline = erlang:monotonic_time(millisecond) + 5000,
    instance(Supervisor, Previous, Deadline).

%% Restart observation tolerates only the transient gap before a replacement child is ready.
-spec instance(pid(), none | pid(), integer()) -> {pid(), hls_domain:snapshot()}.
instance(Supervisor, Previous, Deadline) ->
    Found = try supervisor:which_children(Supervisor) of
        [{instance, Child, worker, _}] when is_pid(Child), Child =/= Previous ->
            case hls_domain_instance:status(Child) of
                Snapshot = #{phase := ready} -> {ok, Child, Snapshot}; _ -> wait end;
        _ -> wait
    catch exit:_ -> wait end,
    case Found of
        {ok, ChildPid, Snapshot0} -> {ChildPid, Snapshot0};
        wait ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            receive after 1 -> instance(Supervisor, Previous, Deadline) end
    end.

%% Device observation is independent of management and may arrive later on its ordinary message path.
-spec effects(pid(), non_neg_integer()) -> [#profile_applied{}].
effects(Device, Count) ->
    await(fun() -> length(maps:get(effects, hls_recovery_device_model:snapshot(Device))) >= Count end),
    Effects = maps:get(effects, hls_recovery_device_model:snapshot(Device)),
    Count = length(Effects),
    Effects.

%% Observe the source endpoint's termination at the same recipient which consumes its effects.
-spec device_down(pid(), hls_domain:handle()) -> ok.
device_down(Device, Handle) ->
    await(fun() -> lists:any(fun
        ({down, H, _}) -> H =:= Handle;
        (_) -> false
    end, maps:get(observations, hls_recovery_device_model:snapshot(Device))) end).

%% Public result data is independently specified and serializable without opaque process state.
-spec effect_map(#profile_applied{}) -> map().
effect_map(#profile_applied{request = Request, epoch = Epoch, profile = Profile, enabled = Enabled}) ->
    #{request => Request, epoch => Epoch, profile => Profile, enabled => Enabled}.

%% Bound test waiting; timeout is test failure, never evidence of a remote fence.
-spec await(fun(() -> boolean())) -> ok.
await(Predicate) -> await(Predicate, erlang:monotonic_time(millisecond) + 5000).

%% Retry public observations without issuing replacement or application work.
-spec await(fun(() -> boolean()), integer()) -> ok.
await(Predicate, Deadline) ->
    case Predicate() of
        true -> ok;
        false ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            receive after 1 -> await(Predicate, Deadline) end
    end.

%% Each finite run owns a distinct externally advertised test node name.
-spec node_name() -> node().
node_name() ->
    [_Local, Host] = string:split(atom_to_list(node()), "@"),
    list_to_atom("recovery_app_" ++ integer_to_list(erlang:unique_integer([positive])) ++ "@" ++ Host).

%% Cleanup never invokes the domain replacement API or replays work.
-spec stop(pid()) -> ok.
stop(Process) -> catch gen_server:stop(Process), ok.
