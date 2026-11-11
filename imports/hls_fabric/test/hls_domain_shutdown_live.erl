-module(hls_domain_shutdown_live).
-moduledoc "Finite matched native/RTL supervision witness over three independent domains. Ordinary OTP strategies, real peer monitors and public actor calls establish lifetime behavior; no private simulator state is inspected.".
-include("hls_recovery_profile.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% External witness driver and monitor helper executed in a real ERTS peer.
-export([native/1, run/2, watch/2]).

-doc "Runs the shared three-domain scenario on native source actors and retains its expected public outcomes.".
-spec native(file:filename()) -> ok.
native(Stage) ->
    ok = filelib:ensure_dir(filename:join(Stage, "counter")),
    Deployments = [native_domain(Domain, Stage) || Domain <- [a, b, c]],
    try
        Result = scenario(Deployments),
        write_result(Stage, Result, native)
    after close_native(Deployments) end.

-doc "Runs the same scenario over three generated cores, then withholds actual output delivery during an explicit stop.".
-spec run(file:filename(), file:filename()) -> ok.
run(Stage, ExpectedFile) ->
    {ok, ExpectedBytes} = file:read_file(ExpectedFile),
    Expected = binary_to_term(ExpectedBytes),
    Interface = filename:join(Stage, "interface.etf"),
    Deployments = [rtl_domain(Domain, Index, Stage, Interface) ||
        {Domain, Index} <- [{a, 0}, {b, 1}, {c, 2}]],
    Brokers = lists:append([maps:get(brokers, D) || D <- Deployments]),
    Leases = [begin #{io := #{lease := Lease}} = hls_fabric:info(B), Lease end || B <- Brokers],
    try
        Result = scenario(Deployments),
        Expected = Result,
        ok = file:write_file(filename:join(Stage, "application-observation.json"),
            json:encode(Result#{native_history_matches => true}), [exclusive]),
        Delivery = delayed_stop(Stage, lists:nth(3, Deployments)),
        [ok = gen_server:stop(Pid, normal, 5000) ||
            D <- Deployments, Pid <- [maps:get(owner, D), maps:get(backend, D)]],
        [ok = hls_fabric:stop(Broker) || Broker <- Brokers],
        ok = file:write_file(filename:join(Stage, "finished"), <<>>, [exclusive]),
        [ok = hls_fabric:await_closed(Lease, 5000) || Lease <- Leases],
        ok = file:write_file(filename:join(Stage, "result.etf"), term_to_binary(Result), [exclusive]),
        ok = file:write_file(filename:join(Stage, "result.json"), json:encode(Result#{
            passed => true, deployment => generated_rtl, native_history_matches => true,
            descriptor_closure => true, delayed_stop => Delivery}), [exclusive])
    after
        [catch gen_server:stop(Pid, normal, 5000) || D <- Deployments,
            Pid <- [maps:get(owner, D), maps:get(backend, D), maps:get(device, D)]],
        [catch hls_fabric:stop(Broker) || Broker <- Brokers]
    end.

%% Each native child owns its actor lifecycle; external device effects survive every restart.
-spec native_domain(atom(), file:filename()) -> map().
native_domain(Domain, Stage) ->
    {ok, Device} = hls_recovery_device_model:start_link(), unlink(Device),
    Spec = #{actors => #{actuator => #{module => hls_recovery_actuator_fixture, mailbox_capacity => 4}},
        routes => #{actuator => #{effect => {external, Device}, reply => {external, Device}}}, startup => #{}},
    {ok, Backend} = hls_domain_erts:start_link(Spec), unlink(Backend),
    #{domain => Domain, owner => owner(Domain, hls_domain_erts, Backend, Stage),
        backend => Backend, device => Device}.

%% Public sideband acknowledgements precede broker attachment; each core has independent lanes.
-spec rtl_domain(atom(), non_neg_integer(), file:filename(), file:filename()) -> map().
rtl_domain(Domain, Index, Stage, Interface) ->
    {ok, Device} = hls_recovery_device_model:start_link(), unlink(Device),
    Prefix = filename:join(Stage, "domain" ++ integer_to_list(Index)),
    ok = hls_recovery_stream_live:session(Prefix, 1),
    {Backend, Brokers} = hls_recovery_stream_live:backend(Prefix, Interface, Device, 1),
    #{domain => Domain, owner => owner(Domain, hls_domain_fabric, Backend, Stage),
        backend => Backend, device => Device, brokers => Brokers}.

%% Automatic replacement applies only to these explicitly reset-safe digital fixtures.
-spec owner(atom(), module(), pid(), file:filename()) -> pid().
owner(Domain, Module, Backend, Stage) ->
    Store = filename:join(Stage, atom_to_list(Domain) ++ ".incarnations"),
    ok = hls_domain:create_store(Store),
    {ok, Owner} = hls_domain:start_link(#{Domain => automatic},
        #{module => Module, endpoints => #{Domain => Backend}, incarnation_file => Store}),
    unlink(Owner), Owner.

%% Manual termination, both dependent restart strategies, stale commands and an unaffected region share one source application.
-spec scenario([map()]) -> map().
scenario([A = #{owner := OA}, B = #{owner := OB}, C = #{owner := OC}]) ->
    [begin {ok, _} = hls_domain:activate(O, D), ready(O, D) end ||
        #{owner := O, domain := D} <- [A, B, C]],
    {ok, All} = hls_shutdown_supervisor:start_link(one_for_all, [{a, OA}, {b, OB}]), unlink(All),
    {_, HA} = child(All, a), {_, HB} = child(All, b),
    HC = maps:get(handle, ready(OC, c)),
    hls_test_nodes:distribution(), {ok, _} = application:ensure_all_started(crypto),
    Name = list_to_atom("shutdown_" ++ integer_to_list(erlang:unique_integer([positive])) ++ "@localhost"),
    Services = [#{name => D, domain => #{owner => O, id => D}} || #{domain := D, owner := O} <- [A, B, C]],
    {ok, Node} = hls_node:start_link(Name, #{}, Services, #{}), unlink(Node),
    {Peer, Remote} = hls_test_nodes:start_peer(),
    try
        VA = virtual(Node, a), VB = virtual(Node, b), VC = virtual(Node, c),
        [applied(Remote, V, 1) || V <- [VA, VB, VC]],
        WA = watched(Remote, VA),
        ok = supervisor:terminate_child(All, a),
        stopped(OA, a, HA),
        shutdown = down(WA),
        {ok, #{phase := stopped, handle := HA}} = hls_domain:stop(OA, HA),
        HB = maps:get(handle, ready(OB, b)), HC = maps:get(handle, ready(OC, c)),
        expect_applied(Remote, VB, 1), expect_applied(Remote, VC, 1),
        {ok, _} = supervisor:restart_child(All, a),
        {_, HA1} = child(All, a), true = HA1 =/= HA,
        VA1 = publish(Node, a), true = VA1 =/= VA,
        initial(Remote, VA1),
        {error, _Protected} = hls_domain:stop(OA, HA),
        HA1 = maps:get(handle, ready(OA, a)),
        applied(Remote, VA1, 2),
        WB = watched(Remote, VB),
        _ = erpc:call(Remote, hls_recovery_application, fail_source, [VA1]),
        {_, HA2} = changed_child(All, a, HA1),
        {_, HB1} = changed_child(All, b, HB),
        shutdown = down(WB),
        initial(Remote, publish(Node, a)), initial(Remote, publish(Node, b)),
        HC = maps:get(handle, ready(OC, c)), expect_applied(Remote, VC, 1),
        stop_supervisor(All), stopped(OA, a, HA2), stopped(OB, b, HB1),
        {ok, Rest} = hls_shutdown_supervisor:start_link(rest_for_one, [{a, OA}, {b, OB}]), unlink(Rest),
        try
            {_, RA} = child(Rest, a), {_, RB} = child(Rest, b),
            true = RA =/= HA2, true = RB =/= HB1,
            RVA = publish(Node, a), RVB = publish(Node, b),
            applied(Remote, RVA, 3), applied(Remote, RVB, 3),
            _ = erpc:call(Remote, hls_recovery_application, fail_source, [RVB]),
            {_, RB1} = changed_child(Rest, b, RB),
            {_, RA} = child(Rest, a), expect_applied(Remote, RVA, 3),
            initial(Remote, publish(Node, b)),
            _ = erpc:call(Remote, hls_recovery_application, fail_source, [RVA]),
            {_, RA1} = changed_child(Rest, a, RA),
            {_, RB2} = changed_child(Rest, b, RB1),
            initial(Remote, publish(Node, a)), initial(Remote, publish(Node, b)),
            HC = maps:get(handle, ready(OC, c)), expect_applied(Remote, VC, 1),
            stop_supervisor(Rest), stopped(OA, a, RA1), stopped(OB, b, RB2),
            {error, stale} = hls_domain:stop(OA, HA),
            #{explicit_healthy_stop => true, duplicate_stop_idempotent => true,
                stale_stop_rejected => true, fresh_endpoint_and_incarnation => true,
                one_for_all => true, rest_for_one => true, subtree_shutdown => true,
                independent_domain_progress => true, real_erts_peer => true,
                no_application_replay => true, evidence => finite_supervised_shutdown_witness}
        after catch stop_supervisor(Rest) end
    after
        catch stop_supervisor(All), peer:stop(Peer), catch hls_node:stop(Node)
    end.

%% A pending old reply must be delivered before stop becomes externally complete.
-spec delayed_stop(file:filename(), map()) -> map().
delayed_stop(Stage, #{owner := Owner, backend := Backend, device := Device}) ->
    #{handle := Handle} = ready(Owner, c),
    {ok, Actor} = hls_domain:resolve(Owner, Handle, actuator),
    ok = hls_recovery_device_model:bind(Device, Handle, Actor),
    #profile_status{status = ?PROFILE_PENDING, epoch = 1} =
        hls_statem:call(Actor, #select_profile{request = 9, epoch = 1, profile = 1}),
    #{received := Received} = hls_domain_fabric:info(Backend),
    delivery(Stage, hold),
    Parent = self(), Ref = make_ref(),
    {Watcher, Monitor} = spawn_monitor(fun() -> delayed_caller(Parent, Ref, Actor) end),
    try
        _ = wait(fun() ->
            #{received := R, frontier := F} = hls_domain_fabric:info(Backend),
            case R =:= Received andalso F >= Received + 4 of true -> {ok, F}; false -> wait end
        end),
        {ok, _} = hls_domain:stop(Owner, Handle),
        _ = wait(fun() ->
            case hls_domain_fabric:info(Backend) of
                #{state := #domain_state{phase = stopped}} = Info -> {ok, Info};
                _ -> wait
            end
        end),
        true = is_process_alive(Actor),
        {error, delivery_pending} = hls_domain:status(Owner, c),
        receive {Ref, _, _} -> error(retirement_before_delivery) after 0 -> ok end,
        delivery(Stage, resume),
        receive {Ref, reply, #profile_status{status = ?PROFILE_APPLIED, epoch = 2}} -> ok
            after 5000 -> error(prior_reply_missing) end,
        receive {Ref, down, shutdown} -> ok after 5000 -> error(shutdown_missing) end,
        receive {'DOWN', Monitor, process, Watcher, normal} -> ok
            after 5000 -> error(watcher_failed) end,
        stopped(Owner, c, Handle),
        #{hardware_stopped_before_delivery => true, public_stop_waited_for_delivery => true,
            prior_reply_before_shutdown => true, management_progressed_during_stall => true}
    after delivery(Stage, resume), exit(Watcher, kill), demonitor(Monitor, [flush]) end.

%% FIFO delivery is withheld without modifying the source actor or generated lifecycle state.
-spec delivery(file:filename(), hold | resume) -> ok.
delivery(Stage, Action) ->
    hls_recovery_stream_live:delivery(Stage, 2, application, Action).


%% Mailbox order exposes an early DOWN rather than hiding it behind selective receive.
-spec delayed_caller(pid(), reference(), pid()) -> ok.
delayed_caller(Parent, Ref, Actor) ->
    Monitor = monitor(process, Actor), Reply = make_ref(),
    gen_server:cast(Actor, #apply_profile{request = 9, epoch = 1}),
    Actor ! {'$gen_call', {self(), Reply}, #query_profile{request = 9, epoch = 1}},
    receive
        {Reply, Result = #profile_status{}} -> Parent ! {Ref, reply, Result};
        {'DOWN', Monitor, process, Actor, Reason} -> error({down_before_reply, Reason})
    after 5000 -> error(reply_timeout) end,
    receive {'DOWN', Monitor, process, Actor, Why} -> Parent ! {Ref, down, Why}
        after 5000 -> error(down_timeout) end.

-doc "Installs a real remote process monitor and establishes a call-order boundary before reporting that monitoring is active.".
-spec watch(pid(), pid()) -> pid().
watch(Actor, Parent) ->
    spawn(fun() ->
        Ref = monitor(process, Actor),
        #profile_status{} = hls_statem:call(Actor, #query_profile{request = 0, epoch = 0}),
        Parent ! {watching, self()},
        receive {'DOWN', Ref, process, Actor, Reason} -> Parent ! {retired, self(), Reason}
            after 10000 -> error(remote_monitor_timeout) end
    end).

%% Wait for the remote monitor's acknowledged installation before issuing a stop.
-spec watched(node(), pid()) -> pid().
watched(Remote, Actor) ->
    Watcher = erpc:call(Remote, ?MODULE, watch, [Actor, self()]),
    receive {watching, Watcher} -> Watcher after 5000 -> error(monitor_not_installed) end.

%% Observe the terminal reason from the previously established remote monitor.
-spec down(pid()) -> term().
down(Watcher) ->
    receive {retired, Watcher, Reason} -> Reason after 5000 -> error(endpoint_not_retired) end.

%% A successful profile transition leaves a state marker which distinguishes preservation from reset.
-spec applied(node(), pid(), pos_integer()) -> ok.
applied(Remote, Actor, Request) ->
    #profile_status{status = ?PROFILE_PENDING, epoch = 0} =
        erpc:call(Remote, hls_statem, call, [Actor, #select_profile{request = Request, epoch = 0, profile = 1}]),
    ok = erpc:call(Remote, gen_server, cast, [Actor, #apply_profile{request = Request, epoch = 0}]),
    expect_applied(Remote, Actor, Request).

%% Repeated public observations make independent state preservation observable.
-spec expect_applied(node(), pid(), pos_integer()) -> ok.
expect_applied(Remote, Actor, Request) ->
    #profile_status{status = ?PROFILE_APPLIED, epoch = 1} =
        erpc:call(Remote, hls_statem, call, [Actor, #query_profile{request = Request, epoch = 0}]), ok.

%% Replacement starts a fresh digital actor; it does not restore its predecessor's data.
-spec initial(node(), pid()) -> ok.
initial(Remote, Actor) ->
    #profile_status{status = ?PROFILE_UNKNOWN, epoch = 0} =
        erpc:call(Remote, hls_statem, call, [Actor, #query_profile{request = 1, epoch = 0}]), ok.

%% Virtual PID publication binds the currently acknowledged ready incarnation.
-spec publish(pid(), atom()) -> pid().
publish(Node, Domain) ->
    {ok, #{actors := #{actuator := Actor}}} = hls_node:publish_domain(Node, Domain), Actor.

%% Read only the virtual node's published actor identity.
-spec virtual(pid(), atom()) -> pid().
virtual(Node, Domain) ->
    #{actors := #{actuator := Actor}} = maps:get(Domain, hls_node:services(Node)), Actor.

%% A supervisor child is ready only when its represented incarnation is ready.
-spec child(pid(), atom()) -> {pid(), hls_domain:handle()}.
child(Supervisor, Domain) ->
    wait(fun() ->
        case lists:keyfind(Domain, 1, supervisor:which_children(Supervisor)) of
            {Domain, Pid, worker, _} when is_pid(Pid) ->
                try hls_domain_instance:status(Pid) of
                    #{phase := ready, handle := Handle} -> {ok, {Pid, Handle}};
                    _ -> wait
                catch exit:_ -> wait end;
            _ -> wait
        end
    end).

%% A real replacement must change incarnation, not merely its host representative.
-spec changed_child(pid(), atom(), hls_domain:handle()) -> {pid(), hls_domain:handle()}.
changed_child(Supervisor, Domain, Previous) ->
    wait(fun() ->
        {Pid, Handle} = child(Supervisor, Domain),
        case Handle =/= Previous of true -> {ok, {Pid, Handle}}; false -> wait end
    end).

%% Poll readiness without issuing lifecycle transitions.
-spec ready(pid(), atom()) -> hls_domain:snapshot().
ready(Owner, Domain) ->
    wait(fun() -> case hls_domain:status(Owner, Domain) of
        {ok, Snapshot = #{phase := ready}} -> {ok, Snapshot}; _ -> wait end end).

%% The public stopped phase must name exactly the retired incarnation.
-spec stopped(pid(), atom(), hls_domain:handle()) -> ok.
stopped(Owner, Domain, Handle) ->
    _ = wait(fun() -> case hls_domain:status(Owner, Domain) of
        {ok, Snapshot = #{phase := stopped, handle := Handle}} -> {ok, Snapshot}; _ -> wait end end), ok.

%% Test deadlines bound observation only; expiry never stands in for a device acknowledgement.
-spec wait(fun(() -> {ok, term()} | wait)) -> term().
wait(Fun) -> wait(Fun, erlang:monotonic_time(millisecond) + 10000).

%% Retain a clear failure when asynchronous supervision does not establish the expected public state.
-spec wait(fun(() -> {ok, term()} | wait), integer()) -> term().
wait(Fun, Deadline) ->
    case Fun() of
        {ok, Result} -> Result;
        wait ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            receive after 1 -> wait(Fun, Deadline) end
    end.

%% Stopping a supervisor must retire all its explicitly owned domains before successful return.
-spec stop_supervisor(pid()) -> ok.
stop_supervisor(Supervisor) -> gen_server:stop(Supervisor, shutdown, 10000).

%% The small expected outcome record is independent of runtime PID and incarnation allocation numbers.
-spec write_result(file:filename(), map(), atom()) -> ok.
write_result(Stage, Result, Deployment) ->
    ok = file:write_file(filename:join(Stage, "result.etf"), term_to_binary(Result), [exclusive]),
    file:write_file(filename:join(Stage, "result.json"),
        json:encode(Result#{passed => true, deployment => Deployment}), [exclusive]).

%% Explicit fixture cleanup does not claim backend retirement or undo device effects.
-spec close_native([map()]) -> ok.
close_native(Deployments) ->
    [catch gen_server:stop(Pid, normal, 5000) || D <- Deployments,
        Pid <- [maps:get(owner, D), maps:get(backend, D), maps:get(device, D)]], ok.
