-module(hls_domain_fabric).
-moduledoc """
Framed hardware implementation of hls_domain_backend. A deployment supplies two
independent existing brokers and a matching emitted interface. hls_domain owners
use the same lifecycle calls as hls_domain_erts; hls_node can publish the returned
incarnation-specific actor endpoints as external Erlang PIDs.

Application traffic is typed by retained codecs. Management polls stay separate
from application backpressure. An orderly actor failure waits for every output
promised by the hardware frontier; transport loss instead retires endpoints with
noconnection. No application operation is replayed. Owner loss requests digital
closure only after it is observed; this host process is not a physical watchdog.

Brokers, endpoint exclusion and transport retirement belong to the deployment.
Attachment requires an exclusive fresh response stream starting at sequence one;
restarting this backend is not a transparent reconnect to an arbitrary old stream.
An owner may restart while the backend itself survives and reconciles closure.
""".
-behaviour(gen_server).
-behaviour(hls_domain_backend).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Deployment and shared lifecycle backend interface.
-export([start_link/3, attach/2, status/1, request/3, endpoint/4, stop/1, info/1, send_request/2]).
%% OTP callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-export_type([transport/0, options/0]).

-doc "Independent preexisting broker lanes; optional routes must match the retained generated interface.".
-type transport() :: #{
    management := pid(),
    application := pid(),
    management_route => hls_fabric:route(),
    application_route => hls_fabric:route()
}.
-doc "External effect recipients and finite bounds. pending_limit bounds unacknowledged casts per actor; declared call slots are independent. Timeouts mean uncertainty, never successful fencing.".
-type options() :: #{
    recipients => #{{term(), atom()} => pid()},
    pending_limit => pos_integer(),
    poll_ms => pos_integer(),
    management_timeout_ms => pos_integer(),
    delivery_timeout_ms => pos_integer()
}.

%% Management serialization retains only a bounded queue and one transmitted command.
-type management_kind() :: status | request | retire_status | retire_command.
%% A queued or transmitted command retains one caller and, after transmission, its correlation timer.
-type exchange() :: #{
    kind := management_kind(),
    input := none | hls_domain_lifecycle:input(),
    from := gen_server:from() | none,
    sequence => pos_integer(),
    timer => reference()
}.
%% A live application request owns a hardware slot until an accepted reply or endpoint retirement.
-type pending() :: #{
    actor := term(),
    endpoint := pid(),
    reference := reference(),
    incarnation := hls_nums:u64(),
    mode := call | cast,
    slot := byte(),
    replies := [atom()],
    admitted := boolean()
}.
%% Frontier drain and endpoint monitor completion are distinct retirement stages.
-type retirement() ::
    none
    | #{
        reason := term(),
        frontier := hls_nums:u32(),
        token := reference(),
        timer := reference(),
        sent := boolean()
    }.
-record(backend, {
    management :: pid(),
    application :: pid(),
    management_route :: hls_fabric:route(),
    application_route :: hls_fabric:route(),
    broker_monitors = #{} :: #{reference() => pid()},
    interface :: hls_domain_wire:interface(),
    indices = #{} :: #{hls_nums:u32() => term()},
    recipients = #{} :: #{{term(), atom()} => pid()},
    owner = undefined :: pid() | undefined,
    owner_monitor = undefined :: reference() | undefined,
    authority = undefined :: reference() | undefined,
    lifecycle = #domain_state{} :: hls_domain_lifecycle:state(),
    actors = #{} :: #{term() => pid()},
    actor_monitors = #{} :: #{reference() => term()},
    incarnation = 0 :: hls_nums:u64(),
    fault_reason = none :: term(),
    queue = queue:new() :: queue:queue(exchange()),
    exchange = none :: exchange() | none,
    management_next = 1 :: pos_integer(),
    management_writing = false :: boolean(),
    request_next = 1 :: pos_integer(),
    sends = gen_server:reqids_new() :: gen_server:request_id_collection(),
    pending = #{} :: #{hls_nums:u32() => pending()},
    received = 0 :: hls_nums:u32(),
    frontier = 0 :: hls_nums:u32(),
    retirement = none :: retirement(),
    retiring_owner = false :: boolean(),
    attempts = 0 :: non_neg_integer(),
    ignored = 0 :: non_neg_integer(),
    rejected = 0 :: non_neg_integer(),
    limit = 8 :: pos_integer(),
    send_limit = 16 :: pos_integer(),
    poll_ms = 10 :: pos_integer(),
    management_ms = 1000 :: pos_integer(),
    delivery_ms = 1000 :: pos_integer()
}).

-doc "Attaches to existing independent streams after checking retained codecs. Does not create brokers, reset hardware, start actors or acquire an owner.".
-spec start_link(transport(), hls_domain_wire:interface() | file:filename(), options()) ->
    gen_server:start_ret().
start_link(Transport, Interface, Options) ->
    gen_server:start_link(?MODULE, {Transport, Interface, Options}, []).

-doc "Starts a backend exchange from the attached owner without waiting; caller identity and authority checks remain unchanged.".
-spec send_request(pid(), hls_domain_backend:request()) -> gen_server:request_id().
send_request(Backend, Request) -> gen_server:send_request(Backend, Request).

-doc "Claims local exclusive control without reset. Old-owner retirement must finish before a new attachment succeeds.".
-spec attach(pid(), pid()) -> {ok, reference()} | {error, term()}.
attach(Backend, Owner) -> gen_server:call(Backend, {attach, Owner}).

-doc "Obtains a fresh device snapshot. A response may expose failure while accepted output is still draining.".
-spec status(pid()) -> {ok, hls_domain_backend:snapshot()} | {error, term()}.
status(Backend) -> gen_server:call(Backend, status).

-doc "Submits an authorized transition once. Timeout leaves its outcome unknown; the owner reconciles its existing transition identity.".
-spec request(pid(), reference(), hls_domain_lifecycle:input()) ->
    hls_domain_lifecycle:output() | {error, term()}.
request(Backend, Authority, Input) -> gen_server:call(Backend, {request, Authority, Input}).

-doc "Resolves an exact ready incarnation; old endpoints never follow a stable actor name into its replacement.".
-spec endpoint(pid(), reference(), hls_nums:u64(), term()) -> {ok, pid()} | {error, term()}.
endpoint(Backend, Authority, Incarnation, Actor) ->
    gen_server:call(Backend, {endpoint, Authority, Incarnation, Actor}).

-doc "Stops local endpoints with connection uncertainty. It does not close deployment-owned brokers or certify remote retirement.".
-spec stop(pid()) -> ok.
stop(Backend) -> gen_server:stop(Backend).

-doc "Returns bounded counters and public lifecycle identity, without retaining application work history.".
-spec info(pid()) ->
    #{
        state := hls_domain_lifecycle:state(),
        actors := hls_domain_backend:actors(),
        pending := non_neg_integer(),
        management_queued := non_neg_integer(),
        received := hls_nums:u32(),
        frontier := hls_nums:u32(),
        ignored := non_neg_integer(),
        rejected := non_neg_integer(),
        retiring_owner := boolean()
    }.
info(Backend) -> gen_server:call(Backend, info).

-doc "Registers distinct management/application return routes and monitors both deployment-owned brokers.".
-spec init({transport(), hls_domain_wire:interface() | file:filename(), options()}) ->
    {ok, #backend{}}.
init({#{management := Management, application := Application} = Transport, Interface0, Options}) ->
    true = Management =/= Application,
    Interface =
        #{
            actors := Actors,
            management_route := ManagementRoute,
            application_route := ApplicationRoute
        } =
        hls_domain_wire:load(Interface0),
    ManagementRoute = maps:get(management_route, Transport, ManagementRoute),
    ApplicationRoute = maps:get(application_route, Transport, ApplicationRoute),
    true = ManagementRoute =/= ApplicationRoute,
    Limit = positive(pending_limit, Options, 8),
    SendLimit =
        lists:sum([
            Limit + maps:get(pending_calls, maps:get(contract, B), 0)
         || B <- maps:values(Actors)
        ]) + 16,
    Poll = positive(poll_ms, Options, 10),
    ManagementMs = positive(management_timeout_ms, Options, 1000),
    DeliveryMs = positive(delivery_timeout_ms, Options, 1000),
    Recipients = maps:get(recipients, Options, #{}),
    maps:foreach(
        fun({Id, Port}, Recipient) ->
            #{outputs := Outputs} = maps:get(Id, Actors),
            true = maps:is_key(Port, Outputs) andalso is_pid(Recipient)
        end,
        Recipients
    ),
    ok = hls_fabric:register_route(Management, ManagementRoute, self()),
    ok = hls_fabric:register_route(Application, ApplicationRoute, self()),
    Monitors = maps:from_list([{monitor(process, Pid), Pid} || Pid <- [Management, Application]]),
    erlang:send_after(Poll, self(), poll),
    {ok, #backend{
        management = Management,
        application = Application,
        management_route = ManagementRoute,
        application_route = ApplicationRoute,
        broker_monitors = Monitors,
        interface = Interface,
        indices = maps:from_list([
            {maps:get(index, Actor), Id}
         || {Id, Actor} <- maps:to_list(Actors)
        ]),
        recipients = Recipients,
        limit = Limit,
        send_limit = SendLimit,
        poll_ms = Poll,
        management_ms = ManagementMs,
        delivery_ms = DeliveryMs
    }}.

-doc "Serializes lifecycle requests and exposes only checked incarnation endpoints.".
-spec handle_call(term(), gen_server:from(), #backend{}) ->
    {reply, term(), #backend{}} | {noreply, #backend{}}.
%% Repeating attachment from the same local owner retrieves its unchanged authority.
handle_call({attach, Owner}, {Owner, _}, State = #backend{owner = Owner, authority = Authority}) ->
    {reply, {ok, Authority}, State};
%% A new owner cannot enter during closure of the previous owner's device session.
handle_call(
    {attach, Owner}, {Owner, _}, State = #backend{owner = undefined, retiring_owner = false}
) when node(Owner) =:= node() ->
    Authority = make_ref(),
    {reply, {ok, Authority}, State#backend{
        owner = Owner, authority = Authority, owner_monitor = monitor(process, Owner)
    }};
%% Unresolved owner loss is unavailable, not evidence that the old hardware stopped.
handle_call({attach, _Owner}, _From, State) ->
    {reply, {error, owned_or_retiring}, State};
%% Status uses the separate management lane, never a cached ready assertion.
handle_call(status, From, State) ->
    enqueue(status, none, From, State);
%% Only the caller which owns this exact capability may mutate the device lifecycle.
handle_call(
    {request, Authority, Input},
    {Owner, _} = From,
    State = #backend{owner = Owner, authority = Authority, retiring_owner = false}
) when is_reference(Authority) ->
    enqueue(request, Input, From, State);
%% Readiness is published only after old endpoints have actually terminated.
handle_call(
    {endpoint, Authority, Incarnation, Actor},
    {Owner, _},
    State = #backend{
        owner = Owner,
        authority = Authority,
        lifecycle = #domain_state{phase = ready, current = Incarnation},
        incarnation = Incarnation,
        retirement = none,
        actors = Actors
    }
) when is_reference(Authority) ->
    {reply,
        case maps:find(Actor, Actors) of
            {ok, Pid} -> {ok, Pid};
            error -> {error, unknown_actor}
        end, State};
%% Stale identities and incomplete readiness never resolve through a stable name.
handle_call({endpoint, _, _, _}, _From, State) ->
    {reply, {error, not_ready_or_stale}, State};
%% Metadata remains bounded by declared actors, requests and one retirement frontier.
handle_call(info, _From, State) ->
    {reply,
        #{
            state => State#backend.lifecycle,
            actors => State#backend.actors,
            pending => map_size(State#backend.pending),
            management_queued => queue:len(State#backend.queue),
            received => State#backend.received,
            frontier => State#backend.frontier,
            ignored => State#backend.ignored,
            rejected => State#backend.rejected,
            retiring_owner => State#backend.retiring_owner
        },
        State};
%% Unknown requests cannot gain controller authority.
handle_call(_Request, _From, State) ->
    {reply, {error, unauthorized}, State}.

-doc "Receives typed application requests and checked broker observations; malformed transport evidence closes the backend.".
-spec handle_cast(term(), #backend{}) -> {noreply, #backend{}} | {stop, term(), #backend{}}.
%% The route identifies the lane because broker deliveries intentionally omit the broker PID.
handle_cast({'$hls_fabric_frame', Receipt, Route, Header, Payload}, State) ->
    try
        {Tag, 0, 0} = Header,
        frame(Route, Tag, Payload, State)
    of
        Next ->
            hls_fabric:ack(lane_broker(Route, State), Receipt),
            {noreply, pump(Next)}
    catch
        Class:Reason ->
            hls_fabric:ack(lane_broker(Route, State), Receipt),
            {stop, {invalid_domain_frame, Class, Reason}, State}
    end;
%% Endpoints are immutable bindings; an old or fabricated submitter cannot consume new capacity.
handle_cast({application, Endpoint, Ref, Actor, Incarnation, Mode, Message}, State) ->
    {noreply, application(Endpoint, Ref, Actor, Incarnation, Mode, Message, State)};
%% Unsupported casts have no management interpretation.
handle_cast(_Message, State) ->
    {noreply, State}.

-doc "Observes ownership, endpoint and broker lifetimes while keeping management independent of data backpressure.".
-spec handle_info(term(), #backend{}) -> {noreply, #backend{}} | {stop, term(), #backend{}}.
%% At most one idle status poll is outstanding; time does not accumulate a poll history.
handle_info(poll, State = #backend{poll_ms = Poll, exchange = Exchange, queue = Queue}) ->
    erlang:send_after(Poll, self(), poll),
    Next =
        case Exchange =:= none andalso queue:is_empty(Queue) of
            true -> queue_management(status, none, none, State);
            false -> State
        end,
    {noreply, Next};
%% Local owner death is only a detection event; hardware closure needs its own acknowledged command.
handle_info({'DOWN', Ref, process, _Owner, _Reason}, State = #backend{owner_monitor = Ref}) ->
    Next = retire_now(noconnection, State#backend{
        owner = undefined, owner_monitor = undefined, authority = undefined
    }),
    {noreply, begin_owner_retirement(Next)};
%% A broker loss invalidates readiness independently of the current lifecycle phase.
handle_info(
    {'DOWN', Ref, process, _Broker, Reason}, State = #backend{broker_monitors = Monitors}
) when is_map_key(Ref, Monitors) ->
    {stop, {transport_down, Reason}, State};
%% Endpoint monitors establish actual death before publication of a successor.
handle_info(
    {'DOWN', Ref, process, _Endpoint, Reason}, State = #backend{actor_monitors = Monitors}
) when is_map_key(Ref, Monitors) ->
    {Actor, Rest} = maps:take(Ref, Monitors),
    Next = State#backend{actors = maps:remove(Actor, State#backend.actors), actor_monitors = Rest},
    case State#backend.retirement of
        #{sent := true} ->
            {noreply, reconcile(Next)};
        _ ->
            {noreply,
                begin_owner_retirement(
                    retire_now({endpoint_down, Reason}, Next#backend{retiring_owner = true})
                )}
    end;
%% A timeout does not cancel transmitted work or cause retransmission as a new command.
handle_info(
    {management_timeout, Sequence},
    State = #backend{exchange = #{sequence := Sequence, from := From, kind := Kind}}
) ->
    answer(From, {error, management_timeout}),
    Next = State#backend{exchange = none},
    case Kind of
        K when K =:= retire_status; K =:= retire_command ->
            {noreply, queue_management(retire_status, none, none, Next)};
        _ ->
            {noreply, pump(Next)}
    end;
%% A missing frontier cannot be replaced with an orderly source-failure notification.
handle_info({delivery_timeout, Token}, State = #backend{retirement = #{token := Token}}) ->
    {stop, delivery_frontier_timeout, State};
%% Broker write completion is distinct from hardware admission and application completion.
handle_info(Message, State = #backend{sends = Sends}) ->
    case gen_server:check_response(Message, Sends, true) of
        {{reply, ok}, Tag, Rest} ->
            Writing = State#backend.management_writing andalso Tag =:= 2,
            {noreply, pump(State#backend{sends = Rest, management_writing = Writing})};
        {{reply, Failure}, _Label, Rest} ->
            {stop, {write_failed, Failure}, State#backend{sends = Rest}};
        {{error, Reason}, _Label, Rest} ->
            {stop, {write_failed, Reason}, State#backend{sends = Rest}};
        _ ->
            {noreply, State}
    end.

-doc "Retires local observers with connection uncertainty; transport ownership remains with the deployment.".
-spec terminate(term(), #backend{}) -> ok.
terminate(_Reason, State) ->
    maps:foreach(
        fun(_Actor, Endpoint) -> Endpoint ! {domain_retire, self(), noconnection} end,
        State#backend.actors
    ),
    ok.

%% Deployment option integers are checked once at this untyped startup boundary.
-spec positive(atom(), options(), pos_integer()) -> pos_integer().
positive(Name, Options, Default) ->
    Value = maps:get(Name, Options, Default),
    true = is_integer(Value) andalso Value > 0,
    Value.

%% Queue overflow is a pre-transmission rejection, not a backend crash or hidden retry.
-spec enqueue(
    management_kind(), none | hls_domain_lifecycle:input(), gen_server:from(), #backend{}
) -> {reply, term(), #backend{}} | {noreply, #backend{}}.
enqueue(Kind, Input, From, State = #backend{queue = Queue}) ->
    case queue:len(Queue) < 8 of
        true -> {noreply, queue_management(Kind, Input, From, State)};
        false -> {reply, {error, busy}, State}
    end.

%% Internal management work obeys the same bound and is never an unbounded background queue.
-spec queue_management(
    management_kind(), none | hls_domain_lifecycle:input(), gen_server:from() | none, #backend{}
) -> #backend{}.
queue_management(Kind, Input, From, State = #backend{queue = Queue}) ->
    true = queue:len(Queue) < 8,
    pump(State#backend{queue = queue:in(#{kind => Kind, input => Input, from => From}, Queue)}).

%% One physical management write remains owned even after its logical response deadline.
%% Completion frees the lane; a timeout cannot accumulate background writes.
-spec pump(#backend{}) -> #backend{}.
pump(
    State = #backend{
        exchange = none,
        management_writing = false,
        queue = Queue,
        management_next = Sequence,
        management = Broker,
        management_route = Route,
        interface = Interface,
        management_ms = Timeout
    }
) ->
    case queue:out(Queue) of
        {empty, _} ->
            State;
        {{value, Entry = #{input := Input, kind := Kind}}, Rest} ->
            true = Sequence < (1 bsl 32),
            {Tag, Payload} = hls_domain_wire:management(Sequence, Input, Interface),
            Attempts =
                State#backend.attempts +
                    case Kind of
                        retire_status -> 1;
                        _ -> 0
                    end,
            true = Attempts =< 8,
            Timer = erlang:send_after(Timeout, self(), {management_timeout, Sequence}),
            transmit(Broker, Route, Tag, Payload, State#backend{
                queue = Rest,
                attempts = Attempts,
                management_next = Sequence + 1,
                management_writing = true,
                exchange = Entry#{sequence => Sequence, timer => Timer}
            })
    end;
pump(State) ->
    State.

%% Each lane is independently registered and can only carry its declared message families.
-spec frame(hls_fabric:route(), byte(), binary(), #backend{}) -> #backend{}.
frame(Route, 1, Payload, State = #backend{management_route = Route, interface = Interface}) ->
    {Sequence, Output, Source, Actor, Frontier} = hls_domain_wire:observation(Payload, Interface),
    management_response(Sequence, Output, Source, Actor, Frontier, State);
frame(Route, Tag, Payload, State = #backend{application_route = Route, received = Received}) when
    Tag >= 2, Tag =< 4
->
    Response = #{sequence := Sequence} = hls_domain_wire:application(Tag, Payload),
    true = Sequence =:= Received + 1,
    reconcile(application_response(Response, State#backend{received = Sequence})).

%% Matching current exchanges alone update authoritative controller observations.
-spec management_response(
    hls_nums:u32(),
    hls_domain_lifecycle:output(),
    hls_nums:u16(),
    hls_nums:u32(),
    hls_nums:u32(),
    #backend{}
) -> #backend{}.
management_response(
    Sequence,
    Output = #domain_output{state = Current},
    Source,
    Actor,
    Frontier,
    State = #backend{
        exchange = #{sequence := Sequence, timer := Timer, kind := Kind, from := From},
        frontier = Previous
    }
) ->
    true = Frontier >= Previous,
    true = Current#domain_state.current >= (State#backend.lifecycle)#domain_state.current,
    erlang:cancel_timer(Timer),
    Next = observe(Current, Source, Actor, Frontier, State#backend{
        exchange = none, frontier = Frontier
    }),
    answer(
        From,
        case Kind of
            status -> status_result(Next);
            _ -> Output
        end
    ),
    owner_retirement_response(Kind, Next);
management_response(_Sequence, _Output, _Source, _Actor, _Frontier, State) ->
    ignored(State).

%% A newly observed phase starts an ordered retirement but cannot overtake promised outputs.
-spec observe(
    hls_domain_lifecycle:state(), hls_nums:u16(), hls_nums:u32(), hls_nums:u32(), #backend{}
) -> #backend{}.
observe(
    Current = #domain_state{phase = ready, current = Incarnation},
    _Source,
    _Actor,
    _Frontier,
    State = #backend{incarnation = Incarnation, retirement = none, actors = Actors}
) when map_size(Actors) > 0 ->
    State#backend{lifecycle = Current};
observe(
    Current, Source, Actor, Frontier, State = #backend{actors = Actors, retirement = Retirement}
) ->
    Reason =
        case Source of
            0 ->
                {domain_retired, Current#domain_state.fault};
            _ ->
                {hls_actor_failure, Actor, #{
                    source_code => Source, source_site => Source bsr 4, kind => Source band 15
                }}
        end,
    Next =
        case map_size(Actors) > 0 andalso Retirement =:= none of
            true -> retirement(Reason, Frontier, State);
            false -> State
        end,
    reconcile(Next#backend{lifecycle = Current, fault_reason = Reason}).

%% Publication waits for both ordered retirement delivery and observed endpoint death.
-spec reconcile(#backend{}) -> #backend{}.
reconcile(
    State = #backend{
        retirement = #{frontier := Frontier, sent := false, reason := Reason} = Retirement,
        received = Received
    }
) when Received >= Frontier ->
    maps:foreach(
        fun(_Actor, Endpoint) -> Endpoint ! {domain_retire, self(), Reason} end,
        State#backend.actors
    ),
    reconcile(State#backend{retirement = Retirement#{sent := true}, pending = #{}});
reconcile(State = #backend{retirement = #{sent := true, timer := Timer}, actors = Actors}) when
    map_size(Actors) =:= 0
->
    erlang:cancel_timer(Timer),
    reconcile(State#backend{retirement = none, incarnation = 0});
reconcile(State = #backend{retirement = Retirement}) when Retirement =/= none -> State;
reconcile(
    State = #backend{
        lifecycle = #domain_state{phase = ready, current = Incarnation},
        owner = Owner,
        retiring_owner = false,
        actors = Actors,
        interface = #{actors := Bindings},
        limit = Limit
    }
) when is_pid(Owner), map_size(Actors) =:= 0 ->
    {Endpoints, Monitors} = maps:fold(
        fun(Id, #{contract := Contract}, {Ps, Ms}) ->
            Limits = #{cast => Limit, call => maps:get(pending_calls, Contract, 0)},
            {ok, Endpoint} = hls_domain_endpoint:start(self(), Id, Incarnation, Limits),
            {Ps#{Id => Endpoint}, Ms#{monitor(process, Endpoint) => Id}}
        end,
        {#{}, #{}},
        Bindings
    ),
    State#backend{
        actors = Endpoints,
        actor_monitors = Monitors,
        incarnation = Incarnation,
        fault_reason = none
    };
reconcile(State) ->
    State.

%% A failure observation can remain visible while an orderly output drain is unfinished.
-spec status_result(#backend{}) -> {ok, hls_domain_backend:snapshot()} | {error, atom()}.
status_result(#backend{retiring_owner = true}) ->
    {error, retirement_pending};
status_result(#backend{lifecycle = #domain_state{phase = ready}, retirement = Retirement}) when
    Retirement =/= none
->
    {error, delivery_pending};
status_result(State = #backend{lifecycle = Lifecycle, actors = Actors, retirement = Retirement}) ->
    Visible =
        case Lifecycle#domain_state.phase =:= ready andalso Retirement =:= none of
            true -> Actors;
            false -> #{}
        end,
    {ok, #{state => Lifecycle, actors => Visible, fault_reason => State#backend.fault_reason}}.

%% Type validation precedes I/O; bounded call slots remain owned until an actual typed reply.
-spec application(pid(), reference(), term(), hls_nums:u64(), call | cast, term(), #backend{}) ->
    #backend{}.
application(
    Endpoint,
    Ref,
    Actor,
    Incarnation,
    Mode,
    Message,
    State = #backend{
        actors = Actors,
        lifecycle = #domain_state{phase = Phase, current = Current},
        retirement = Retirement
    }
) ->
    case
        Phase =:= ready andalso Retirement =:= none andalso Incarnation =:= Current andalso
            maps:get(Actor, Actors, none) =:= Endpoint
    of
        false ->
            result(Endpoint, Ref, {error, not_ready_or_stale}),
            State;
        true ->
            admit(Endpoint, Ref, Actor, Incarnation, Mode, Message, State)
    end.

%% Request identities never wrap or get reused after an uncertain write.
-spec admit(pid(), reference(), term(), hls_nums:u64(), call | cast, term(), #backend{}) ->
    #backend{}.
admit(
    Endpoint, Ref, _Actor, _Incarnation, _Mode, _Message, State = #backend{request_next = Next}
) when Next >= (1 bsl 32) ->
    result(Endpoint, Ref, {error, exhausted}),
    State;
admit(
    Endpoint,
    Ref,
    Actor,
    Incarnation,
    Mode,
    Message,
    State = #backend{interface = #{actors := Actors}, pending = Pending, request_next = Request}
) ->
    Binding = maps:get(Actor, Actors),
    case slot(Actor, Mode, Binding, Pending) of
        busy ->
            result(Endpoint, Ref, {error, busy}),
            State;
        Slot ->
            Encoded =
                try hls_domain_wire:request(Binding, Mode, Message, Incarnation, Request, Slot) of
                    {Payload0, Replies0} -> {ok, Payload0, Replies0}
                catch
                    error:Reason -> {error, Reason}
                end,
            case Encoded of
                {ok, Payload, Replies} ->
                    Entry = #{
                        actor => Actor,
                        endpoint => Endpoint,
                        reference => Ref,
                        incarnation => Incarnation,
                        mode => Mode,
                        slot => Slot,
                        replies => Replies,
                        admitted => false
                    },
                    transmit(
                        State#backend.application,
                        State#backend.application_route,
                        2,
                        Payload,
                        State#backend{
                            request_next = Request + 1, pending = Pending#{Request => Entry}
                        }
                    );
                {error, Failure} ->
                    result(Endpoint, Ref, {error, Failure}),
                    State
            end
    end.

%% Casts have no retained reply handle; calls reuse a slot only after their accepted reply.
-spec slot(term(), call | cast, hls_domain_wire:actor(), #{hls_nums:u32() => pending()}) ->
    byte() | busy.
slot(_Actor, cast, _Binding, _Pending) ->
    255;
slot(Actor, call, #{contract := Contract}, Pending) ->
    Used = [S || #{actor := A, mode := call, slot := S} <- maps:values(Pending), A =:= Actor],
    case lists:seq(0, maps:get(pending_calls, Contract, 1) - 1) -- Used of
        [Free | _] -> Free;
        [] -> busy
    end.

%% Stream sequence advances even for stale incarnations; stale contents never release current ownership.
-spec application_response(hls_domain_wire:response(), #backend{}) -> #backend{}.
application_response(#{incarnation := Incarnation}, State = #backend{incarnation = Current}) when
    Incarnation =/= Current
->
    ignored(State);
application_response(
    #{kind := effect, actor := Index, port := Port, header := Header, payload := Payload},
    State = #backend{
        indices = Indices,
        interface = #{actors := Bindings},
        actors = Actors,
        recipients = Recipients
    }
) ->
    Actor = maps:get(Index, Indices),
    Binding = #{ports := Ports, outputs := Outputs} = maps:get(Actor, Bindings),
    [Name] = [Name || {Name, I} <- maps:to_list(Ports), I =:= Port],
    {Tag, 0, Message} = hls_domain_wire:message(Binding, Header, Payload),
    true = lists:member(Tag, maps:get(Name, Outputs)),
    Recipient = maps:get({Actor, Name}, Recipients),
    maps:get(Actor, Actors) ! {domain_effect, self(), Recipient, Message},
    State;
application_response(
    #{kind := Kind, actor := Index, request := Request, disposition := Disposition} = Response,
    State = #backend{pending = Pending, indices = Indices, interface = #{actors := Bindings}}
) ->
    case maps:find(Request, Pending) of
        {ok,
            #{
                actor := Actor,
                endpoint := Endpoint,
                reference := Ref,
                mode := Mode,
                slot := Slot,
                replies := Replies
            } = Entry} ->
            true = maps:get(Index, Indices) =:= Actor,
            case {Kind, Disposition, Mode} of
                {accepted, accepted, cast} ->
                    result(Endpoint, Ref, ok),
                    State#backend{pending = maps:remove(Request, Pending)};
                {accepted, accepted, call} ->
                    Endpoint ! {domain_admitted, self(), Ref},
                    State#backend{pending = Pending#{Request := Entry#{admitted := true}}};
                {accepted, Rejection, _} ->
                    result(Endpoint, Ref, {error, Rejection}),
                    State#backend{
                        pending = maps:remove(Request, Pending),
                        rejected = State#backend.rejected + 1
                    };
                {reply, accepted, call} ->
                    true = maps:get(admitted, Entry),
                    #{header := Header, payload := Payload} = Response,
                    {Tag, Slot, Message} = hls_domain_wire:message(
                        maps:get(Actor, Bindings), Header, Payload
                    ),
                    true = lists:member(Tag, Replies),
                    result(Endpoint, Ref, Message),
                    State#backend{pending = maps:remove(Request, Pending)};
                _ ->
                    error(unexpected_application_response)
            end;
        error ->
            ignored(State)
    end.

%% Keep physical-write ownership separate from controller/application acknowledgements.
-spec transmit(pid(), hls_fabric:route(), byte(), binary(), #backend{}) -> #backend{}.
transmit(Broker, Route, Tag, Payload, State = #backend{sends = Sends, send_limit = Limit}) ->
    true = gen_server:reqids_size(Sends) < Limit,
    Id = hls_fabric:send_request(Broker, Route, {Tag, 0, 0}, Payload, 1000),
    State#backend{sends = gen_server:reqids_add(Id, Tag, Sends)}.

%% Identify the broker solely through this backend's exclusive return routes.
-spec lane_broker(hls_fabric:route(), #backend{}) -> pid().
lane_broker(Route, #backend{management_route = Route, management = Broker}) -> Broker;
lane_broker(Route, #backend{application_route = Route, application = Broker}) -> Broker.

%% One sender orders result/effect delivery before eventual endpoint retirement.
-spec result(pid(), reference(), term()) -> term().
result(Endpoint, Ref, Value) -> Endpoint ! {domain_result, self(), Ref, Value}.

%% Only one finite frontier is retained, not every earlier application operation.
-spec retirement(term(), hls_nums:u32(), #backend{}) -> #backend{}.
retirement(Reason, Frontier, State = #backend{delivery_ms = Timeout}) ->
    Token = make_ref(),
    Timer = erlang:send_after(Timeout, self(), {delivery_timeout, Token}),
    State#backend{
        retirement = #{
            reason => Reason, frontier => Frontier, token => Token, timer => Timer, sent => false
        }
    }.

%% Unknown connection outcome retires local endpoints immediately without asserting remote closure.
-spec retire_now(term(), #backend{}) -> #backend{}.
retire_now(Reason, State = #backend{retirement = Existing, received = Received}) ->
    case Existing of
        none -> ok;
        #{timer := Timer} -> erlang:cancel_timer(Timer)
    end,
    reconcile(retirement(Reason, Received, State)).

%% Drop unsent old-owner commands, then ask hardware before choosing its closure operation.
-spec begin_owner_retirement(#backend{}) -> #backend{}.
begin_owner_retirement(State = #backend{queue = Queue}) ->
    [answer(maps:get(from, Entry), {error, retirement_pending}) || Entry <- queue:to_list(Queue)],
    queue_management(retire_status, none, none, State#backend{
        queue = queue:new(), retiring_owner = true, attempts = 0
    }).

%% Device observations, rather than an owner monitor alone, establish retirement completion.
-spec owner_retirement_response(management_kind(), #backend{}) -> #backend{}.
owner_retirement_response(
    Kind, State = #backend{retiring_owner = true, lifecycle = #domain_state{phase = Phase}}
) when
    (Kind =:= retire_status orelse Kind =:= retire_command) andalso
        (Phase =:= failed orelse Phase =:= unbound)
->
    State#backend{retiring_owner = false};
owner_retirement_response(
    retire_status, State = #backend{retiring_owner = true, lifecycle = Current}
) ->
    Input =
        case Current#domain_state.phase of
            Phase when Phase =:= closing; Phase =:= isolated; Phase =:= initializing ->
                #domain_input{
                    op = abort,
                    expected = Current#domain_state.previous,
                    target = Current#domain_state.target,
                    transition = Current#domain_state.transition,
                    fault = owner_down
                };
            _ ->
                #domain_input{
                    op = fault, expected = Current#domain_state.current, fault = owner_down
                }
        end,
    queue_management(retire_command, Input, none, State);
owner_retirement_response(retire_command, State = #backend{retiring_owner = true}) ->
    queue_management(retire_status, none, none, State);
owner_retirement_response(_Kind, State) ->
    State.

%% Timer-generated queries have no application caller to answer.
-spec answer(gen_server:from() | none, term()) -> ok.
answer(none, _Value) -> ok;
answer(From, Value) -> gen_server:reply(From, Value).

%% Aggregate stale-observation counts have constant storage.
-spec ignored(#backend{}) -> #backend{}.
ignored(State) -> State#backend{ignored = State#backend.ignored + 1}.
