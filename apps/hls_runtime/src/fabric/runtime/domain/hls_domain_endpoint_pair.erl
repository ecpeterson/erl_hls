-module(hls_domain_endpoint_pair).
-moduledoc """
Ordinary OTP child coordinating one independently owned TX/RX endpoint pair.

Place this child after both domain-instance children under one_for_all; deployment
owners and management adapters outlive that subtree. This process owns both local
capabilities and only issues bounded control requests. Application traffic never
passes through it. A fresh child fences existing bindings, requires both domain
incarnations to advance beyond both retained endpoint histories, then binds and
confirms RX before enabling TX under one complete binding.

Lost replies require ordered inspection before at most one management retry.
An unavailable ordered read withdraws readiness and fences the reachable peer;
the adapter cannot distinguish a missing reply from a disconnected wire. This instance
never adopts a replacement adapter or resolves its configured name again; recovery
requires explicit deployment reconciliation and a supervised fresh instance with
fresh domains. There is no transparent reconnect or application replay promise.
""".
-behaviour(gen_server).
-include("hls_domain_channel_endpoints.hrl").

%% Supervised startup and passive readiness evidence.
-export([start_link/6, status/1]).
-export_type([endpoint/0, domain/0, options/0, evidence/0]).
%% Ordinary OTP lifecycle.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-doc "One adapter PID or startup-only registered name and its fixed endpoint ID.".
-type endpoint() :: {pid() | atom(), hls_nums:u32()}.
-doc "One existing deployment owner and the domain whose ready incarnation it reports.".
-type domain() :: {pid(), hls_domain:domain()}.
-doc "Finite polling and request deadlines; elapsed time never establishes remote retirement.".
-type options() :: #{poll_ms => pos_integer(), request_timeout_ms => pos_integer()}.
-doc "Last paired evidence, startup, or uncertainty. Ready records are observations, not continuing peer-liveness guarantees.".
-type evidence() ::
    starting
    | {error, noconnection}
    | #{
        phase := ready,
        binding := #endpoint_binding{},
        tx := hls_domain_endpoint_wire:snapshot(),
        rx := hls_domain_endpoint_wire:snapshot()
    }.

%% One static slot exists for each independently managed direction.
-type side() :: tx | rx.
%% Resolved process identities never follow registered-name replacement.
-type owned() :: #{backend := pid(), id := hls_nums:u32(), authority := none | reference()}.
%% The bounded continuation describes only management work, never application work.
-type action() ::
    {attach, side()}
    | {inspect, side()}
    | {mutate, side(), hls_domain_endpoint_wire:command()}
    | {reconcile, side()}
    | {retry, side()}
    | {halt, side()}
    | {domains, choose | verify}
    | admit
    | choose
    | confirm_rx
    | publish.
%% A lost command retains its exact pre-state and bounded continuation until reconciled.
-type intent() :: #{
    command := hls_domain_endpoint_wire:command(),
    before := hls_domain_endpoint_wire:snapshot(),
    continuation := [action()],
    retries := 0 | 1
}.
%% Probe workers possess no endpoint mutation capability.
-type probe() :: #{pid := pid(), monitor := reference(), timer := reference(), side := side()}.
%% At most one management request and two read-only owner probes are outstanding.
-record(pair, {
    endpoints :: #{tx := owned(), rx := owned()},
    domains :: #{tx := domain(), rx := domain()},
    namespace :: hls_nums:u64(),
    backend_monitors = #{} :: #{reference() => pid()},
    owner_monitors = [] :: [reference()],
    snapshots = #{} :: #{side() => hls_domain_endpoint_wire:snapshot()},
    binding = none :: none | #endpoint_binding{},
    pending = #{} :: #{side() => intent()},
    todo = [] :: [action()],
    exchange = none ::
        none | #{id := gen_server:request_id(), action := action(), timer := reference()},
    probes = #{} :: #{reference() => probe()},
    observations = #{} :: #{side() => {ok, hls_domain:snapshot()} | {error, term()}},
    probe_purpose = choose :: choose | verify,
    dead = [] :: [pid()],
    unavailable = false :: boolean(),
    ready = false :: boolean(),
    evidence = starting :: evidence(),
    poll_timer = none :: none | reference(),
    poll_ms = 100 :: pos_integer(),
    timeout_ms = 1000 :: pos_integer()
}).

-doc "Starts promptly as a normal OTP child; Namespace is an explicit retained link identity, independent of management sessions. RX is confirmed before TX admission. A failed transport leaves this instance unavailable until explicitly replaced through supervision; it never adopts a new adapter PID or resumes a transport after an unavailable ordered read automatically.".
-spec start_link(endpoint(), endpoint(), domain(), domain(), hls_nums:u64(), options()) ->
    gen_server:start_ret().
start_link(Tx, Rx, Source, Destination, Namespace, Options) ->
    gen_server:start_link(?MODULE, {Tx, Rx, Source, Destination, Namespace, Options}, []).

-doc "Returns the last readiness observation without issuing or waiting for a management request.".
-spec status(pid()) -> evidence().
status(Pair) -> gen_server:call(Pair, status).

-doc "Resolves adapters once, monitors authorities and schedules bounded initial admission.".
-spec init({endpoint(), endpoint(), domain(), domain(), hls_nums:u64(), options()}) ->
    {ok, #pair{}}.
init({Tx, Rx, Source = {SourceOwner, _}, Destination = {DestinationOwner, _}, Namespace, Options}) ->
    process_flag(trap_exit, true),
    true = is_integer(Namespace) andalso Namespace > 0 andalso Namespace < (1 bsl 64),
    [] = maps:keys(Options) -- [poll_ms, request_timeout_ms],
    Poll = maps:get(poll_ms, Options, 100),
    Timeout = maps:get(request_timeout_ms, Options, 1000),
    true = is_integer(Poll) andalso Poll > 0,
    true = is_integer(Timeout) andalso Timeout > 0,
    Endpoints = #{tx => endpoint(Tx), rx => endpoint(Rx)},
    Backends = lists:usort([Pid || #{backend := Pid} <- maps:values(Endpoints)]),
    State = #pair{
        endpoints = Endpoints,
        domains = #{tx => Source, rx => Destination},
        namespace = Namespace,
        poll_ms = Poll,
        timeout_ms = Timeout,
        backend_monitors = maps:from_list([{monitor(process, Pid), Pid} || Pid <- Backends]),
        owner_monitors = [
            monitor(process, Pid)
         || Pid <- lists:usort([SourceOwner, DestinationOwner])
        ],
        todo = [{attach, tx}, {attach, rx}, {inspect, tx}, {inspect, rx}, admit]
    },
    {ok, schedule(State)}.

%% Public names are resolved only here, never after a monitored transport disappears.
-spec endpoint(endpoint()) -> owned().
endpoint({Name, Id}) when is_atom(Name) ->
    case whereis(Name) of
        undefined -> error({endpoint_pair_unavailable, Name});
        Pid -> endpoint({Pid, Id})
    end;
endpoint({Pid, Id}) when is_pid(Pid), node(Pid) =:= node() ->
    true = is_integer(Id) andalso Id >= 0 andalso Id < (1 bsl 32),
    #{backend => Pid, id => Id, authority => none}.

-doc "Provides passive evidence; no public call sends application work or replaces a transport.".
-spec handle_call(term(), gen_server:from(), #pair{}) -> {reply, term(), #pair{}}.
%% Status is deliberately nonblocking and does not refresh either endpoint.
handle_call(status, _From, State) -> {reply, State#pair.evidence, State};
%% Transport replacement and lifecycle mutation are deployment responsibilities.
handle_call(_, _From, State) -> {reply, {error, unsupported}, State}.

-doc "Ignores casts; paired management has no application forwarding lane.".
-spec handle_cast(term(), #pair{}) -> {noreply, #pair{}}.
handle_cast(_, State) -> {noreply, State}.

-doc "Advances one bounded management continuation or completes read-only domain observations.".
-spec handle_info(term(), #pair{}) -> {noreply, #pair{}} | {stop, term(), #pair{}}.
%% A single poll timer resumes delayed reads or refreshes ready evidence.
handle_info(poll, State) ->
    {noreply, drive(poll(State#pair{poll_timer = none}))};
%% Probe answers are correlated independently of their worker's normal DOWN signal.
handle_info({domain_observation, Ref, Result}, State) ->
    {noreply, probe_result(Ref, Result, State)};
%% A timed-out read says nothing about domain retirement.
handle_info({probe_timeout, Ref}, State) ->
    {noreply, probe_result(Ref, {error, noconnection}, State)};
%% Abandoned management aliases leave mutation intent intact for ordered inspection.
handle_info({request_timeout, Id}, State = #pair{exchange = #{id := Id}}) ->
    _ = gen_server:receive_response(Id, 0),
    {noreply, result({error, noconnection}, State)};
%% Adapter loss is persistent uncertainty; owner loss remains a supervision failure.
handle_info({'DOWN', Ref, process, Pid, Reason}, State) ->
    case maps:is_key(Ref, State#pair.backend_monitors) of
        true ->
            {noreply, transport_down(Pid, State)};
        false ->
            case lists:member(Ref, State#pair.owner_monitors) of
                true -> {stop, {domain_owner_down, Reason}, State};
                false -> {noreply, State}
            end
    end;
%% Ordinary supervisor shutdown lets surviving adapters observe this capability owner's death.
handle_info({'EXIT', _, shutdown}, State) ->
    {stop, shutdown, State};
%% Preserve structured OTP shutdown reasons without turning them into management commands.
handle_info({'EXIT', _, {shutdown, _} = Reason}, State) ->
    {stop, Reason, State};
%% Only the current management alias can complete its continuation.
handle_info(Message, State = #pair{exchange = #{id := Id}}) ->
    case gen_server:check_response(Message, Id) of
        {reply, Reply} -> {noreply, result(Reply, State)};
        {error, _} -> {noreply, result({error, noconnection}, State)};
        _ -> {noreply, State}
    end;
%% Late aliases and cancelled probe monitors cannot create new management work.
handle_info(_, State) ->
    {noreply, State}.

-doc "Cancels local reads and aliases. Each surviving adapter independently inspects and fences this dead owner's endpoint, including an uncertain transmitted bind; no remote success is inferred here.".
-spec terminate(term(), #pair{}) -> ok.
terminate(_, State) ->
    _ = cancel_work(State),
    ok.

%% One delayed wakeup bounds unavailable-owner and management-read polling.
-spec schedule(#pair{}) -> #pair{}.
schedule(State = #pair{poll_timer = none}) ->
    State#pair{poll_timer = erlang:send_after(State#pair.poll_ms, self(), poll)};
schedule(State) ->
    State.

%% Only ready pairs repeat the full readiness check; unavailable pairs only retire reachable peers.
-spec poll(#pair{}) -> #pair{}.
poll(State = #pair{todo = [], unavailable = true}) ->
    State#pair{todo = halt_plan(State)};
poll(State = #pair{todo = [], ready = true}) ->
    State#pair{todo = [{domains, verify}, {inspect, tx}, {inspect, rx}, publish]};
poll(State) ->
    State.

%% Pure continuations are finite; every I/O action returns immediately to the gen_server.
-spec drive(#pair{}) -> #pair{}.
drive(State = #pair{exchange = Exchange, probes = Probes}) when
    Exchange =/= none; map_size(Probes) > 0
->
    State;
drive(State = #pair{todo = []}) ->
    schedule(State);
drive(State = #pair{todo = [Action | Rest]}) ->
    action(Action, State#pair{todo = Rest}).

%% Attachment uses this coordinator's real caller identity at both shared adapters.
-spec action(action(), #pair{}) -> #pair{}.
action({attach, Side} = Action, State) ->
    #{id := Id} = owned(Side, State),
    issue(Side, Action, {attach, Id, self()}, State);
%% Every inspect is ordered through the same lane as its preceding mutation.
action({inspect, Side} = Action, State) ->
    #{id := Id} = owned(Side, State),
    issue(Side, Action, {status, Id}, State);
%% Mutation intent is retained before the request can enter its adapter's queue.
action({mutate, Side, Command}, State) ->
    Intent = #{
        command => Command,
        before => maps:get(Side, State#pair.snapshots),
        continuation => State#pair.todo,
        retries => 0
    },
    send_mutation(Side, State#pair{pending = (State#pair.pending)#{Side => Intent}});
%% Reconciliation is always a new status request, never retransmission of an unknown pulse.
action({reconcile, Side} = Action, State) ->
    #{id := Id} = owned(Side, State),
    issue(Side, Action, {status, Id}, State);
%% A checked retry reuses the exact original command and its single retry allowance.
action({retry, Side}, State) ->
    send_mutation(Side, State);
%% Read-only workers never acquire endpoint capabilities.
action({domains, Purpose}, State) ->
    start_probes(Purpose, State);
%% A new coordinator retires old live bindings before choosing fresh identities.
action(admit, State) ->
    admit(State);
%% Both local lifetimes must exceed both retained endpoint histories.
action(choose, State) ->
    choose(State);
%% RX confirmation is exact sampled evidence, not a continuous remote-ready wire.
action(confirm_rx, State = #pair{binding = Binding}) ->
    true = target({bind, Binding}, maps:get(rx, State#pair.snapshots)),
    drive(State);
%% Paired readiness requires matching observations from both independently clocked endpoints.
action(publish, State = #pair{binding = Binding}) ->
    true = target({bind, Binding}, maps:get(tx, State#pair.snapshots)),
    true = target({bind, Binding}, maps:get(rx, State#pair.snapshots)),
    drive(State#pair{
        ready = true,
        evidence = #{
            phase => ready,
            binding => Binding,
            tx => maps:get(tx, State#pair.snapshots),
            rx => maps:get(rx, State#pair.snapshots)
        }
    });
%% Transport loss authorizes fencing only the still-owned reachable endpoint.
action({halt, Side}, State) ->
    Snapshot = maps:get(Side, State#pair.snapshots),
    case Snapshot of
        #{active := true, fault := false, binding := Binding} ->
            action({mutate, Side, {fence, Binding}}, State);
        #{active := false, fault := false} ->
            drive(State);
        _ ->
            suspend({inspect, Side}, State#pair{todo = [{halt, Side} | State#pair.todo]})
    end.

%% Resolve a retained owned endpoint without recomputing registration or capability state.
-spec owned(side(), #pair{}) -> owned().
owned(Side, #pair{endpoints = Endpoints}) -> maps:get(Side, Endpoints).

%% A dead adapter never turns into a request against a replacement registered process.
-spec issue(side(), action(), hls_domain_channel_fabric:request(), #pair{}) -> #pair{}.
issue(Side, Action, Request, State) ->
    #{backend := Backend} = owned(Side, State),
    case is_process_alive(Backend) of
        false ->
            transport_down(Backend, State);
        true ->
            Id = hls_domain_channel_fabric:send_request(Backend, Request),
            Timer = erlang:send_after(State#pair.timeout_ms, self(), {request_timeout, Id}),
            State#pair{exchange = #{id => Id, action => Action, timer => Timer}}
    end.

%% At most one mutation request is outstanding; each endpoint retains at most one uncertain intent.
-spec send_mutation(side(), #pair{}) -> #pair{}.
send_mutation(Side, State) ->
    #{id := Id, authority := Authority} = owned(Side, State),
    #{command := Command} = maps:get(Side, State#pair.pending),
    issue(Side, {mutate, Side, Command}, {request, Authority, Id, Command}, State).

%% Deadline removal happens before dispatch so each alias has one local outcome.
-spec result(term(), #pair{}) -> #pair{}.
result(Reply, State = #pair{exchange = #{action := Action, timer := Timer}}) ->
    erlang:cancel_timer(Timer),
    response(Action, Reply, State#pair{exchange = none}).

%% Successful attachment records only this owner's capability for its fixed endpoint.
-spec response(action(), term(), #pair{}) -> #pair{}.
response({attach, Side}, {ok, Authority}, State) when is_reference(Authority) ->
    Endpoint = (owned(Side, State))#{authority := Authority},
    drive(State#pair{endpoints = (State#pair.endpoints)#{Side := Endpoint}});
%% A prior owner's retirement or queue saturation cannot be bypassed by this child.
response({attach, _} = Action, {error, Reason}, State) when
    Reason =:= retiring; Reason =:= owned; Reason =:= busy
->
    suspend(Action, State);
%% Current metadata is checked against the configured endpoint direction and retained namespace.
response({inspect, Side}, {ok, Snapshot}, State) ->
    drive(observe(Side, Snapshot, State));
%% Direct mutation replies must be canonical acceptance, not guessed success after rejection.
response({mutate, Side, Command}, {ok, Snapshot}, State) ->
    #{status := accepted} = Snapshot,
    true = target(Command, Snapshot),
    completed(Side, observe(Side, Snapshot, State));
%% Ordered status resolves a retained intent without requiring its original response to arrive.
response({reconcile, Side}, {ok, Snapshot}, State) ->
    reconcile(Side, observe(Side, Snapshot, State));
%% Lost mutation replies preserve exact command identity; only inspection follows.
response({mutate, Side, Command}, {error, {outcome_unknown, Command}}, State) ->
    unknown(Side, State);
response({mutate, Side, _}, {error, noconnection}, State) ->
    unknown(Side, State);
%% A known pre-queue rejection can be inspected under the same bounded retry rule.
response({mutate, Side, _}, {error, busy}, State) ->
    unknown(Side, State);
%% The adapter cannot distinguish read timeout from wire loss; quarantine that transport and fence its peer.
response({_, Side}, {error, noconnection}, State) ->
    #{backend := Backend} = owned(Side, State),
    transport_down(Backend, State);
%% Any other canonical rejection is a supervision failure, not permission to adopt another binding.
response(Action, Failure, _State) ->
    error({endpoint_pair_management_failed, Action, Failure}).

%% Keep startup or ready evidence unavailable while a control observation is missing.
-spec suspend(action(), #pair{}) -> #pair{}.
suspend(Action, State) ->
    schedule(State#pair{todo = [Action | State#pair.todo], evidence = {error, noconnection}}).

%% Pending mutation continuations remain in their intent while the ordered read is outstanding.
-spec unknown(side(), #pair{}) -> #pair{}.
unknown(Side, State) ->
    drive(State#pair{todo = [{reconcile, Side}], evidence = {error, noconnection}}).

%% Namespace replacement is external deployment work, even when the new endpoint is inactive.
-spec observe(side(), hls_domain_endpoint_wire:snapshot(), #pair{}) -> #pair{}.
observe(Side, Snapshot = #{kind := Side, binding := Binding}, State) ->
    case Binding of
        #endpoint_binding{} when Binding =:= #endpoint_binding{} -> ok;
        #endpoint_binding{namespace = Namespace} -> true = Namespace =:= State#pair.namespace
    end,
    State#pair{snapshots = (State#pair.snapshots)#{Side => Snapshot}}.

%% Acceptance and reconciliation use exactly the same complete binding postcondition.
-spec target(hls_domain_endpoint_wire:command(), hls_domain_endpoint_wire:snapshot()) -> boolean().
target({bind, Binding}, #{binding := Binding, active := true, fault := false}) -> true;
target({fence, Binding}, #{binding := Binding, active := false, fault := false}) -> true;
target(_, _) -> false.

%% Finish intent once; a transport failure never resumes its saved admission continuation.
-spec completed(side(), #pair{}) -> #pair{}.
completed(Side, State) ->
    #{continuation := After} = maps:get(Side, State#pair.pending),
    Next = State#pair{pending = maps:remove(Side, State#pair.pending)},
    case State#pair.unavailable of
        true -> drive(Next#pair{todo = halt_plan(Next)});
        false -> drive(Next#pair{todo = After})
    end.

%% One retry is permitted only after exact unchanged pre-state and fresh domain evidence.
-spec reconcile(side(), #pair{}) -> #pair{}.
reconcile(Side, State) ->
    Intent =
        #{command := Command, before := Before, retries := Retries} = maps:get(
            Side, State#pair.pending
        ),
    Snapshot = maps:get(Side, State#pair.snapshots),
    case target(Command, Snapshot) of
        true ->
            completed(Side, State);
        false ->
            case {same_ownership(Before, Snapshot), Command, State#pair.unavailable, Retries} of
                {true, {bind, _}, true, _} ->
                    completed(Side, State);
                {true, _, _, 0} ->
                    Next = State#pair{
                        pending = (State#pair.pending)#{Side := Intent#{retries := 1}}
                    },
                    Retry =
                        case Command of
                            {fence, _} ->
                                [{retry, Side}];
                            {bind, _} when Side =:= rx -> [{domains, verify}, {retry, Side}];
                            {bind, _} ->
                                [{domains, verify}, {inspect, rx}, confirm_rx, {retry, Side}]
                        end,
                    drive(Next#pair{todo = Retry});
                _ ->
                    error({endpoint_pair_unreconciled, Side, Command, Snapshot})
            end
    end.

%% Status text may change between ticks; binding and ownership must remain exact.
-spec same_ownership(hls_domain_endpoint_wire:snapshot(), hls_domain_endpoint_wire:snapshot()) ->
    boolean().
same_ownership(Before, Snapshot) ->
    maps:with([binding, active, fault, packet_sequence], Before) =:=
        maps:with([binding, active, fault, packet_sequence], Snapshot).

%% Stop source admission before retiring an old receiver, then inspect both again.
-spec admit(#pair{}) -> #pair{}.
admit(State) ->
    Tx = maps:get(tx, State#pair.snapshots),
    Rx = maps:get(rx, State#pair.snapshots),
    false = maps:get(fault, Tx),
    false = maps:get(fault, Rx),
    Refresh = [{inspect, tx}, {inspect, rx}, admit],
    case {maps:get(active, Tx), maps:get(active, Rx)} of
        {true, _} ->
            drive(State#pair{todo = [{mutate, tx, {fence, maps:get(binding, Tx)}} | Refresh]});
        {false, true} ->
            drive(State#pair{todo = [{mutate, rx, {fence, maps:get(binding, Rx)}} | Refresh]});
        {false, false} ->
            drive(State#pair{todo = [{domains, choose}, choose]})
    end.

%% Burned generations need only be exceeded; both retained incarnation histories still constrain admission.
-spec choose(#pair{}) -> #pair{}.
choose(State) ->
    {Source, Destination} = ready_domains(State),
    Bindings = [maps:get(binding, S) || S <- maps:values(State#pair.snapshots)],
    OldSource = lists:max([B#endpoint_binding.source_incarnation || B <- Bindings]),
    OldDestination = lists:max([B#endpoint_binding.destination_incarnation || B <- Bindings]),
    Generation = lists:max([B#endpoint_binding.generation || B <- Bindings]),
    case Source > OldSource andalso Destination > OldDestination of
        false ->
            schedule(State#pair{todo = [{inspect, tx}, {inspect, rx}, admit], evidence = starting});
        true ->
            true = Generation < ((1 bsl 64) - 1),
            Binding = #endpoint_binding{
                namespace = State#pair.namespace,
                generation = Generation + 1,
                source_incarnation = Source,
                destination_incarnation = Destination
            },
            drive(State#pair{
                binding = Binding,
                todo = [
                    {mutate, rx, {bind, Binding}},
                    {inspect, rx},
                    confirm_rx,
                    {domains, verify},
                    {mutate, tx, {bind, Binding}},
                    {inspect, tx},
                    {inspect, rx},
                    publish
                ]
            })
    end.

%% Both probes are bounded status-only calls; their results cannot directly mutate a domain.
-spec start_probes(choose | verify, #pair{}) -> #pair{}.
start_probes(Purpose, State) ->
    Parent = self(),
    Probes = maps:from_list([
        begin
            Ref = make_ref(),
            {Pid, Monitor} = spawn_monitor(fun() ->
                Result =
                    try
                        hls_domain:status(Owner, Domain)
                    catch
                        exit:_ -> {error, noconnection}
                    end,
                Parent ! {domain_observation, Ref, Result}
            end),
            Timer = erlang:send_after(State#pair.timeout_ms, self(), {probe_timeout, Ref}),
            {Ref, #{pid => Pid, monitor => Monitor, timer => Timer, side => Side}}
        end
     || {Side, {Owner, Domain}} <- maps:to_list(State#pair.domains)
    ]),
    State#pair{probes = Probes, observations = #{}, probe_purpose = Purpose}.

%% Missing reads withdraw readiness; a confirmed replacement incarnation cannot inherit the old pair.
-spec probe_result(reference(), term(), #pair{}) -> #pair{}.
probe_result(Ref, Result, State) ->
    case maps:take(Ref, State#pair.probes) of
        error ->
            State;
        {#{pid := Pid, monitor := Monitor, timer := Timer, side := Side}, Rest} ->
            erlang:cancel_timer(Timer),
            demonitor(Monitor, [flush]),
            exit(Pid, kill),
            Next = State#pair{
                probes = Rest, observations = (State#pair.observations)#{Side => Result}
            },
            case map_size(Rest) of
                0 -> domains_complete(Next);
                _ -> Next
            end
    end.

%% Fresh bind selection waits for ready owners; existing exact bindings reject observed lifecycle changes.
-spec domains_complete(#pair{}) -> #pair{}.
domains_complete(State = #pair{probe_purpose = Purpose}) ->
    case ready_domains(State) of
        none ->
            suspend({domains, Purpose}, State);
        _Pair when Purpose =:= choose -> drive(State);
        Pair ->
            #endpoint_binding{source_incarnation = Source, destination_incarnation = Destination} =
                State#pair.binding,
            true = Pair =:= {Source, Destination},
            drive(State)
    end.

%% Domain names and incarnations are supplied by their existing deployment owners.
-spec ready_domains(#pair{}) -> none | {hls_domain:incarnation(), hls_domain:incarnation()}.
ready_domains(#pair{
    domains = #{tx := {_, SourceDomain}, rx := {_, DestinationDomain}}, observations = Observations
}) ->
    case Observations of
        #{
            tx := {ok, #{phase := ready, handle := {SourceDomain, Source}}},
            rx := {ok, #{phase := ready, handle := {DestinationDomain, Destination}}}
        } when Source > 0, Destination > 0 ->
            {Source, Destination};
        _ ->
            none
    end.

%% A dead adapter or unavailable ordered read is never re-adopted; only reachable owned peers receive retirement work.
-spec transport_down(pid(), #pair{}) -> #pair{}.
transport_down(Backend, State) ->
    case lists:member(Backend, State#pair.dead) of
        true ->
            State;
        false ->
            Next = (cancel_work(State))#pair{
                dead = [Backend | State#pair.dead],
                unavailable = true,
                ready = false,
                evidence = {error, noconnection},
                todo = []
            },
            drive(Next#pair{todo = halt_plan(Next)})
    end.

%% A surviving uncertain mutation is inspected before any fence is constructed from its result.
-spec halt_plan(#pair{}) -> [action()].
halt_plan(State) ->
    lists:append([
        case maps:is_key(Side, State#pair.pending) of
            true -> [{reconcile, Side}];
            false -> [{inspect, Side}, {halt, Side}]
        end
     || Side <- [tx, rx],
        #{backend := Backend, authority := Authority} <- [owned(Side, State)],
        Authority =/= none,
        not lists:member(Backend, State#pair.dead),
        is_process_alive(Backend)
    ]).

%% Cancellation abandons only local reads and aliases; transmitted mutation intent remains retained.
-spec cancel_work(#pair{}) -> #pair{}.
cancel_work(State) ->
    maps:foreach(
        fun(_, #{pid := Pid, monitor := Monitor, timer := Timer}) ->
            erlang:cancel_timer(Timer),
            demonitor(Monitor, [flush]),
            exit(Pid, kill)
        end,
        State#pair.probes
    ),
    case State#pair.exchange of
        none ->
            ok;
        #{id := Id, timer := Timer} ->
            erlang:cancel_timer(Timer),
            _ = gen_server:receive_response(Id, 0)
    end,
    case State#pair.poll_timer of
        none -> ok;
        Poll -> erlang:cancel_timer(Poll)
    end,
    State#pair{probes = #{}, exchange = none, poll_timer = none}.
