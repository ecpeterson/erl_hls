-module(hls_supervisor_fabric).
-moduledoc """
Production parent-management backend for a compiled FPGA supervisor. A normal
hls_domain owner and host OTP representative control the parent through one existing
broker. Each child uses its own hls_domain_fabric application/management lanes;
no child payload passes through this process. The resolved parent endpoint also
accepts explicit admission, inspection and termination of compiled temporary slots.

A deployment supplies an already persisted finite incarnation interval. This adapter
submits that exact grant once when the parent is observed initializing. It allocates
nothing, never rewinds a grant, and does not retry an uncertain packet. Reattachment
can use grant => none. Broker loss retires the parent observer with noconnection;
it does not reset the autonomous supervisor. Transport session establishment and
old-path exclusion remain deployment obligations.
""".
-behaviour(gen_server).
-behaviour(hls_domain_backend).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Deployment and ordinary domain-backend interface.
-export([start_link/3, attach/2, status/1, request/3, endpoint/4, send_request/2, stop/1, info/1]).
%% Operations addressed to one resolved parent-incarnation endpoint.
-export([start_child/3, terminate_child/3, child_status/2]).
%% OTP callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-export_type([transport/0, options/0, child/0, child_result/0]).

-doc "One existing independent management broker, after a deployment-attested nonzero transport session.".
-type transport() :: #{management := pid(), session := hls_nums:u64()}.
-doc "A pre-reserved grant and finite management deadlines. Missing grants leave new parent initialization unavailable; they never imply allocation.".
-type options() :: #{
    grant => none | {hls_domain:incarnation(), hls_domain:incarnation()},
    poll_ms => pos_integer(),
    management_timeout_ms => pos_integer()
}.
-doc "An observation or admission result for one compiled slot; admission does not imply initialization or endpoint publication.".
-type child() :: #{
    id := atom(), incarnation := hls_nums:u64(), phase := hls_supervisor_lifecycle:child_phase()
}.
-doc "Definite slot outcomes retain the observed occupant; connection uncertainty supplies no admission or retirement evidence.".
-type child_result() :: {ok, child()} | {error, {atom(), child()}} | {error, atom()}.
%% Eight queued requests and one transmitted exchange bound retained management callers.
-type exchange() :: #{
    input := hls_supervisor_wire:command(),
    from := none | gen_server:from(),
    sequence => hls_nums:u32(),
    timer => reference()
}.
%% The parent observer owns no application data or queued work.
-record(backend, {
    broker :: pid(),
    broker_monitor :: reference(),
    route :: hls_fabric:route(),
    session :: hls_nums:u64(),
    interface :: hls_supervisor_wire:interface(),
    grant = none :: none | {hls_domain:incarnation(), hls_domain:incarnation()},
    grant_attempted = 0 :: hls_nums:u64(),
    grant_pending = none :: none | hls_supervisor_wire:command(),
    grant_result = none :: none | accepted | rejected,
    owner = undefined :: undefined | pid(),
    owner_monitor = undefined :: undefined | reference(),
    authority = undefined :: undefined | reference(),
    lifecycle = #domain_state{} :: hls_domain_lifecycle:state(),
    detail = none :: term(),
    endpoint = none :: none | pid(),
    endpoint_monitor = none :: none | reference(),
    incarnation = 0 :: hls_nums:u64(),
    retiring = false :: boolean(),
    queue = queue:new() :: queue:queue(exchange()),
    exchange = none :: none | exchange(),
    sequence = 1 :: pos_integer(),
    writing = false :: boolean(),
    sends = gen_server:reqids_new() :: gen_server:request_id_collection(),
    ignored = 0 :: non_neg_integer(),
    poll_ms = 10 :: pos_integer(),
    timeout_ms = 1000 :: pos_integer()
}).

-doc "Claims one retained management route without resetting or starting hardware. The grant must already be durably reserved and exclusively delegated to this supervisor.".
-spec start_link(transport(), hls_supervisor_wire:interface() | map() | file:filename(), options()) ->
    gen_server:start_ret().
start_link(Transport, Interface, Options) ->
    gen_server:start_link(?MODULE, {Transport, Interface, Options}, []).
-doc "Claims local owner authority without changing the device lifecycle; exact repeats preserve the capability.".
-spec attach(pid(), pid()) -> {ok, reference()} | {error, term()}.
attach(Pid, Owner) -> gen_server:call(Pid, {attach, Owner}).
-doc "Obtains fresh framed lifecycle evidence. No wall-clock timeout is interpreted as successful shutdown.".
-spec status(pid()) -> {ok, hls_domain_backend:snapshot()} | {error, term()}.
status(Pid) -> gen_server:call(Pid, status).
-doc "Submits one owner-authorized lifecycle command; an uncertain result is never automatically retransmitted.".
-spec request(pid(), reference(), hls_domain_lifecycle:input()) ->
    hls_domain_lifecycle:output() | {error, term()}.
request(Pid, Authority, Input) -> gen_server:call(Pid, {request, Authority, Input}).
-doc "Resolves the exact ready parent lifetime observer named supervisor. This endpoint accepts no application operations.".
-spec endpoint(pid(), reference(), hls_nums:u64(), term()) -> {ok, pid()} | {error, term()}.
endpoint(Pid, Authority, Epoch, Actor) -> gen_server:call(Pid, {endpoint, Authority, Epoch, Actor}).
-doc "Starts the common backend exchange without changing the owner caller identity.".
-spec send_request(pid(), hls_domain_backend:request()) -> gen_server:request_id().
send_request(Pid, Request) -> gen_server:send_request(Pid, Request).
-doc "Stops this local adapter with connection uncertainty; deployment-owned brokers and the supervisor continue independently.".
-spec stop(pid()) -> ok.
stop(Pid) -> gen_server:stop(Pid).
-doc "Returns bounded management diagnostics, including the outcome of the one attempted grant for the observed parent incarnation.".
-spec info(pid()) -> map().
info(Pid) -> gen_server:call(Pid, info).

-doc "Admits one temporary occupant into a vacant compiled slot. Pass the last observed occupant (zero for an unused slot); a concurrent or stale request cannot acquire someone else's child. The result names the reserved incarnation, not readiness. Never automatically retry an uncertain result.".
-spec start_child(pid(), atom(), hls_nums:u64()) -> child_result().
start_child(Endpoint, Slot, Expected) ->
    gen_server:call(Endpoint, {child, start, Slot, Expected}, infinity).
-doc "Requests retirement of exactly one temporary occupant, without allocating a replacement. Accepted intent is not completion; inspect the slot until vacant. The source program's normal completion can be followed by this explicit OTP-style termination.".
-spec terminate_child(pid(), atom(), hls_domain:incarnation()) -> child_result().
terminate_child(Endpoint, Slot, Epoch) ->
    gen_server:call(Endpoint, {child, stop, Slot, Epoch}, infinity).
-doc "Inspects one compiled slot through the exact parent endpoint. Vacant means both core and transport retirement were confirmed; it does not promise the slot remains free until a later admission.".
-spec child_status(pid(), atom()) -> child_result().
child_status(Endpoint, Slot) ->
    gen_server:call(Endpoint, {child, inspect, Slot, 0}, infinity).

-doc "Validates the retained interface, session and grant before registering its exclusive broker route.".
-spec init({transport(), hls_supervisor_wire:interface() | map() | file:filename(), options()}) ->
    {ok, #backend{}}.
init({#{management := Broker, session := Session}, Interface0, Options}) ->
    true = is_integer(Session) andalso Session > 0 andalso Session < (1 bsl 64),
    [] = maps:keys(Options) -- [grant, poll_ms, management_timeout_ms],
    Interface = #{management_route := Route} = hls_supervisor_wire:load(Interface0),
    Grant = maps:get(grant, Options, none),
    ok = grant(Grant),
    Poll = positive(poll_ms, Options, 10),
    Timeout = positive(management_timeout_ms, Options, 1000),
    ok = hls_fabric:register_route(Broker, Route, self()),
    erlang:send_after(Poll, self(), poll),
    {ok, #backend{
        broker = Broker,
        broker_monitor = monitor(process, Broker),
        route = Route,
        session = Session,
        interface = Interface,
        grant = Grant,
        poll_ms = Poll,
        timeout_ms = Timeout
    }}.

-doc "Bounds and orders lifecycle requests independently of every child application lane.".
-spec handle_call(term(), gen_server:from(), #backend{}) ->
    {reply, term(), #backend{}} | {noreply, #backend{}}.
%% An attached owner repeats its existing claim rather than acquiring another capability.
handle_call({attach, Owner}, {Owner, _}, State = #backend{owner = Owner, authority = Authority}) ->
    {reply, {ok, Authority}, State};
%% Owner death revokes host authority without changing the remote supervisor's lifetime.
handle_call({attach, Owner}, {Owner, _}, State = #backend{owner = undefined}) when
    node(Owner) =:= node()
->
    Authority = make_ref(),
    {reply, {ok, Authority},
        reconcile(State#backend{
            owner = Owner,
            authority = Authority,
            owner_monitor = monitor(process, Owner)
        })};
%% Status always goes through hardware, even when the previous observation was ready.
handle_call(status, From, State) ->
    enqueue(none, From, State);
%% The backend checks both the capability and actual caller, just like the ordinary domain adapter.
handle_call(
    {request, Authority, Input},
    {Owner, _} = From,
    State = #backend{owner = Owner, authority = Authority}
) when is_reference(Authority) ->
    enqueue(Input, From, State);
%% A live parent observer never changes its incarnation when a later snapshot arrives.
handle_call(
    {endpoint, Authority, Epoch, supervisor},
    {Owner, _},
    State = #backend{
        owner = Owner,
        authority = Authority,
        incarnation = Epoch,
        lifecycle = #domain_state{phase = ready, current = Epoch},
        retiring = false,
        endpoint = Endpoint
    }
) when is_reference(Authority), is_pid(Endpoint) ->
    {reply, {ok, Endpoint}, State};
%% Possession of a resolved parent endpoint permits management, as with an ordinary OTP supervisor PID.
handle_call(
    {child, Epoch, Operation, Id, Expected},
    {Endpoint, _} = From,
    State = #backend{
        endpoint = Endpoint,
        incarnation = Epoch,
        lifecycle = #domain_state{phase = ready, current = Epoch},
        retiring = false,
        owner = Owner,
        interface = #{slots := Slots}
    }
) when
    is_pid(Endpoint),
    is_pid(Owner),
    (Operation =:= start orelse Operation =:= stop orelse Operation =:= inspect),
    is_atom(Id),
    is_integer(Expected),
    Expected >= 0,
    Expected < (1 bsl 64)
->
    case maps:find(Id, Slots) of
        {ok, Slot} -> enqueue({child, Operation, Epoch, Slot, Expected}, From, State);
        error -> {reply, {error, unknown_child}, State}
    end;
%% Introspection retains counters and current evidence rather than work history.
handle_call(info, _From, State) ->
    {reply,
        #{
            state => State#backend.lifecycle,
            session => State#backend.session,
            grant_attempted => State#backend.grant_attempted,
            grant_result => State#backend.grant_result,
            queued => queue:len(State#backend.queue),
            ignored => State#backend.ignored
        },
        State};
%% Unknown requests cannot acquire lifecycle authority or address a child.
handle_call(_, _, State) ->
    {reply, {error, unauthorized}, State}.

-doc "Consumes only complete canonical parent management observations; malformed current-session evidence closes the adapter.".
-spec handle_cast(term(), #backend{}) -> {noreply, #backend{}} | {stop, term(), #backend{}}.
%% Broker acknowledgement releases this frame independently of any lifecycle result.
handle_cast(
    {'$hls_fabric_frame', Receipt, Route, Header, Payload},
    State = #backend{broker = Broker, route = Route}
) ->
    try
        {Tag, 0, 0} = Header,
        frame(Tag, Payload, State)
    of
        Next ->
            hls_fabric:ack(Broker, Receipt),
            {noreply, pump(Next)}
    catch
        Class:Reason ->
            hls_fabric:ack(Broker, Receipt),
            {stop, {invalid_supervisor_frame, Class, Reason}, State}
    end;
%% This parent management adapter has no application forwarding interface.
handle_cast(_, State) ->
    {noreply, State}.

-doc "Keeps one idle poll and one physical write outstanding; broker loss and deadlines remain connection uncertainty.".
-spec handle_info(term(), #backend{}) -> {noreply, #backend{}} | {stop, term(), #backend{}}.
%% Polling samples state but never allocates identities or requests replacement.
handle_info(poll, State = #backend{poll_ms = Poll, exchange = Exchange, queue = Queue}) ->
    erlang:send_after(Poll, self(), poll),
    Next =
        case Exchange =:= none andalso queue:is_empty(Queue) of
            true -> queue_request(none, none, State);
            false -> State
        end,
    {noreply, Next};
%% Host authority can disappear while local FPGA supervision continues.
handle_info({'DOWN', Ref, process, _Owner, _Reason}, State = #backend{owner_monitor = Ref}) ->
    {noreply, State#backend{owner = undefined, owner_monitor = undefined, authority = undefined}};
%% A lost broker cannot attest that the autonomous subtree stopped.
handle_info({'DOWN', Ref, process, _Broker, Reason}, State = #backend{broker_monitor = Ref}) ->
    {stop, {transport_down, Reason}, State};
%% Actual observer death precedes creating a replacement parent observer.
handle_info(
    {'DOWN', Ref, process, _Endpoint, _Reason},
    State = #backend{endpoint_monitor = Ref, retiring = true}
) ->
    {noreply,
        reconcile(State#backend{
            endpoint = none,
            endpoint_monitor = none,
            incarnation = 0,
            retiring = false
        })};
%% Killing a host observer is not a reason to invent a remote parent failure.
handle_info({'DOWN', Ref, process, _Endpoint, Reason}, State = #backend{endpoint_monitor = Ref}) ->
    {stop, {observer_down, Reason}, State};
%% A timed-out pulse may have changed hardware; reconnect/reconcile rather than replay it.
handle_info({management_timeout, Sequence}, State = #backend{exchange = #{sequence := Sequence}}) ->
    {stop, management_timeout, State};
%% Broker write completion releases physical ownership independently of the hardware response.
handle_info(Message, State = #backend{sends = Sends}) ->
    case gen_server:check_response(Message, Sends, true) of
        {{reply, ok}, _Label, Rest} ->
            {noreply, pump(State#backend{sends = Rest, writing = false})};
        {{reply, Failure}, _Label, Rest} ->
            {stop, {write_failed, Failure}, State#backend{sends = Rest}};
        {{error, Failure}, _Label, Rest} ->
            {stop, {write_failed, Failure}, State#backend{sends = Rest}};
        _ ->
            {noreply, State}
    end.

-doc "Retires only the local lifetime observer and replies to retained callers with uncertainty. No stop or grant is sent during adapter teardown.".
-spec terminate(term(), #backend{}) -> ok.
terminate(_Reason, State) ->
    case State#backend.endpoint of
        none -> ok;
        Pid -> Pid ! {retire, self(), noconnection}
    end,
    case State#backend.exchange of
        none -> ok;
        #{from := From} -> answer(From, {error, noconnection})
    end,
    [answer(maps:get(from, E), {error, noconnection}) || E <- queue:to_list(State#backend.queue)],
    ok.

%% Type checks occur only on the deployment's untyped options boundary.
-spec positive(atom(), options(), pos_integer()) -> pos_integer().
positive(Key, Options, Default) ->
    Value = maps:get(Key, Options, Default),
    true = is_integer(Value) andalso Value > 0,
    Value.
%% The upper sentinel cannot be consumed by the finite supervisor allocator.
-spec grant(none | {hls_domain:incarnation(), hls_domain:incarnation()}) -> ok.
grant(none) ->
    ok;
grant({First, Last}) when
    is_integer(First),
    is_integer(Last),
    First > 0,
    First =< Last,
    Last < ((1 bsl 64) - 1)
->
    ok.

%% Overflow proves that no device command was submitted.
-spec enqueue(hls_supervisor_wire:command(), gen_server:from(), #backend{}) ->
    {reply, term(), #backend{}} | {noreply, #backend{}}.
enqueue(Input, From, State = #backend{queue = Queue}) ->
    case queue:len(Queue) < 8 of
        true -> {noreply, queue_request(Input, From, State)};
        false -> {reply, {error, busy}, State}
    end.
%% Internal polls obey the same finite queue; grants have one separately reserved slot.
-spec queue_request(hls_supervisor_wire:command(), none | gen_server:from(), #backend{}) ->
    #backend{}.
queue_request(Input, From, State = #backend{queue = Queue}) ->
    pump(State#backend{queue = queue:in(#{input => Input, from => From}, Queue)}).
%% A grant needed by initialization precedes the next observation; no application is serialized here.
-spec pump(#backend{}) -> #backend{}.
pump(State = #backend{exchange = none, writing = false, grant_pending = Input}) when
    Input =/= none
->
    transmit(#{input => Input, from => none}, State#backend{grant_pending = none});
pump(State = #backend{exchange = none, writing = false, queue = Queue}) ->
    case queue:out(Queue) of
        {empty, _} -> State;
        {{value, Entry}, Rest} -> transmit(Entry, State#backend{queue = Rest})
    end;
pump(State) ->
    State.

%% A physical write remains owned until broker completion, even if its logical response arrives first.
-spec transmit(exchange(), #backend{}) -> #backend{}.
transmit(
    Entry = #{input := Input},
    State = #backend{
        broker = Broker,
        route = Route,
        sequence = Sequence,
        session = Session,
        interface = Interface,
        timeout_ms = Timeout,
        sends = Sends
    }
) ->
    true = Sequence < (1 bsl 32),
    true = gen_server:reqids_size(Sends) =:= 0,
    {Tag, Payload} = hls_supervisor_wire:command(Session, Sequence, Input, Interface),
    Timer = erlang:send_after(Timeout, self(), {management_timeout, Sequence}),
    Request = hls_fabric:send_request(Broker, Route, {Tag, 0, 0}, Payload, Timeout),
    State#backend{
        exchange = Entry#{sequence => Sequence, timer => Timer},
        sequence = Sequence + 1,
        writing = true,
        sends = gen_server:reqids_add(Request, management, Sends)
    }.

%% Foreign-session frames cannot change readiness or release a current exchange.
-spec frame(byte(), binary(), #backend{}) -> #backend{}.
frame(_Tag, <<Session:64/little, _/binary>>, State = #backend{session = Current}) when
    Session =/= Current
->
    State#backend{ignored = State#backend.ignored + 1};
frame(1, Payload, State = #backend{interface = Interface, session = Session}) ->
    Observation = #{session := Session} = hls_supervisor_wire:observation(Payload, Interface),
    response(Observation, State).

%% Only the current request can update controller state; late old replies are discarded.
-spec response(hls_supervisor_wire:observation(), #backend{}) -> #backend{}.
response(
    #{
        sequence := Sequence,
        output := Output = #domain_output{state = Current},
        grant_accepted := GrantAccepted,
        supervisor_reason := Reason
    } = Observation,
    State = #backend{
        exchange = #{sequence := Sequence, timer := Timer, from := From, input := Input}
    }
) ->
    erlang:cancel_timer(Timer),
    true = Current#domain_state.current >= (State#backend.lifecycle)#domain_state.current,
    Next0 = reconcile(State#backend{exchange = none, lifecycle = Current, detail = Reason}),
    Next =
        case Input of
            {grant, _, _, _} ->
                Next0#backend{
                    grant_result =
                        case GrantAccepted of
                            true -> accepted;
                            false -> rejected
                        end
                };
            _ ->
                prepare_grant(Next0)
        end,
    answer(
        From,
        case Input of
            none -> snapshot(Next);
            {child, _, _, _, _} -> child_result(Input, Observation, Next#backend.interface);
            _ -> Output
        end
    ),
    Next;
response(_Observation, State) ->
    State#backend{ignored = State#backend.ignored + 1}.

%% Correlation and slot identity must agree before an admission result reaches its caller.
-spec child_result(
    hls_supervisor_wire:command(),
    hls_supervisor_wire:observation(),
    hls_supervisor_wire:interface()
) -> child_result().
child_result(
    {child, Operation, _Parent, Slot, Expected},
    #{
        child_slot := Slot,
        child_status := Status,
        child_phase := Phase,
        child_incarnation := Epoch
    },
    #{slots := Slots}
) ->
    [Id] = [Name || {Name, Index} <- maps:to_list(Slots), Index =:= Slot],
    Child = #{id => Id, incarnation => Epoch, phase => Phase},
    case {Operation, Status} of
        {inspect, ok} ->
            {ok, Child};
        {start, accepted} when Epoch > Expected -> {ok, Child};
        {stop, S} when Expected > 0, Epoch =:= Expected, (S =:= accepted orelse S =:= replay) ->
            {ok, Child};
        {_, S} when S =:= ok; S =:= accepted; S =:= replay ->
            error(invalid_child_result);
        _ ->
            {error, {Status, Child}}
    end.

%% Observe initialization before binding a pre-reserved interval; a rejected/lost grant is never silently reallocated.
-spec prepare_grant(#backend{}) -> #backend{}.
prepare_grant(
    State = #backend{
        owner = Owner,
        grant = {First, Last},
        grant_attempted = Previous,
        lifecycle = #domain_state{phase = initializing, current = Epoch}
    }
) when
    is_pid(Owner), Epoch > 0, Epoch =/= Previous
->
    State#backend{
        grant_pending = {grant, Epoch, First, Last}, grant_attempted = Epoch, grant_result = none
    };
prepare_grant(State) ->
    State.

%% A parent snapshot is ready only after its old observer actually terminated.
-spec snapshot(#backend{}) -> {ok, hls_domain_backend:snapshot()} | {error, atom()}.
snapshot(#backend{lifecycle = #domain_state{phase = ready}, endpoint = none, owner = Owner}) when
    is_pid(Owner)
->
    {error, observer_pending};
snapshot(#backend{lifecycle = #domain_state{phase = Phase}, retiring = true}) when
    Phase =:= ready; Phase =:= stopped
->
    {error, observer_pending};
snapshot(#backend{lifecycle = Current, endpoint = Endpoint, detail = Detail}) ->
    Actors =
        case {Current#domain_state.phase, Endpoint} of
            {ready, Pid} when is_pid(Pid) -> #{supervisor => Pid};
            _ -> #{}
        end,
    {ok, #{state => Current, actors => Actors, fault_reason => Detail}}.

%% The observer follows one exact lifetime. Parent management has no prior application frontier to drain.
-spec reconcile(#backend{}) -> #backend{}.
reconcile(State = #backend{retiring = true}) ->
    State;
reconcile(
    State = #backend{
        lifecycle = #domain_state{phase = ready, current = Epoch},
        incarnation = Epoch,
        endpoint = Endpoint
    }
) when is_pid(Endpoint) ->
    State;
reconcile(State = #backend{endpoint = Endpoint, lifecycle = Current}) when is_pid(Endpoint) ->
    Reason =
        case Current#domain_state.phase of
            failed -> {domain_failed, Current#domain_state.fault};
            _ -> shutdown
        end,
    Endpoint ! {retire, self(), Reason},
    State#backend{retiring = true};
reconcile(
    State = #backend{owner = Owner, lifecycle = #domain_state{phase = ready, current = Epoch}}
) when is_pid(Owner), Epoch > 0 ->
    Backend = self(),
    {Endpoint, Monitor} = spawn_monitor(fun() ->
        observer(Backend, monitor(process, Backend), Epoch, gen_server:reqids_new())
    end),
    State#backend{endpoint = Endpoint, endpoint_monitor = Monitor, incarnation = Epoch};
reconcile(State) ->
    State.

%% The exact-lifetime endpoint retains at most nine pending management replies and never blocks retirement.
-spec observer(pid(), reference(), hls_nums:u64(), gen_server:request_id_collection()) ->
    no_return().
observer(Backend, Monitor, Epoch, Requests) ->
    receive
        {retire, Backend, Reason} ->
            observer_retire(Requests),
            exit(Reason);
        {'DOWN', Monitor, process, Backend, _} ->
            observer_retire(Requests),
            exit(noconnection);
        {'$gen_call', From, {child, Operation, Slot, Expected}} ->
            case gen_server:reqids_size(Requests) < 9 of
                true ->
                    Request = gen_server:send_request(
                        Backend, {child, Epoch, Operation, Slot, Expected}
                    ),
                    observer(
                        Backend, Monitor, Epoch, gen_server:reqids_add(Request, From, Requests)
                    );
                false ->
                    gen_server:reply(From, {error, busy}),
                    observer(Backend, Monitor, Epoch, Requests)
            end;
        {'$gen_call', From, _Request} ->
            gen_server:reply(From, {error, lifecycle_only}),
            observer(Backend, Monitor, Epoch, Requests);
        Message ->
            case gen_server:check_response(Message, Requests, true) of
                {{reply, Reply}, From, Rest} ->
                    gen_server:reply(From, Reply),
                    observer(Backend, Monitor, Epoch, Rest);
                {{error, _}, From, Rest} ->
                    gen_server:reply(From, {error, noconnection}),
                    observer(Backend, Monitor, Epoch, Rest);
                _ ->
                    observer(Backend, Monitor, Epoch, Requests)
            end
    end.

%% An endpoint's death must not leave callers waiting for a response from a future incarnation.
-spec observer_retire(gen_server:request_id_collection()) -> ok.
observer_retire(Requests) ->
    [
        gen_server:reply(From, {error, noconnection})
     || {_Request, From} <- gen_server:reqids_to_list(Requests)
    ],
    ok.

%% Polls and delegated-grant exchanges have no waiting application caller.
-spec answer(none | gen_server:from(), term()) -> ok.
answer(none, _Value) -> ok;
answer(From, Value) -> gen_server:reply(From, Value).
