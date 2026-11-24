-module(hls_domain_channel_instance).
-moduledoc """
An ordinary OTP child binding one mailbox after two supervised domains become ready.

Place this worker after the two hls_domain_instance children of a one_for_all
supervisor. The deployment owners and shared management adapter outlive that
subtree. This worker only observes domain owners and binds or fences the mailbox;
OTP owns restart order and intensity. Application packets never pass through it.

A lost bind reply is reconciled by inspection of its exact generation and endpoint
pair. Connection loss leaves this child unavailable, without replacing either
actor or replaying work. Replacing a dead local adapter requires explicit reattach
and matching device evidence before and after acquiring its local capability.
A canonical rejected admission is a startup failure reported to OTP. An ordered
inspection proving that a lost command left the exact previous binding unchanged
permits one checked management retry; application work is never replayed.
A fresh worker does not adopt an old live binding. General host restart therefore
requires both endpoint incarnations to advance, rather than pretending continuity.
""".
-behaviour(gen_server).

%% Ordinary supervisor child and explicit transport recovery.
-export([start_link/5, status/1, reattach/2]).
-export_type([backend_ref/0, endpoint/0, options/0, evidence/0]).
%% OTP callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-doc "A PID or ordinary local registered name, resolved only at startup or explicit reattachment; live workers never follow a name automatically.".
-type backend_ref() :: pid() | atom().

-doc "One deployment owner and its declared domain; no application endpoint is routed through this worker.".
-type endpoint() :: {pid(), hls_domain:domain()}.
-doc "Finite observation cadence and deadline; neither expiration authorizes actor replacement.".
-type options() :: #{poll_ms => pos_integer(), request_timeout_ms => pos_integer()}.
-doc "Last exact binding evidence, initial admission, or transport uncertainty; readiness is not a liveness guarantee.".
-type evidence() ::
    starting
    | {error, noconnection}
    | #{
        phase := ready,
        status := hls_domain_channel:status(),
        generation := hls_nums:u64(),
        source_incarnation := hls_nums:u64(),
        destination_incarnation := hls_nums:u64(),
        packet_sequence := hls_nums:u32(),
        active := boolean(),
        fault := boolean()
    }.
%% Bounded read-only owner probes carry no lifecycle or channel mutation authority.
-type probe() :: #{
    pid := pid(), monitor := reference(), timer := reference(), role := source | destination
}.
%% A binding is exact; a stable domain name cannot silently acquire a successor channel.
-type binding() :: none | {hls_nums:u64(), hls_nums:u64(), hls_nums:u64()}.
%% Each probe records a domain lifecycle result, never application data.
-type observations() :: #{
    source => {ok, hls_domain:snapshot()} | {error, term()},
    destination => {ok, hls_domain:snapshot()} | {error, term()}
}.
%% One management request and at most two owner observations are outstanding.
-record(instance, {
    backend :: pid(),
    backend_monitor :: reference(),
    channel :: hls_nums:u32(),
    source :: endpoint(),
    destination :: endpoint(),
    owner_monitors = [] :: [reference()],
    authority = none :: none | reference(),
    binding = none :: binding(),
    pending = none :: none | hls_domain_channel_wire:command(),
    retry_bind = none :: none | hls_domain_channel_wire:command(),
    bind_retries = 0 :: 0..1,
    fence_retries = 0 :: 0..1,
    snapshot = none :: none | hls_domain_channel_wire:snapshot(),
    evidence = starting :: evidence(),
    exchange = none ::
        none | #{id := gen_server:request_id(), kind := term(), timer := reference()},
    probes = #{} :: #{reference() => probe()},
    observations = #{} :: observations(),
    reconnect = none ::
        none
        | #{
            backend := pid(),
            from := gen_server:from(),
            before => hls_domain_channel_wire:snapshot()
        },
    poll_timer = none :: none | reference(),
    poll_ms = 100 :: pos_integer(),
    timeout_ms = 1000 :: pos_integer()
}).

-doc "Starts promptly; channel admission follows readiness of both existing domain owners. A registered adapter name in the OTP child specification allows later child restarts to resolve a replacement adapter.".
-spec start_link(backend_ref(), hls_nums:u32(), endpoint(), endpoint(), options()) ->
    gen_server:start_ret().
start_link(Backend, Channel, Source, Destination, Options) ->
    gen_server:start_link(
        ?MODULE, {resolve_backend(Backend), Channel, Source, Destination, Options}, []
    ).

-doc "Returns the last observation without blocking on management or application traffic.".
-spec status(pid()) -> evidence().
status(Instance) -> gen_server:call(Instance, status).

-doc "Reconciles a replacement adapter after the previous local process is gone. Incompatible generations reject; no actor reset or application replay is requested.".
-spec reattach(pid(), backend_ref()) -> ok | {error, term()}.
reattach(Instance, Backend) ->
    gen_server:call(Instance, {reattach, resolve_backend(Backend)}, infinity).

%% Resolve ordinary local registration once, retaining a concrete process identity afterward.
-spec resolve_backend(backend_ref()) -> pid().
resolve_backend(Backend) when is_pid(Backend), node(Backend) =:= node() -> Backend;
resolve_backend(Name) when is_atom(Name) ->
    case whereis(Name) of
        Pid when is_pid(Pid) -> Pid;
        undefined -> error({channel_backend_unavailable, Name})
    end.

-doc "Monitors deployment authorities and schedules admission without blocking the supervisor.".
-spec init({pid(), hls_nums:u32(), endpoint(), endpoint(), options()}) -> {ok, #instance{}}.
init({Backend, Channel, {SourceOwner, _} = Source, {DestinationOwner, _} = Destination, Options}) ->
    process_flag(trap_exit, true),
    true = node(Backend) =:= node(),
    [] = maps:keys(Options) -- [poll_ms, request_timeout_ms],
    Poll = maps:get(poll_ms, Options, 100),
    Timeout = maps:get(request_timeout_ms, Options, 1000),
    true = is_integer(Poll) andalso Poll > 0 andalso is_integer(Timeout) andalso Timeout > 0,
    State = #instance{
        backend = Backend,
        backend_monitor = monitor(process, Backend),
        channel = Channel,
        source = Source,
        destination = Destination,
        owner_monitors = [
            monitor(process, Pid)
         || Pid <- lists:usort([SourceOwner, DestinationOwner])
        ],
        poll_ms = Poll,
        timeout_ms = Timeout
    },
    {ok, schedule(State)}.

-doc "Exposes observations and allows explicit transport replacement only after local adapter death.".
-spec handle_call(term(), gen_server:from(), #instance{}) ->
    {reply, term(), #instance{}} | {noreply, #instance{}}.
%% Status does not imply a new remote observation or application handshake.
handle_call(status, _From, State) ->
    {reply, State#instance.evidence, State};
%% Reattachment first checks the surviving binding before claiming the fresh adapter.
handle_call({reattach, New}, From, State = #instance{backend = Old, reconnect = none}) when
    is_pid(New), node(New) =:= node(), New =/= Old
->
    case is_process_alive(Old) orelse not is_process_alive(New) of
        true ->
            {reply, {error, transport_not_replaced}, State};
        false ->
            Clean = cancel_work(State),
            Next = Clean#instance{
                reconnect = #{backend => New, from => From},
                authority = none,
                evidence = {error, noconnection}
            },
            {noreply, issue(reconnect_before, {status, State#instance.channel}, New, Next)}
    end;
%% A second replacement cannot race the first binding reconciliation.
handle_call({reattach, _}, _From, State) ->
    {reply, {error, busy}, State};
%% No message here can activate, replace, or send application work to a domain.
handle_call(_, _From, State) ->
    {reply, {error, unsupported}, State}.

-doc "Ignores casts; this child has no application data or reset-command forwarding interface.".
-spec handle_cast(term(), #instance{}) -> {noreply, #instance{}}.
handle_cast(_, State) -> {noreply, State}.

-doc "Combines bounded owner observations with exact framed channel evidence.".
-spec handle_info(term(), #instance{}) -> {noreply, #instance{}} | {stop, term(), #instance{}}.
%% One poll starts only when previous probes and management work have completed.
handle_info(poll, State) ->
    progress(State#instance{poll_timer = none});
%% Probe results precede the monitored worker's normal DOWN signal.
handle_info({owner_observation, Ref, Result}, State) ->
    probe_result(Ref, Result, State);
%% Read-only observation timeouts discard workers, never actor state.
handle_info({probe_timeout, Ref}, State) ->
    probe_result(Ref, {error, noconnection}, State);
%% Abandoning a management alias does not mean its transmitted command failed.
handle_info({request_timeout, Id}, State = #instance{exchange = #{id := Id}}) ->
    _ = gen_server:receive_response(Id, 0),
    management_result({error, noconnection}, State);
%% An absent adapter says nothing about the continuing device incarnation.
handle_info(
    {'DOWN', Ref, process, _Pid, _Reason},
    State = #instance{backend_monitor = Ref, reconnect = Reconnect}
) when
    Reconnect =/= none
->
    {noreply, State#instance{authority = none, evidence = {error, noconnection}}};
%% Outside explicit reattachment, cancel local probes and retain connection uncertainty.
handle_info({'DOWN', Ref, process, _Pid, _Reason}, State = #instance{backend_monitor = Ref}) ->
    {noreply,
        schedule((cancel_work(State))#instance{authority = none, evidence = {error, noconnection}})};
%% Losing a deployment owner is an actual supervision failure, unlike losing its transport.
handle_info({'DOWN', Ref, process, _Pid, Reason} = Message, State) ->
    case lists:member(Ref, State#instance.owner_monitors) of
        true -> {stop, {domain_owner_down, Reason}, State};
        false -> management_message(Message, State)
    end;
%% Trapped supervisor shutdown runs terminate; unrelated exits carry no channel authority.
handle_info({'EXIT', _Pid, shutdown}, State) ->
    {stop, shutdown, State};
%% A structured supervisor shutdown preserves its supplied reason.
handle_info({'EXIT', _Pid, {shutdown, _} = Reason}, State) ->
    {stop, Reason, State};
%% Correlated asynchronous replies retain this process as the mutation owner.
handle_info(Message, State) ->
    management_message(Message, State).

%% Match request-monitor errors as well as replies before discarding unrelated process messages.
-spec management_message(term(), #instance{}) ->
    {noreply, #instance{}} | {stop, term(), #instance{}}.
management_message(Message, State = #instance{exchange = #{id := Id}}) ->
    case gen_server:check_response(Message, Id) of
        {reply, Reply} -> management_result(Reply, State);
        {error, _} -> management_result({error, noconnection}, State);
        _ -> {noreply, State}
    end;
management_message(_, State) ->
    {noreply, State}.

-doc "Stops read-only probes. The surviving adapter observes owner death and fences the resulting exact generation, including a bind whose reply was lost.".
-spec terminate(term(), #instance{}) -> ok.
terminate(_Reason, State) ->
    _ = cancel_work(State),
    case State#instance.reconnect of
        none -> ok;
        #{from := From} -> gen_server:reply(From, {error, noconnection})
    end,
    ok.

%% A single timer prevents unavailable transports from accumulating observation work.
-spec schedule(#instance{}) -> #instance{}.
schedule(State = #instance{poll_timer = none}) ->
    State#instance{poll_timer = erlang:send_after(State#instance.poll_ms, self(), poll)};
schedule(State) ->
    State.

%% Attachment waits for the adapter's old-owner barrier; ready owner snapshots alone cannot bypass it.
-spec progress(#instance{}) -> {noreply, #instance{}}.
progress(State = #instance{exchange = Exchange, probes = Probes, reconnect = Reconnect}) when
    Exchange =/= none; map_size(Probes) > 0; Reconnect =/= none
->
    {noreply, State};
progress(State = #instance{backend = Backend, authority = none, channel = Channel}) ->
    case is_process_alive(Backend) of
        true -> {noreply, issue(attach, {attach, Channel, self()}, Backend, State)};
        false -> {noreply, schedule(State#instance{evidence = {error, noconnection}})}
    end;
progress(State) ->
    Next = State#instance{observations = #{}},
    {noreply,
        start_probe(
            destination,
            State#instance.destination,
            start_probe(source, State#instance.source, Next)
        )}.

%% Public owner APIs are read in bounded workers; no mutation capability leaves the coordinator.
-spec start_probe(source | destination, endpoint(), #instance{}) -> #instance{}.
start_probe(Role, {Owner, Domain}, State) ->
    Parent = self(),
    Ref = make_ref(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Result =
            try
                hls_domain:status(Owner, Domain)
            catch
                exit:_ -> {error, noconnection}
            end,
        Parent ! {owner_observation, Ref, Result}
    end),
    Timer = erlang:send_after(State#instance.timeout_ms, self(), {probe_timeout, Ref}),
    State#instance{
        probes = (State#instance.probes)#{
            Ref => #{pid => Pid, monitor => Monitor, timer => Timer, role => Role}
        }
    }.

%% Once both owner reads complete, use a fresh channel observation from the ordered management lane.
-spec probe_result(reference(), term(), #instance{}) -> {noreply, #instance{}}.
probe_result(Ref, Result, State) ->
    case maps:take(Ref, State#instance.probes) of
        error ->
            {noreply, State};
        {#{pid := Pid, monitor := Monitor, timer := Timer, role := Role}, Rest} ->
            erlang:cancel_timer(Timer),
            demonitor(Monitor, [flush]),
            exit(Pid, kill),
            Next = State#instance{
                probes = Rest, observations = (State#instance.observations)#{Role => Result}
            },
            case map_size(Rest) of
                0 ->
                    {noreply,
                        issue(
                            inspect, {status, State#instance.channel}, State#instance.backend, Next
                        )};
                _ ->
                    {noreply, Next}
            end
    end.

%% Management requests remain in the owner process and use one response alias at a time.
-spec issue(term(), hls_domain_channel_fabric:request(), pid(), #instance{}) -> #instance{}.
issue(Kind, Request, Backend, State) ->
    Id = hls_domain_channel_fabric:send_request(Backend, Request),
    Timer = erlang:send_after(State#instance.timeout_ms, self(), {request_timeout, Id}),
    State#instance{exchange = #{id => Id, kind => Kind, timer => Timer}}.

%% Dispatch a completed exchange after removing its deadline and alias bookkeeping.
-spec management_result(term(), #instance{}) ->
    {noreply, #instance{}} | {stop, term(), #instance{}}.
management_result(Result, State = #instance{exchange = #{kind := Kind, timer := Timer}}) ->
    erlang:cancel_timer(Timer),
    management_reply(Kind, Result, State#instance{exchange = none}).

%% Local claim failure does not authorize fencing somebody else's channel.
-spec management_reply(term(), term(), #instance{}) ->
    {noreply, #instance{}} | {stop, term(), #instance{}}.
management_reply(attach, {ok, Authority}, State) ->
    {noreply, schedule(State#instance{authority = Authority})};
management_reply(attach, {error, Reason}, State) when Reason =:= retiring; Reason =:= owned ->
    {noreply, schedule(State)};
%% Replacement transport must observe the same exact binding before and after attachment.
management_reply(reconnect_before, {ok, Snapshot}, State = #instance{reconnect = Reconnect}) ->
    case compatible(Snapshot, State) of
        true ->
            #{backend := Backend} = Reconnect,
            Next = State#instance{reconnect = Reconnect#{before => Snapshot}},
            {noreply,
                issue(reconnect_attach, {attach, State#instance.channel, self()}, Backend, Next)};
        false ->
            reconnect_failed(incompatible_binding, State)
    end;
management_reply(
    reconnect_attach, {ok, Authority}, State = #instance{reconnect = #{backend := Backend}}
) ->
    demonitor(State#instance.backend_monitor, [flush]),
    Next = State#instance{
        backend = Backend, backend_monitor = monitor(process, Backend), authority = Authority
    },
    {noreply, issue(reconnect_after, {status, State#instance.channel}, Backend, Next)};
management_reply(
    reconnect_after,
    {ok, Snapshot},
    State = #instance{reconnect = #{backend := Backend, from := From, before := Before}}
) ->
    case identity(Snapshot) =:= identity(Before) of
        true ->
            gen_server:reply(From, ok),
            Next = State#instance{backend = Backend, reconnect = none},
            reconcile(Snapshot, Next);
        false ->
            gen_server:reply(From, {error, binding_changed}),
            {stop, channel_binding_changed, State#instance{reconnect = none}}
    end;
management_reply(Kind, Failure, State) when
    Kind =:= reconnect_before; Kind =:= reconnect_attach; Kind =:= reconnect_after
->
    reconnect_failed(Failure, State);
%% A missing mutation response leaves the exact operation pending for ordered inspection.
management_reply(_Kind, {error, noconnection}, State) ->
    {noreply, schedule(State#instance{evidence = {error, noconnection}})};
management_reply(_Kind, {error, {outcome_unknown, _}}, State) ->
    {noreply, schedule(State#instance{evidence = {error, noconnection}})};
management_reply(mutate, {error, busy}, State) ->
    {noreply, schedule(State#instance{pending = none})};
management_reply(_Kind, {error, busy}, State) ->
    {noreply, schedule(State)};
%% Only an ordered inspection can prove a lost command never changed the prior binding.
management_reply(inspect, {ok, Snapshot}, State) ->
    reconcile(Snapshot, State);
%% A direct canonical rejection is an admission failure, not transport uncertainty.
management_reply(_Kind, {ok, Snapshot}, State) ->
    observe(Snapshot, State);
management_reply(_Kind, {error, Reason}, State) ->
    {stop, {channel_management_failed, Reason}, State}.

%% Preserve a failed explicit reattachment as uncertainty without adopting a different live binding.
-spec reconnect_failed(term(), #instance{}) -> {noreply, #instance{}}.
reconnect_failed(Reason, State = #instance{reconnect = #{from := From}}) ->
    gen_server:reply(From, {error, Reason}),
    {noreply, schedule(State#instance{reconnect = none, evidence = {error, noconnection}})}.

%% Retry at most once after exact ordered evidence excludes a lost mutation; binds require fresh owner reads.
-spec reconcile(hls_domain_channel_wire:snapshot(), #instance{}) ->
    {noreply, #instance{}} | {stop, term(), #instance{}}.
reconcile(
    Snapshot = #{active := false, fault := false},
    State = #instance{
        pending = {bind, _, _, _} = Command, snapshot = Before
    }
) when Before =/= none ->
    case identity(Snapshot) =:= identity(Before) andalso not maps:get(active, Before) of
        true ->
            case State#instance.bind_retries of
                0 ->
                    {noreply,
                        schedule(State#instance{
                            pending = none,
                            retry_bind = Command,
                            bind_retries = 1,
                            snapshot = Snapshot,
                            evidence = starting
                        })};
                1 ->
                    {noreply, schedule(State#instance{evidence = {error, noconnection}})}
            end;
        false ->
            observe(Snapshot, State)
    end;
reconcile(
    Snapshot = #{active := true, fault := false, generation := Generation},
    State = #instance{
        pending = {fence, Generation} = Command, snapshot = Before
    }
) when Before =/= none ->
    case identity(Snapshot) =:= identity(Before) of
        true ->
            case State#instance.fence_retries of
                0 -> mutate(Command, State#instance{fence_retries = 1, snapshot = Snapshot});
                1 -> {noreply, schedule(State#instance{evidence = {error, noconnection}})}
            end;
        false ->
            observe(Snapshot, State)
    end;
reconcile(Snapshot, State) ->
    observe(Snapshot, State).

%% Pending bind identity allows confirmation after reply loss, but never a duplicate mutation.
-spec observe(hls_domain_channel_wire:snapshot(), #instance{}) ->
    {noreply, #instance{}} | {stop, term(), #instance{}}.
observe(#{fault := true} = Snapshot, State) ->
    {stop, {channel_fault, Snapshot}, State#instance{snapshot = Snapshot}};
observe(Snapshot, State = #instance{pending = {bind, Expected, Source, Destination}}) ->
    case Snapshot of
        #{
            generation := Generation,
            source_incarnation := Source,
            destination_incarnation := Destination,
            active := true
        } when
            Generation =:= Expected + 1
        ->
            observe(Snapshot, State#instance{
                pending = none, binding = {Generation, Source, Destination}
            });
        _ ->
            {stop, {channel_bind_not_established, Snapshot}, State#instance{snapshot = Snapshot}}
    end;
observe(Snapshot = #{active := false}, State = #instance{pending = {fence, _}}) ->
    observe(Snapshot, State#instance{pending = none});
observe(Snapshot, State = #instance{pending = {fence, _}}) ->
    {stop, {channel_fence_not_established, Snapshot}, State#instance{snapshot = Snapshot}};
observe(Snapshot, State = #instance{binding = {Generation, Source, Destination}}) ->
    case Snapshot of
        #{
            generation := Generation,
            source_incarnation := Source,
            destination_incarnation := Destination,
            active := true
        } ->
            Evidence =
                case pair(State) of
                    {Source, Destination} -> Snapshot#{phase => ready};
                    _ -> {error, noconnection}
                end,
            {noreply, schedule(State#instance{snapshot = Snapshot, evidence = Evidence})};
        _ ->
            {stop, {channel_binding_closed, Snapshot}, State#instance{snapshot = Snapshot}}
    end;
%% A reconciled retry remains pinned to its original pair, even if newer owner snapshots appear.
observe(Snapshot, State = #instance{retry_bind = {bind, Expected, Source, Destination} = Command}) ->
    case {Snapshot, pair(State)} of
        {#{active := false, generation := Expected}, {Source, Destination}} ->
            mutate(Command, State#instance{snapshot = Snapshot, retry_bind = none});
        _ ->
            {noreply,
                schedule(State#instance{snapshot = Snapshot, evidence = {error, noconnection}})}
    end;
%% A newly started worker cannot adopt a previous child's live channel, even if owners still report ready.
observe(Snapshot = #{active := true, generation := Generation}, State) ->
    mutate({fence, Generation}, State#instance{snapshot = Snapshot});
observe(
    Snapshot = #{
        active := false,
        generation := Generation,
        source_incarnation := OldSource,
        destination_incarnation := OldDestination
    },
    State
) ->
    case pair(State) of
        {Source, Destination} when Source > OldSource, Destination > OldDestination ->
            mutate({bind, Generation, Source, Destination}, State#instance{snapshot = Snapshot});
        _ ->
            {noreply, schedule(State#instance{snapshot = Snapshot, evidence = starting})}
    end.

%% A source and destination must both be ready under their configured domain names.
-spec pair(#instance{}) -> none | {hls_domain:incarnation(), hls_domain:incarnation()}.
pair(#instance{
    source = {_, SourceDomain}, destination = {_, DestinationDomain}, observations = Observations
}) ->
    case Observations of
        #{
            source := {ok, #{phase := ready, handle := {SourceDomain, Source}}},
            destination := {ok, #{phase := ready, handle := {DestinationDomain, Destination}}}
        } when
            Source > 0, Destination > 0
        ->
            {Source, Destination};
        _ ->
            none
    end.

%% Retain intent before submission so a missing reply cannot trigger automatic repetition.
-spec mutate(hls_domain_channel_wire:command(), #instance{}) -> {noreply, #instance{}}.
mutate(Command, State) ->
    Request = {request, State#instance.authority, State#instance.channel, Command},
    {noreply, issue(mutate, Request, State#instance.backend, State#instance{pending = Command})}.

%% Reattachment admits only the known binding or the exact accepted result of its pending bind.
-spec compatible(hls_domain_channel_wire:snapshot(), #instance{}) -> boolean().
compatible(Snapshot, #instance{pending = {bind, Expected, Source, Destination}, snapshot = Before}) ->
    identity(Snapshot) =:= {Expected + 1, Source, Destination} orelse
        (Before =/= none andalso identity(Snapshot) =:= identity(Before));
compatible(Snapshot, #instance{binding = Binding}) when Binding =/= none ->
    identity(Snapshot) =:= Binding;
compatible(Snapshot, #instance{snapshot = Before}) when Before =/= none ->
    identity(Snapshot) =:= identity(Before);
compatible(Snapshot, _) ->
    identity(Snapshot) =:= {0, 0, 0}.

%% Packet counters may advance while transport is absent; binding identity cannot.
-spec identity(hls_domain_channel_wire:snapshot()) ->
    {hls_nums:u64(), hls_nums:u64(), hls_nums:u64()}.
identity(#{
    generation := Generation, source_incarnation := Source, destination_incarnation := Destination
}) ->
    {Generation, Source, Destination}.

%% Cancel only local read work and reply aliases; no cancellation is sent to remote actors.
-spec cancel_work(#instance{}) -> #instance{}.
cancel_work(State) ->
    maps:foreach(
        fun(_Ref, #{pid := Pid, monitor := Monitor, timer := Timer}) ->
            erlang:cancel_timer(Timer),
            demonitor(Monitor, [flush]),
            exit(Pid, kill)
        end,
        State#instance.probes
    ),
    case State#instance.exchange of
        none ->
            ok;
        #{id := Id, timer := Timer} ->
            erlang:cancel_timer(Timer),
            _ = gen_server:receive_response(Id, 0),
            ok
    end,
    State#instance{probes = #{}, exchange = none}.
