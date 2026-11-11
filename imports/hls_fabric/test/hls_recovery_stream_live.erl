-module(hls_recovery_stream_live).
-moduledoc "Deployment-only harness for the same recovery application on ERTS and two generated framed-domain cores. The C++ peer transports words; lifecycle, application correlation and output frontiers are synthesized.".
-include("hls_recovery_profile.hrl").

%% External-tool entry points and explicit transport scheduling controls.
-export([native/1, run/2, delivery/4, session/2, backend/4]).

-doc "Runs the shared native application first and retains its independent expected public history in a fresh directory.".
-spec native(file:filename()) -> ok.
native(Stage) ->
    _ = hls_recovery_application_tests:native(Stage),
    ok.

-doc "Opens independent FIFO lanes for two domains, attaches the reusable backend, and requires the identical application history observed natively. Stage must contain the emitted interface.etf and fresh simulator FIFOs.".
-spec run(file:filename(), file:filename()) -> ok.
run(Stage, NativeResult) ->
    {ok, NativeBytes} = file:read_file(NativeResult),
    Native = binary_to_term(NativeBytes),
    Interface = filename:join(Stage, "interface.etf"),
    {ok, DeviceA} = hls_recovery_device_model:start_link(), unlink(DeviceA),
    {ok, DeviceB} = hls_recovery_device_model:start_link(), unlink(DeviceB),
    {A, BrokersA} = backend(filename:join(Stage, "domain0"), Interface, DeviceA),
    {B, BrokersB} = backend(filename:join(Stage, "domain1"), Interface, DeviceB),
    Brokers = BrokersA ++ BrokersB,
    Leases = [begin #{io := #{lease := Lease}} = hls_fabric:info(Broker), Lease end || Broker <- Brokers],
    OwnerA = owner(a, automatic, A, filename:join(Stage, "a.incarnations")),
    OwnerB = owner(b, manual, B, filename:join(Stage, "b.incarnations")),
    try
        RTL = hls_recovery_application:run(OwnerA, OwnerB, DeviceA, DeviceB, #{}),
        Native = RTL,
        ok = file:write_file(filename:join(Stage, "application-observation.json"),
            json:encode(RTL#{native_history_matches => true}), [exclusive]),
        Delivery = delayed_retirement(Stage, OwnerB, B, DeviceB),
        ok = file:write_file(filename:join(Stage, "delivery-observation.json"),
            json:encode(Delivery), [exclusive]),
        [ok = gen_server:stop(Pid, normal, 5000) || Pid <- [OwnerA, OwnerB, A, B]],
        [ok = hls_fabric:stop(Broker) || Broker <- Brokers],
        %% A reader blocked in the OS cannot close until its FIFO peer closes too.
        %% This signals transport shutdown only; final success still requires every lease below.
        ok = file:write_file(filename:join(Stage, "finished"), <<>>, [exclusive]),
        [ok = hls_fabric:await_closed(Lease, 5000) || Lease <- Leases],
        ok = file:write_file(filename:join(Stage, "result.etf"), term_to_binary(RTL), [exclusive]),
        ok = file:write_file(filename:join(Stage, "result.json"), json:encode(RTL#{passed => true,
            deployment => generated_rtl, native_history_matches => true, descriptor_closure => true,
            delayed_retirement => Delivery}), [exclusive])
    after
        [catch gen_server:stop(Pid, normal, 5000) ||
            Pid <- [OwnerA, OwnerB, A, B] ++ Brokers ++ [DeviceA, DeviceB]]
    end.

%% The ordinary application leaves manual domain B ready; pause only transport delivery after its next selection.
-spec delayed_retirement(file:filename(), pid(), pid(), pid()) -> map().
delayed_retirement(Stage, Owner, Backend, Device) ->
    {ok, #{phase := ready, handle := Handle}} = hls_domain:status(Owner, b),
    {ok, Actor} = hls_domain:resolve(Owner, Handle, actuator),
    #profile_status{status = ?PROFILE_PENDING, epoch = 1} =
        hls_statem:call(Actor, #select_profile{request = 25, epoch = 1, profile = 1}),
    #{received := Received} = hls_domain_fabric:info(Backend),
    ok = delivery(Stage, 1, application, hold),
    Caller = self(), Reference = make_ref(),
    {Watcher, Monitor} = spawn_monitor(fun() -> delayed_caller(Caller, Reference, Actor) end),
    try
        %% Four actual stream responses: cast admission, effect, call admission and typed reply.
        %% The independent management lane observes their production while their bytes remain held.
        Produced = wait_observation(fun() ->
            Info = #{received := R, frontier := F} = hls_domain_fabric:info(Backend),
            case R =:= Received andalso F >= Received + 4 of true -> {ok, Info}; false -> wait end
        end),
        true = is_process_alive(Actor),
        [_] = maps:get(effects, hls_recovery_device_model:snapshot(Device)),
        no_caller_result(Reference, Monitor, Watcher),
        gen_server:cast(Actor, #controller_failure{reason = 1}),
        _ = wait_observation(fun() -> case hls_domain:status(Owner, b) of
            {ok, Snapshot = #{phase := failed}} -> {ok, Snapshot}; _ -> wait end end),
        #{received := Received, frontier := FaultFrontier} = hls_domain_fabric:info(Backend),
        true = FaultFrontier >= Received + 5,
        true = is_process_alive(Actor),
        no_caller_result(Reference, Monitor, Watcher),
        ok = delivery(Stage, 1, application, resume),
        receive
            {Reference, typed_reply, #profile_status{status = ?PROFILE_APPLIED,
                request = 25, epoch = 2, profile = 1, enabled = 16#fe}} -> ok;
            {'DOWN', Monitor, process, Watcher, Failure} -> error({caller_failed, Failure})
        after 5000 -> error(delayed_reply_missing) end,
        receive
            {Reference, ordered_down, Reason} ->
                true = Reason =/= noconnection andalso Reason =/= noproc;
            {'DOWN', Monitor, process, Watcher, FailureAfterReply} ->
                error({caller_failed_after_reply, FailureAfterReply})
        after 5000 -> error(delayed_down_missing) end,
        receive {'DOWN', Monitor, process, Watcher, normal} -> ok
            after 5000 -> error(caller_did_not_finish) end,
        _ = wait_observation(fun() ->
            case maps:get(observations, hls_recovery_device_model:snapshot(Device)) of
                [{effect, _}, {effect, #profile_applied{request = 25, epoch = 2,
                    profile = 1, enabled = 16#fe}}, {down, Handle, _}] -> {ok, done};
                _ -> wait
            end
        end),
        #{received_before_release => Received, produced_before_fault => maps:get(frontier, Produced),
            fault_frontier => FaultFrontier, endpoint_survived_pending_delivery => true,
            typed_reply_before_down => true, external_effect_before_down => true,
            management_progressed_during_application_delay => true}
    after
        _ = delivery(Stage, 1, application, resume),
        exit(Watcher, kill),
        demonitor(Monitor, [flush])
    end.

%% A raw ordinary gen_server call exposes mailbox order instead of hiding an earlier DOWN by selective receive.
-spec delayed_caller(pid(), reference(), pid()) -> ok.
delayed_caller(Parent, Reference, Actor) ->
    Monitor = monitor(process, Actor),
    Reply = make_ref(),
    gen_server:cast(Actor, #apply_profile{request = 25, epoch = 1}),
    Actor ! {'$gen_call', {self(), Reply}, #query_profile{request = 25, epoch = 1}},
    receive
        {Reply, Status = #profile_status{}} ->
            Parent ! {Reference, typed_reply, Status},
            receive {'DOWN', Monitor, process, Actor, Reason} ->
                Parent ! {Reference, ordered_down, Reason}, ok
            after 5000 -> error(delayed_down_missing) end;
        {'DOWN', Monitor, process, Actor, Reason} -> error({down_before_reply, Reason})
    after 5000 -> error(delayed_reply_missing) end.

%% Neither a typed reply nor endpoint termination may become visible while its output remains undelivered.
-spec no_caller_result(reference(), reference(), pid()) -> ok.
no_caller_result(Reference, Monitor, Watcher) ->
    receive
        {Reference, _, _} -> error(caller_completed_before_delivery);
        {'DOWN', Monitor, process, Watcher, Reason} -> error({caller_failed_before_delivery, Reason})
    after 0 -> ok end.

%% Bounded polling observes authoritative public backend state, never internal simulated registers.
-spec wait_observation(fun(() -> {ok, term()} | wait)) -> term().
wait_observation(Observe) ->
    wait_observation(Observe, erlang:monotonic_time(millisecond) + 5000).

%% Preserve the final failed observation in the calling assertion when the finite witness times out.
-spec wait_observation(fun(() -> {ok, term()} | wait), integer()) -> term().
wait_observation(Observe, Deadline) ->
    case Observe() of
        {ok, Value} -> Value;
        wait ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            receive after 1 -> wait_observation(Observe, Deadline) end
    end.

%% Only deployment-specific stream ownership belongs here; requests remain ordinary typed actor messages.
-spec backend(file:filename(), file:filename(), pid()) -> {pid(), [pid()]}.
backend(Prefix, Interface, Device) ->
    ok = session(Prefix, 1),
    backend(Prefix, Interface, Device, 1).

-doc "Opens fresh deployment FIFO lanes only after the caller has observed the actual session acknowledgement.".
-spec backend(file:filename(), file:filename(), pid(), pos_integer()) -> {pid(), [pid()]}.
backend(Prefix, Interface, Device, Session) ->
    {ok, Management} = hls_fabric:start_link(Prefix ++ "_management_tx", Prefix ++ "_management_rx", #{rx_route_limit => 1}),
    unlink(Management),
    {ok, Application} = hls_fabric:start_link(Prefix ++ "_application_tx", Prefix ++ "_application_rx", #{rx_route_limit => 1}),
    unlink(Application),
    {ok, Backend} = hls_domain_fabric:start_link(#{management => Management, application => Application, session => Session},
        Interface, #{recipients => #{{actuator, effect} => Device},
            management_timeout_ms => 3000, delivery_timeout_ms => 3000}),
    unlink(Backend),
    {Backend, [Management, Application]}.

%% Automatic replacement is explicitly confined to the reset-safe simulated controller.
-spec owner(atom(), hls_domain:policy(), pid(), file:filename()) -> pid().
owner(Domain, Policy, Backend, Store) ->
    ok = hls_domain:create_store(Store),
    {ok, Owner} = hls_domain:start_link(#{Domain => Policy}, #{module => hls_domain_fabric,
        endpoints => #{Domain => Backend}, incarnation_file => Store}),
    unlink(Owner),
    Owner.

-doc "Pauses or resumes only OS delivery of already accepted RTL bytes on one lane. The bounded queue still applies physical ready backpressure when full; management on the other lane continues. Acknowledgement is simulator transport policy, not a device fence.".
-spec delivery(file:filename(), 0 | 1 | 2, management | application, hold | resume) -> ok.
delivery(Stage, Domain, Lane, Action) ->
    Prefix = filename:join(Stage, "domain" ++ integer_to_list(Domain) ++ "_" ++
        atom_to_list(Lane) ++ "_delivery"),
    Value = case Action of hold -> <<"1">>; resume -> <<"0">> end,
    Temporary = Prefix ++ ".next",
    ok = file:write_file(Temporary, Value),
    ok = file:rename(Temporary, Prefix ++ ".control"),
    delivery_ack(Prefix ++ ".ack", Value, erlang:monotonic_time(millisecond) + 5000).

%% Wait for the transport scheduler's explicit acknowledgement rather than assuming a file write took effect.
-spec delivery_ack(file:filename(), binary(), integer()) -> ok.
delivery_ack(Path, Value, Deadline) ->
    case file:read_file(Path) of
        {ok, Value} -> ok;
        _ ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            receive after 1 -> delivery_ack(Path, Value, Deadline) end
    end.

-doc "Requests a public transport reset and waits for the simulator to observe matching actual RTL session outputs. Actor reset is untouched.".
-spec session(file:filename(),pos_integer()) -> ok.
session(Prefix,Session)->
    Value=integer_to_binary(Session),Path=Prefix++"_session",
    ok=file:write_file(Path++".next",Value),ok=file:rename(Path++".next",Path++".control"),
    wait_observation(fun()->case file:read_file(Path++".ack") of
        {ok,Bytes}->case string:trim(Bytes)=:=Value of true->{ok,ok};false->wait end;
        _->wait end end).
