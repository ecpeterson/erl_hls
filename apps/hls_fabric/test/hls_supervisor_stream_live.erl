-module(hls_supervisor_stream_live).
-moduledoc "Finite mixed-supervision witness through production framed endpoints and a real distribution peer. The simulator transfers public words only; source callbacks cause every child failure.".
-include("hls_recovery_profile.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").
-export([native/1, run/2, watch/2, delayed/3, outcome/2]).
%% Shared public-pin and real-peer fixture operations.
-export([device/0, native_backend/1, owner/4, rtl_child/3, lease/1, with_peer/3, watched/2, down/1, call/3, apply_profile/3, applied/3, initial/2, publish/2, virtual/2, ready/2, wait/1, save/2]).

-doc "Runs the shared replacement/publication scenario on native actors under an ordinary OTP supervisor.".
-spec native(file:filename()) -> ok.
native(Stage) ->
    ok = filelib:ensure_dir(filename:join(Stage, "unused")),
    Devices = [device(), device()],
    Backends = [native_backend(D) || D <- Devices],
    Owner = owner(
        native, #{a => lists:nth(1, Backends), b => lists:nth(2, Backends)}, hls_domain_erts, Stage
    ),
    {ok, Supervisor} = hls_fpga_supervisor_otp:start_link(Owner, #{
        strategy => one_for_one, intensity => 8, period => 60
    }),
    unlink(Supervisor),
    try
        ready(Owner, a),
        ready(Owner, b),
        Result = with_peer(Owner, Owner, fun(Node, Remote) ->
            Common = common(Node, Remote, Owner, Owner),
            shutdown(fun() -> gen_server:stop(Supervisor, shutdown, 10000) end, Node, Remote),
            Common
        end),
        save(Stage, Result#{passed => true, deployment => native})
    after
        [catch gen_server:stop(P) || P <- [Supervisor, Owner] ++ Backends ++ Devices]
    end.

-doc "Exercises compiled autonomous replacement, bounded output retirement, disconnected observation and host-parent shutdown through the shipped brokers.".
-spec run(file:filename(), file:filename()) -> ok.
run(Stage, NativeFile) ->
    {ok, Bytes} = file:read_file(NativeFile),
    Native = binary_to_term(Bytes),
    ParentPrefix = filename:join(Stage, "parent"),
    ok = hls_recovery_stream_live:session(ParentPrefix, 1),
    {ok, ParentBroker} = hls_fabric:start_link(
        ParentPrefix ++ "_management_tx", ParentPrefix ++ "_management_rx", #{rx_route_limit => 1}
    ),
    unlink(ParentBroker),
    {ok, ParentBackend} = hls_supervisor_fabric:start_link(
        #{management => ParentBroker, session => 1},
        filename:join(Stage, "interface.etf"),
        #{grant => {1, 128}, management_timeout_ms => 5000}
    ),
    unlink(ParentBackend),
    ParentOwner = owner(parent, #{board => ParentBackend}, hls_supervisor_fabric, Stage),
    {ok, {1, 128}} = hls_domain_ids:reserve(ParentOwner, 128),
    {ok, Parent} = hls_shutdown_supervisor:start_link(one_for_one, [{board, ParentOwner}]),
    unlink(Parent),
    _ = ready(ParentOwner, board),
    A = rtl_child(a, 0, Stage),
    B = rtl_child(b, 1, Stage),
    #{owner := OA} = A,
    #{owner := OB} = B,
    Brokers = [ParentBroker | maps:get(brokers, A) ++ maps:get(brokers, B)],
    Leases = [lease(P) || P <- Brokers],
    try
        #{handle := ChildHandle} = ready(OA, a),
        _ = ready(OB, b),
        {error, supervised_child} = hls_domain:stop(OA, ChildHandle, 5000),
        Result = with_peer(OA, OB, fun(Node, Remote) ->
            Common = common(Node, Remote, OA, OB),
            Common = maps:without([passed, deployment], Native),
            Delivery = delayed_restart(Stage, Node, Remote, A, B),
            {NewBackend, NewBrokers, Reconnect} = disconnected_restart(Stage, Node, Remote, A, B),
            shutdown(fun() -> supervisor:terminate_child(Parent, board) end, Node, Remote),
            FreshLeases = [lease(P) || P <- NewBrokers],
            [ok = gen_server:stop(P, normal, 5000) || P <- [NewBackend]],
            [ok = hls_fabric:stop(P) || P <- NewBrokers],
            {
                Common#{
                    delayed_retirement => Delivery,
                    reconnect => Reconnect,
                    native_history_matches => true
                },
                FreshLeases
            }
        end),
        {Report, FreshLeases} = Result,
        [
            catch gen_server:stop(P, normal, 5000)
         || P <- [Parent, ParentOwner, ParentBackend, OA, OB, maps:get(backend, B)]
        ],
        [catch hls_fabric:stop(P) || P <- Brokers],
        ok = file:write_file(filename:join(Stage, "finished"), <<>>, [exclusive]),
        [ok = hls_fabric:await_closed(L, 5000) || L <- Leases ++ FreshLeases],
        save(Stage, Report#{passed => true, deployment => generated_rtl, descriptor_closure => true})
    after
        [
            catch gen_server:stop(P, normal, 5000)
         || P <- [
                Parent,
                ParentOwner,
                ParentBackend,
                OA,
                OB,
                maps:get(backend, A),
                maps:get(backend, B),
                maps:get(device, A),
                maps:get(device, B)
            ]
        ],
        [catch hls_fabric:stop(P) || P <- Brokers]
    end.

-doc "Separate devices retain external effects across all digital domain replacements.".
-spec device() -> pid().
device() ->
    {ok, P} = hls_recovery_device_model:start_link(),
    unlink(P),
    P.
-doc "The native network and hardware network use exactly the same source callbacks.".
-spec native_backend(pid()) -> pid().
native_backend(Device) ->
    Spec = #{
        actors => #{actuator => #{module => hls_recovery_actuator_fixture, mailbox_capacity => 4}},
        routes => #{actuator => #{effect => {external, Device}, reply => {external, Device}}},
        startup => #{}
    },
    {ok, P} = hls_domain_erts:start_link(Spec),
    unlink(P),
    P.
-doc "Child owners observe externally managed lifetimes; only the parent owner allocates replacements in RTL.".
-spec owner(atom(), map(), module(), file:filename()) -> pid().
owner(Name, Backends, Module, Stage) ->
    Store = filename:join(Stage, atom_to_list(Name) ++ ".incarnations"),
    ok = hls_domain_ids:create(Store),
    {ok, P} = hls_domain:start_link(
        maps:map(fun(_, _) -> automatic end, Backends),
        #{module => Module, endpoints => Backends, incarnation_file => Store}
    ),
    unlink(P),
    P.
-doc "Independent brokers own each child's physical lanes, with only effects sent to its external device.".
-spec rtl_child(atom(), non_neg_integer(), file:filename()) -> map().
rtl_child(Id, Index, Stage) ->
    Device = device(),
    Prefix = filename:join(Stage, "domain" ++ integer_to_list(Index)),
    Interface = filename:join(Stage, "child_" ++ integer_to_list(Index) ++ ".etf"),
    ok = hls_recovery_stream_live:session(Prefix, 1),
    {Backend, Brokers} = hls_recovery_stream_live:backend(Prefix, Interface, Device, 1),
    #{
        id => Id,
        index => Index,
        owner => owner(Id, #{Id => Backend}, hls_domain_fabric, Stage),
        backend => Backend,
        brokers => Brokers,
        device => Device,
        interface => Interface,
        prefix => Prefix
    }.
-doc "Keep a lease before stopping its broker so descriptor closure is independently observable.".
-spec lease(pid()) -> term().
lease(Broker) ->
    #{io := #{lease := Lease}} = hls_fabric:info(Broker),
    Lease.

-doc "The same remote callers and virtual-node publication API are used for both deployments.".
-spec with_peer(pid(), pid(), fun((pid(), node()) -> term())) -> term().
with_peer(OA, OB, Fun) ->
    hls_test_nodes:distribution(),
    {ok, _} = application:ensure_all_started(crypto),
    Name = list_to_atom(
        "supervisor_stream_" ++ integer_to_list(erlang:unique_integer([positive])) ++ "@localhost"
    ),
    {ok, Node} = hls_node:start_link(
        Name,
        #{},
        [
            #{name => a, domain => #{owner => OA, id => a}},
            #{name => b, domain => #{owner => OB, id => b}}
        ],
        #{}
    ),
    unlink(Node),
    {Peer, Remote} = hls_test_nodes:start_peer(),
    try
        Fun(Node, Remote)
    after
        peer:stop(Peer),
        hls_node:stop(Node)
    end.
%% Public histories compare fresh identity/state and sibling preservation, not numeric failure encodings.
-spec common(pid(), node(), pid(), pid()) -> map().
common(Node, Remote, OA, OB) ->
    VA = virtual(Node, a),
    VB = virtual(Node, b),
    #{handle := {a, Old}} = ready(OA, a),
    apply_profile(Remote, VB, 7),
    apply_profile(Remote, VA, 9),
    W = watched(Remote, VA),
    ok = erpc:call(Remote, gen_server, cast, [VA, #controller_failure{reason = 1}]),
    Reason = down(W),
    true = Reason =/= noconnection,
    true = Reason =/= noproc,
    _ = changed(OA, a, Old),
    New = publish(Node, a),
    true = New =/= VA,
    initial(Remote, New),
    applied(Remote, VB, 7),
    VB = virtual(Node, b),
    #{handle := {b, _}} = ready(OB, b),
    {error, _} = erpc:call(Remote, ?MODULE, outcome, [VA, #query_profile{request = 9, epoch = 0}]),
    #{
        fresh_pid => true,
        fresh_state => true,
        sibling_state_preserved => true,
        old_pid_terminal => true,
        ordinary_source_failure => true
    }.

%% Delay accepted replies while hardware completes replacement before any new virtual PID is allowed.
-spec delayed_restart(file:filename(), pid(), node(), map(), map()) -> map().
delayed_restart(Stage, Node, Remote, #{owner := OA, backend := Backend}, _B) ->
    VA = virtual(Node, a),
    VB = virtual(Node, b),
    #{handle := {a, Old}} = ready(OA, a),
    #profile_status{status = ?PROFILE_PENDING} = call(Remote, VA, #select_profile{
        request = 21, epoch = 0, profile = 1
    }),
    #{received := Received} = hls_domain_fabric:info(Backend),
    ok = hls_recovery_stream_live:delivery(Stage, 0, application, hold),
    {ok, Local} = hls_domain:resolve(OA, {a, Old}, actuator),
    %% This independent producer can progress while the remote connection waits for admission.
    gen_server:cast(Local, #apply_profile{request = 21, epoch = 0}),
    _ = wait(fun() ->
        case hls_domain_fabric:info(Backend) of
            #{received := Received, frontier := F} when F >= Received + 2 -> {ok, F};
            _ -> wait
        end
    end),
    Ref = make_ref(),
    Watcher = erpc:call(Remote, ?MODULE, delayed, [VA, self(), Ref]),
    _ = wait(fun() ->
        case hls_domain_fabric:info(Backend) of
            #{received := Received, frontier := F} when F >= Received + 4 -> {ok, F};
            _ -> wait
        end
    end),
    gen_server:cast(Local, #controller_failure{reason = 2}),
    _ = wait(fun() ->
        case hls_domain_fabric:info(Backend) of
            #{state := #domain_state{phase = ready, current = New}, received := Received} when
                New > Old
            ->
                {ok, New};
            _ ->
                wait
        end
    end),
    {error, _} = hls_node:publish_domain(Node, a),
    applied(Remote, VB, 7),
    receive
        {Ref, _, _} -> error(retirement_overtook_held_output)
    after 0 -> ok
    end,
    ok = hls_recovery_stream_live:delivery(Stage, 0, application, resume),
    receive
        {Ref, reply, #profile_status{status = ?PROFILE_APPLIED, request = 21, epoch = 1}} -> ok
    after 5000 -> error(missing_prior_reply)
    end,
    receive
        {Ref, down, Why} ->
            true = Why =/= noconnection,
            true = Why =/= noproc
    after 5000 -> error(missing_ordered_down)
    end,
    _ = changed(OA, a, Old),
    Fresh = publish(Node, a),
    true = Fresh =/= VA,
    initial(Remote, Fresh),
    true = is_pid(Watcher),
    #{
        autonomous_replacement_before_delivery => true,
        reply_before_down => true,
        publication_waited_for_retirement => true,
        sibling_progress_during_stall => true
    }.

%% Lose observation during a source fault; reconnect selects actual current identity without inventing missed exits.
-spec disconnected_restart(file:filename(), pid(), node(), map(), map()) -> {pid(), [pid()], map()}.
disconnected_restart(
    Stage,
    Node,
    Remote,
    #{
        owner := OA,
        backend := Backend,
        brokers := Brokers,
        interface := Interface,
        device := Device,
        prefix := Prefix
    },
    _B
) ->
    VA = virtual(Node, a),
    VB = virtual(Node, b),
    #{handle := {a, Old}} = ready(OA, a),
    W = watched(Remote, VA),
    #{received := Before} = hls_domain_fabric:info(Backend),
    ok = hls_recovery_stream_live:delivery(Stage, 0, management, hold),
    ok = erpc:call(Remote, gen_server, cast, [VA, #controller_failure{reason = 3}]),
    %% The admission acknowledgement comes from actual hardware before observer termination.
    _ = wait(fun() ->
        case hls_domain_fabric:info(Backend) of
            #{pending := 0, received := After} when After > Before -> {ok, ok};
            _ -> wait
        end
    end),
    ok = hls_domain_fabric:stop(Backend),
    noconnection = down(W),
    OldLeases = [lease(P) || P <- Brokers],
    [ok = hls_fabric:stop(P) || P <- Brokers],
    transport(Prefix, 2),
    [ok = hls_fabric:await_closed(L, 5000) || L <- OldLeases],
    ok = hls_recovery_stream_live:delivery(Stage, 0, management, resume),
    ok = hls_recovery_stream_live:session(Prefix, 2),
    FreshPrefix = Prefix ++ "_transport2",
    {Fresh, NewBrokers} = hls_recovery_stream_live:backend(FreshPrefix, Interface, Device, 2),
    {ok, #{state := #domain_state{phase = ready, current = New}}} = hls_domain_fabric:status(Fresh),
    true = New > Old,
    {error, incarnation_not_ready} = hls_domain:reattach(OA, {a, Old}, Fresh),
    %% Attachment is retained when the exact watch acknowledgement is still in flight.
    case hls_domain:reattach(OA, {a, New}, Fresh) of
        {ok, _} -> ok;
        {error, publication_pending} -> ok
    end,
    #{handle := {a, New}} = ready(OA, a),
    {error, changed_incarnation} = hls_node:reattach_domain(Node, a),
    NewPid = publish(Node, a),
    true = NewPid =/= VA,
    initial(Remote, NewPid),
    applied(Remote, VB, 7),
    {error, _} = erpc:call(Remote, ?MODULE, outcome, [VA, #query_profile{request = 0, epoch = 0}]),
    {Fresh, NewBrokers, #{
        prior_monitor_noconnection => true,
        newer_incarnation_explicitly_selected => true,
        same_incarnation_reattach_rejected => true,
        old_pid_not_revived => true,
        sibling_preserved => true
    }}.

%% Real transport closure precedes the session sideband; the simulator only rotates FIFO descriptors.
-spec transport(file:filename(), pos_integer()) -> ok.
transport(Prefix, Generation) ->
    Path = Prefix ++ "_transport",
    Value = integer_to_binary(Generation),
    ok = file:write_file(Path ++ ".next", Value),
    ok = file:rename(Path ++ ".next", Path ++ ".control"),
    _ = wait(fun() ->
        case file:read_file(Path ++ ".ack") of
            {ok, B} ->
                case string:trim(B) =:= Value of
                    true -> {ok, ok};
                    false -> wait
                end;
            _ ->
                wait
        end
    end),
    ok.
%% Explicit host-parent termination reaches both child lifetimes through the framed production adapter.
-spec shutdown(fun(() -> ok), pid(), node()) -> ok.
shutdown(Stop, Node, Remote) ->
    A = watched(Remote, virtual(Node, a)),
    B = watched(Remote, virtual(Node, b)),
    ok = Stop(),
    shutdown = down(A),
    shutdown = down(B),
    ok.

-doc "Returns call failure as a value so the witness can check a terminal old virtual PID.".
-spec outcome(pid(), tuple()) -> {ok, term()} | {error, term()}.
outcome(Actor, Message) ->
    try hls_statem:call(Actor, Message) of
        R -> {ok, R}
    catch
        exit:R -> {error, R}
    end.
-doc "Installs a real remote monitor and confirms actor reachability before reporting readiness.".
-spec watch(pid(), pid()) -> pid().
watch(Actor, Parent) ->
    spawn(fun() ->
        M = monitor(process, Actor),
        #profile_status{} = hls_statem:call(Actor, #query_profile{request = 0, epoch = 0}),
        Parent ! {watching, self()},
        receive
            {'DOWN', M, process, Actor, Reason} -> Parent ! {down, self(), Reason}
        after 10000 -> error(monitor_timeout)
        end
    end).
-doc "Checks mailbox order of a remote accepted reply and the following old-incarnation DOWN.".
-spec delayed(pid(), pid(), reference()) -> pid().
delayed(Actor, Parent, Ref) ->
    spawn(fun() ->
        M = monitor(process, Actor),
        Reply = make_ref(),
        Actor ! {'$gen_call', {self(), Reply}, #query_profile{request = 21, epoch = 0}},
        receive
            {Reply, R = #profile_status{}} -> Parent ! {Ref, reply, R};
            {'DOWN', M, process, Actor, Reason} -> error({down_before_reply, Reason})
        after 5000 -> error(reply_timeout)
        end,
        receive
            {'DOWN', M, process, Actor, Why} -> Parent ! {Ref, down, Why}
        after 5000 -> error(down_timeout)
        end
    end).
-doc "Ready acknowledgement closes the race between remote monitor installation and the requested fault.".
-spec watched(node(), pid()) -> pid().
watched(Remote, Actor) ->
    W = erpc:call(Remote, ?MODULE, watch, [Actor, self()]),
    receive
        {watching, W} -> W
    after 5000 -> error(monitor_timeout)
    end.
-doc "This monitor was installed before the failure stimulus.".
-spec down(pid()) -> term().
down(W) ->
    receive
        {down, W, Reason} -> Reason
    after 5000 -> error(down_timeout)
    end.
-doc "Compiler-generated typed call plumbing is exercised through a different real ERTS node.".
-spec call(node(), pid(), tuple()) -> tuple().
call(Remote, Actor, Message) -> erpc:call(Remote, hls_statem, call, [Actor, Message]).
-doc "Applying a profile leaves a marker that detects accidental sibling reset.".
-spec apply_profile(node(), pid(), pos_integer()) -> ok.
apply_profile(Remote, Actor, Request) ->
    #profile_status{status = ?PROFILE_PENDING} = call(Remote, Actor, #select_profile{
        request = Request, epoch = 0, profile = 1
    }),
    ok = erpc:call(Remote, gen_server, cast, [Actor, #apply_profile{request = Request, epoch = 0}]),
    applied(Remote, Actor, Request).
-doc "An actual successful query must retain the selected source state.".
-spec applied(node(), pid(), pos_integer()) -> ok.
applied(Remote, Actor, Request) ->
    #profile_status{status = ?PROFILE_APPLIED, epoch = 1} = call(Remote, Actor, #query_profile{
        request = Request, epoch = 0
    }),
    ok.
-doc "A successor contains fresh digital state rather than replayed predecessor history.".
-spec initial(node(), pid()) -> ok.
initial(Remote, Actor) ->
    #profile_status{status = ?PROFILE_UNKNOWN, epoch = 0} = call(Remote, Actor, #query_profile{
        request = 1, epoch = 0
    }),
    ok.
-doc "Publication uses the already existing per-connection predecessor-retirement acknowledgement.".
-spec publish(pid(), atom()) -> pid().
publish(Node, Domain) ->
    {ok, #{actors := #{actuator := Actor}}} = hls_node:publish_domain(Node, Domain),
    Actor.
-doc "Stable service names locate the current published PID without reviving earlier PIDs.".
-spec virtual(pid(), atom()) -> pid().
virtual(Node, Domain) ->
    #{actors := #{actuator := Actor}} = maps:get(Domain, hls_node:services(Node)),
    Actor.
-doc "Endpoint presence is required in addition to the controller's ready phase.".
-spec ready(pid(), atom()) -> hls_domain:snapshot().
ready(Owner, Domain) ->
    wait(fun() ->
        case hls_domain:status(Owner, Domain) of
            {ok, S = #{phase := ready, actors := Actors}} when map_size(Actors) > 0 -> {ok, S};
            _ -> wait
        end
    end).
%% A later ready identity must be independently observed before publication.
-spec changed(pid(), atom(), pos_integer()) -> hls_domain:snapshot().
changed(Owner, Domain, Old) ->
    wait(fun() ->
        case hls_domain:status(Owner, Domain) of
            {ok, S = #{phase := ready, handle := {Domain, New}, actors := Actors}} when
                New > Old, map_size(Actors) > 0
            ->
                {ok, S};
            _ ->
                wait
        end
    end).
-doc "Timeouts bound the witness; no elapsed deadline manufactures retirement evidence.".
-spec wait(fun(() -> wait | {ok, term()})) -> term().
wait(Fun) -> wait(Fun, erlang:monotonic_time(millisecond) + 10000).
%% Repeated observations never replay source requests or lifecycle mutations.
-spec wait(fun(() -> wait | {ok, term()}), integer()) -> term().
wait(Fun, End) ->
    case Fun() of
        {ok, R} ->
            R;
        wait ->
            true = erlang:monotonic_time(millisecond) < End,
            receive
            after 1 -> wait(Fun, End)
            end
    end.
-doc "Evidence records explicitly distinguish a finite observed history from a general guarantee.".
-spec save(file:filename(), map()) -> ok.
save(Stage, Result) ->
    ok = file:write_file(filename:join(Stage, "result.etf"), term_to_binary(Result), [exclusive]),
    file:write_file(filename:join(Stage, "result.json"), json:encode(Result), [exclusive]).
