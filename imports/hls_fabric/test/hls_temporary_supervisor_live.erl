-module(hls_temporary_supervisor_live).
-moduledoc "Finite native/RTL temporary-child witness: ordinary OTP reference, fixed compiled capacity, independent framed lanes and real remote callers.".
-include("hls_recovery_profile.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").
-export([native/1, run/2]).
-define(S, hls_supervisor_stream_live).

-doc "Runs the bounded-template scenario using ordinary OTP temporary child specifications and source actors.".
-spec native(file:filename()) -> ok.
native(Stage) ->
    ok = filelib:ensure_dir(filename:join(Stage, "unused")),
    Devices = [?S:device(), ?S:device()],
    Backends = [?S:native_backend(D) || D <- Devices],
    Owner = ?S:owner(native, maps:from_list(lists:zip([a, b], Backends)), hls_domain_erts, Stage),
    {ok, Supervisor} = hls_temporary_supervisor_otp:start_link(),
    unlink(Supervisor),
    Context = #{kind => native, supervisor => Supervisor, owner => Owner},
    try
        admitted(Context, Owner, Owner),
        Report = ?S:with_peer(Owner, Owner, fun(Node, Remote) ->
            Common = common(Context, Node, Remote, Owner, Owner),
            W = ?S:watched(Remote, ?S:virtual(Node, b)),
            ok = gen_server:stop(Supervisor, shutdown, 10000),
            shutdown = ?S:down(W),
            Common
        end),
        ?S:save(Stage, Report#{passed => true, deployment => native})
    after
        [catch gen_server:stop(P) || P <- [Supervisor, Owner] ++ Backends ++ Devices]
    end.

-doc "Exercises the same public lifetime history against generated RTL, then stalls accepted output across temporary retirement.".
-spec run(file:filename(), file:filename()) -> ok.
run(Stage, NativeFile) ->
    {ok, Bytes} = file:read_file(NativeFile),
    Native = maps:without([passed, deployment], binary_to_term(Bytes)),
    Prefix = filename:join(Stage, "parent"),
    ok = hls_recovery_stream_live:session(Prefix, 1),
    {ok, Broker} = hls_fabric:start_link(Prefix ++ "_management_tx", Prefix ++ "_management_rx", #{
        rx_route_limit => 1
    }),
    unlink(Broker),
    {ok, Backend} = hls_supervisor_fabric:start_link(
        #{management => Broker, session => 1},
        filename:join(Stage, "interface.etf"),
        #{grant => {1, 128}, management_timeout_ms => 5000}
    ),
    unlink(Backend),
    ParentOwner = ?S:owner(parent, #{board => Backend}, hls_supervisor_fabric, Stage),
    {ok, {1, 128}} = hls_domain:reserve_incarnations(ParentOwner, 128),
    {ok, Parent} = hls_shutdown_supervisor:start_link(one_for_one, [{board, ParentOwner}]),
    unlink(Parent),
    #{handle := ParentHandle} = ?S:ready(ParentOwner, board),
    {ok, Endpoint} = hls_domain:resolve(ParentOwner, ParentHandle, supervisor),
    A = ?S:rtl_child(a, 0, Stage),
    B = ?S:rtl_child(b, 1, Stage),
    OA = maps:get(owner, A),
    OB = maps:get(owner, B),
    Context = #{kind => rtl, supervisor => Endpoint},
    Brokers = [Broker | maps:get(brokers, A) ++ maps:get(brokers, B)],
    Leases = [?S:lease(P) || P <- Brokers],
    Processes = [
        Parent,
        ParentOwner,
        Backend,
        OA,
        OB,
        maps:get(backend, A),
        maps:get(backend, B),
        maps:get(device, A),
        maps:get(device, B)
    ],
    try
        admitted(Context, OA, OB),
        Report = ?S:with_peer(OA, OB, fun(Node, Remote) ->
            Native = common(Context, Node, Remote, OA, OB),
            Delay = held_output(Context, Stage, Node, Remote, A),
            WA = ?S:watched(Remote, ?S:virtual(Node, a)),
            WB = ?S:watched(Remote, ?S:virtual(Node, b)),
            ok = supervisor:terminate_child(Parent, board),
            shutdown = ?S:down(WA),
            shutdown = ?S:down(WB),
            Native#{delayed_retirement => Delay, native_history_matches => true}
        end),
        [catch gen_server:stop(P, normal, 5000) || P <- Processes],
        [ok = hls_fabric:stop(P) || P <- Brokers],
        ok = file:write_file(filename:join(Stage, "finished"), <<>>, [exclusive]),
        [ok = hls_fabric:await_closed(L, 5000) || L <- Leases],
        ?S:save(Stage, Report#{
            passed => true, deployment => generated_rtl, descriptor_closure => true
        })
    after
        [catch gen_server:stop(P, normal, 5000) || P <- Processes],
        [catch hls_fabric:stop(P) || P <- Brokers]
    end.

%% Concurrent contenders share the same last-occupant identity; exactly one gets an admission.
-spec admitted(map(), pid(), pid()) -> ok.
admitted(Context, OA, OB) ->
    #{phase := vacant, incarnation := 0} = slot(Context, a),
    #{phase := vacant, incarnation := 0} = slot(Context, b),
    Parent = self(),
    Ref = make_ref(),
    [spawn(fun() -> Parent ! {Ref, admit(Context, a, 0)} end) || _ <- [1, 2]],
    Results = [
        receive
            {Ref, R} -> R
        after 10000 -> error(admission_timeout)
        end
     || _ <- [1, 2]
    ],
    1 = length([ok || {ok, _} <- Results]),
    1 = length([busy || {error, busy} <- Results]),
    #{handle := {a, A}} = ?S:ready(OA, a),
    [{ok, A}] = [R || R = {ok, _} <- Results],
    {ok, B} = admit(Context, b, 0),
    #{handle := {b, B}} = ?S:ready(OB, b),
    {error, busy} = admit(Context, a, A),
    {error, busy} = admit(Context, b, B),
    {error, unknown_child} = admit(Context, not_compiled, 0),
    ok.

%% The same source fault and explicit normal termination leave vacant capacity, never a replacement.
-spec common(map(), pid(), node(), pid(), pid()) -> map().
common(Context, Node, Remote, OA, OB) ->
    VA = ?S:virtual(Node, a),
    VB = ?S:virtual(Node, b),
    #{handle := {a, Old}} = ?S:ready(OA, a),
    ?S:apply_profile(Remote, VB, 7),
    ?S:apply_profile(Remote, VA, 9),
    W = ?S:watched(Remote, VA),
    ok = erpc:call(Remote, gen_server, cast, [VA, #controller_failure{reason = 1}]),
    Why = ?S:down(W),
    true = Why =/= noconnection,
    true = Why =/= noproc,
    vacant(Context, a, Old),
    [#{phase := vacant, incarnation := Old} = slot(Context, a) || _ <- lists:seq(1, 4)],
    {error, stale} = admit(Context, a, Old - 1),
    {ok, New} = admit(Context, a, Old),
    true = New > Old,
    #{handle := {a, New}} = ?S:ready(OA, a),
    Fresh = ?S:publish(Node, a),
    true = Fresh =/= VA,
    ?S:initial(Remote, Fresh),
    ?S:applied(Remote, VB, 7),
    {error, _} = erpc:call(Remote, ?S, outcome, [VA, #query_profile{request = 9, epoch = 0}]),
    {error, stale} = terminate(Context, a, Old),
    #{handle := {a, New}} = ?S:ready(OA, a),
    W2 = ?S:watched(Remote, Fresh),
    ok = terminate(Context, a, New),
    shutdown = ?S:down(W2),
    vacant(Context, a, New),
    #{handle := {b, _}} = ?S:ready(OB, b),
    VB = ?S:virtual(Node, b),
    ?S:applied(Remote, VB, 7),
    #{
        concurrent_single_admission => true,
        capacity_explicit => true,
        fault_without_restart => true,
        explicit_completion_without_restart => true,
        fresh_pid => true,
        fresh_state => true,
        stale_operations_rejected => true,
        old_pid_terminal => true,
        sibling_state_preserved => true
    }.

%% A retired core cannot release its slot until the existing observer receives its promised outputs.
-spec held_output(map(), file:filename(), pid(), node(), map()) -> map().
held_output(Context, Stage, Node, Remote, #{owner := OA, backend := Backend}) ->
    #{phase := vacant, incarnation := Previous} = slot(Context, a),
    {ok, Epoch} = admit(Context, a, Previous),
    #{handle := {a, Epoch}} = ?S:ready(OA, a),
    VA = ?S:publish(Node, a),
    VB = ?S:virtual(Node, b),
    #profile_status{status = ?PROFILE_PENDING} = ?S:call(Remote, VA, #select_profile{
        request = 21, epoch = 0, profile = 1
    }),
    #{received := Received} = hls_domain_fabric:info(Backend),
    ok = hls_recovery_stream_live:delivery(Stage, 0, application, hold),
    {ok, Local} = hls_domain:resolve(OA, {a, Epoch}, actuator),
    gen_server:cast(Local, #apply_profile{request = 21, epoch = 0}),
    frontier(Backend, Received, Received + 2),
    Ref = make_ref(),
    _ = erpc:call(Remote, ?S, delayed, [VA, self(), Ref]),
    frontier(Backend, Received, Received + 4),
    gen_server:cast(Local, #controller_failure{reason = 2}),
    _ = ?S:wait(fun() ->
        case hls_domain_fabric:info(Backend) of
            #{state := #domain_state{phase = Phase, current = Epoch}, received := Received} when
                Phase =:= stopped; Phase =:= failed
            ->
                {ok, ok};
            _ ->
                wait
        end
    end),
    {error, busy} = admit(Context, a, Epoch),
    #{phase := retiring, incarnation := Epoch} = slot(Context, a),
    ?S:applied(Remote, VB, 7),
    receive
        {Ref, _, _} -> error(retirement_overtook_reply)
    after 0 -> ok
    end,
    ok = hls_recovery_stream_live:delivery(Stage, 0, application, resume),
    receive
        {Ref, reply, #profile_status{status = ?PROFILE_APPLIED, request = 21, epoch = 1}} -> ok
    after 5000 -> error(missing_reply)
    end,
    receive
        {Ref, down, R} -> true = R =/= noconnection
    after 5000 -> error(missing_down)
    end,
    vacant(Context, a, Epoch),
    {ok, Fresh} = admit(Context, a, Epoch),
    true = Fresh > Epoch,
    #{handle := {a, Fresh}} = ?S:ready(OA, a),
    New = ?S:publish(Node, a),
    true = New =/= VA,
    ?S:initial(Remote, New),
    #{
        reuse_waited_for_retirement => true,
        reply_before_down => true,
        sibling_progress_during_stall => true
    }.

%% Poll public accepted-output sequence rather than forcing simulator internals.
-spec frontier(pid(), non_neg_integer(), non_neg_integer()) -> ok.
frontier(Backend, Received, Minimum) ->
    _ = ?S:wait(fun() ->
        case hls_domain_fabric:info(Backend) of
            #{received := Received, frontier := F} when F >= Minimum -> {ok, ok};
            _ -> wait
        end
    end),
    ok.

%% Explicit template selection bounds native capacity just as hardware slot selection does.
-spec admit(map(), atom(), non_neg_integer()) -> {ok, pos_integer()} | {error, atom()}.
admit(#{kind := native, supervisor := Sup, owner := Owner} = Context, Id, Expected) when
    Id =:= a; Id =:= b
->
    case slot(Context, Id) of
        #{phase := vacant, incarnation := Expected} ->
            case supervisor:start_child(Sup, hls_temporary_supervisor_otp:spec(Owner, Id)) of
                {ok, _} ->
                    #{handle := {Id, Epoch}} = ?S:ready(Owner, Id),
                    {ok, Epoch};
                {error, {already_started, _}} ->
                    {error, busy};
                {error, already_present} ->
                    {error, busy}
            end;
        #{phase := vacant} ->
            {error, stale};
        _ ->
            {error, busy}
    end;
admit(#{kind := native}, _, _) ->
    {error, unknown_child};
admit(#{kind := rtl, supervisor := Endpoint}, Id, Expected) ->
    admission(hls_supervisor_fabric:start_child(Endpoint, Id, Expected)).

%% An accepted hardware start returns the reserved identity, not a guess from a later status sample.
-spec admission(term()) -> {ok, pos_integer()} | {error, atom()}.
admission({ok, #{incarnation := Epoch}}) -> {ok, Epoch};
admission({error, {Status, _}}) -> {error, Status};
admission({error, Reason}) -> {error, Reason}.

%% A stale completion request must never terminate a later occupant.
-spec terminate(map(), a | b, pos_integer()) -> ok | {error, atom()}.
terminate(#{kind := native, supervisor := Sup} = Context, Id, Epoch) ->
    case slot(Context, Id) of
        #{incarnation := Epoch} -> supervisor:terminate_child(Sup, Id);
        _ -> {error, stale}
    end;
terminate(#{kind := rtl, supervisor := Endpoint}, Id, Epoch) ->
    case hls_supervisor_fabric:terminate_child(Endpoint, Id, Epoch) of
        {ok, _} -> ok;
        {error, {Status, _}} -> {error, Status};
        {error, Reason} -> {error, Reason}
    end.

%% Native OTP has deleted the temporary specification only when it no longer lists the child.
-spec slot(map(), a | b) -> map().
slot(#{kind := native, supervisor := Sup, owner := Owner}, Id) ->
    {ok, #{phase := Phase, target := Target}} = hls_domain:status(Owner, Id),
    Present = lists:keymember(Id, 1, supervisor:which_children(Sup)),
    #{
        id => Id,
        incarnation => Target,
        phase =>
            case not Present andalso (Phase =:= unbound orelse Phase =:= stopped) of
                true -> vacant;
                false -> running
            end
    };
slot(#{kind := rtl, supervisor := Endpoint}, Id) ->
    {ok, Observation} = hls_supervisor_fabric:child_status(Endpoint, Id),
    Observation.

%% Neither elapsed time nor a dead local representative alone proves the slot reusable.
-spec vacant(map(), a | b, non_neg_integer()) -> ok.
vacant(Context, Id, Epoch) ->
    _ = ?S:wait(fun() ->
        case slot(Context, Id) of
            #{phase := vacant, incarnation := Epoch} -> {ok, ok};
            _ -> wait
        end
    end),
    ok.
