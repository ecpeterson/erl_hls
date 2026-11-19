-module(hls_domain_fabric).
-moduledoc """
Framed hardware implementation of hls_domain_backend. A deployment supplies two
independent existing brokers and a matching emitted interface. hls_domain owners
use the same lifecycle calls as hls_domain_erts; hls_node can publish the returned
incarnation-specific actor endpoints as external Erlang PIDs.

Application traffic is typed by retained codecs. Management polls stay separate
from application backpressure. Orderly shutdown and actor failure wait for every output
promised by the hardware frontier; transport loss instead retires endpoints with
noconnection. No application operation is replayed. Owner loss preserves actors
by default; owner_loss => fail explicitly requests digital closure. Neither is a
physical watchdog.

Brokers, endpoint exclusion and transport retirement belong to the deployment.
Before attachment, isolate the old brokers and establish a fresh nonzero session
through the generated transport-reset/acknowledgement pins. This clears only
packet state; surviving actors keep their incarnation and state. Every frame
carries the session, so delayed old frames cannot impersonate fresh requests.
The deployment owns session non-reuse, including across cold hardware resets.
Host proxies are disposable; hls_domain and hls_node explicitly reattach the
same surviving incarnation after transport loss.

Locally supervised child interfaces acquire an exact-incarnation watch before
exposing endpoints. One immutable hardware retirement record preserves the old
cause and output frontier across autonomous restarts. Acknowledgement follows
ordered output delivery and endpoint death; only then can a successor be watched.
Host lifecycle commands are rejected for these children.
""".
-behaviour(gen_server).
-behaviour(hls_domain_backend).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Deployment and shared lifecycle backend interface.
-export([start_link/3, attach/2, status/1, request/3, endpoint/4, stop/1, info/1, send_request/2]).
%% Application rectangle ingress.
-export([cast_rectangle/3, cast_addresses/1]).
%% OTP callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-export_type([transport/0, options/0]).

-doc "Independent preexisting broker lanes; optional routes must match the retained generated interface.".
-type transport() :: #{
    management := pid(),
    application := pid(),
    session := hls_nums:u64(),
    management_route => hls_fabric:route(),
    application_route => hls_fabric:route()
}.
-doc "External effect recipients and finite bounds. pending_limit bounds unacknowledged casts per actor; declared call slots are independent. Timeouts mean uncertainty, never successful fencing. Locally supervised children require owner_loss => preserve.".
-type options() :: #{
    owner_loss => hls_domain_backend:owner_loss(),
    recipients => #{{term(), atom()} => pid()},
    pending_limit => pos_integer(),
    poll_ms => pos_integer(),
    management_timeout_ms => pos_integer(),
    delivery_timeout_ms => pos_integer()
}.

%% Management serialization retains only a bounded queue and one transmitted command.
-type management_kind() :: status | request | retire_status | retire_command | watch | retire_ack.
%% Publication commands name an exact observed identity; they never reset or start actors.
-type management_input() ::
    none | hls_domain_lifecycle:input() | {watch | retire_ack, hls_nums:u64()}.
%% A queued or transmitted command retains one caller and, after transmission, its correlation timer.
-type exchange() :: #{
    kind := management_kind(),
    input := management_input(),
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
%% One broker-owned application frame may arrive before its independent watch acknowledgement.
-type deferred() ::
    none
    | #{
        route := hls_fabric:route(),
        tag := byte(),
        payload := binary(),
        receipt := reference(),
        incarnation := hls_nums:u64(),
        timer := reference(),
        token := reference()
    }.
-record(backend, {
    session :: hls_nums:u64(),
    supervised = false :: boolean(),
    incarnation_floor = 0 :: hls_nums:u64(),
    reset_seen = false :: boolean(),
    watch_target = 0 :: hls_nums:u64(),
    retired_epoch = 0 :: hls_nums:u64(),
    deferred = none :: deferred(),
    publication = #{watched => 0, retirement => none} :: hls_domain_wire:publication(),
    owner_loss = preserve :: hls_domain_backend:owner_loss(),
    slot_cursor = #{} :: #{term() => byte()},
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

-doc "Obtains a fresh device snapshot. A response may expose failure while accepted output is still draining; locally supervised readiness also waits for a confirmed incarnation watch.".
-spec status(pid()) -> {ok, hls_domain_backend:snapshot()} | {error, term()}.
status(Backend) -> gen_server:call(Backend, status).

-doc "Submits an authorized transition once. Timeout leaves its outcome unknown; the owner reconciles its existing transition identity. Locally supervised child interfaces reject lifecycle commands with supervised_child.".
-spec request(pid(), reference(), hls_domain_lifecycle:input()) ->
    hls_domain_lifecycle:output() | {error, term()}.
request(Backend, Authority, Input) -> gen_server:call(Backend, {request, Authority, Input}).

-doc "Resolves an exact ready incarnation; old endpoints never follow a stable actor name into its replacement.".
-spec endpoint(pid(), reference(), hls_nums:u64(), term()) -> {ok, pid()} | {error, term()}.
endpoint(Backend, Authority, Incarnation, Actor) ->
    gen_server:call(Backend, {endpoint, Authority, Incarnation, Actor}).

-doc "Admit one typed cast to a rectangle on the endpoint's declared target in its current incarnation. Returns ok when the shared ingress accepts the packet. Later ingress waits for every selected actor to consume it. Retirement can interrupt delivery. Timeout or disconnect leaves delivery uncertain.".
-spec cast_rectangle(pid(), hls_domain_wire:bounds(), tuple()) -> ok | {error, term()}.
cast_rectangle(Endpoint, Bounds, Message) ->
    gen_server:call(Endpoint, {'$hls_rectangle_cast', Bounds, Message}).

-doc "Read the cast addresses bound when this endpoint was published. A rectangle entry gives the source target, point and dimensions. Deployment code can compare these with its application coordinates before exposing a broadcast bank.".
-spec cast_addresses(pid()) -> #{atom() => map()}.
cast_addresses(Endpoint) -> gen_server:call(Endpoint, '$hls_cast_addresses').

-doc "Stops local endpoints with connection uncertainty. It does not close deployment-owned brokers or certify remote retirement.".
-spec stop(pid()) -> ok.
stop(Backend) -> gen_server:stop(Backend).

-doc "Returns bounded counters and public lifecycle identity, without retaining application work history.".
-spec info(pid()) ->
    #{
        session := hls_nums:u64(),
        supervised := boolean(),
        publication := hls_domain_wire:publication(),
        deferred := boolean(),
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
init({
    #{management := Management, application := Application, session := Session} = Transport,
    Interface0,
    Options
}) ->
    true = is_integer(Session) andalso Session > 0 andalso Session < (1 bsl 64),
    OwnerLoss = maps:get(owner_loss, Options, preserve),
    true = OwnerLoss =:= preserve orelse OwnerLoss =:= fail,
    true = Management =/= Application,
    Interface =
        #{
            actors := Actors,
            management_route := ManagementRoute,
            application_route := ApplicationRoute
        } =
        hls_domain_wire:load(Interface0),
    Supervised = maps:get(supervision, Interface, none) =:= local,
    true = not Supervised orelse OwnerLoss =:= preserve,
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
        session = Session,
        supervised = Supervised,
        owner_loss = OwnerLoss,
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
%% The compiled supervisor alone owns child lifecycle; host attachment grants observation only.
handle_call(
    {request, Authority, _Input},
    {Owner, _},
    State = #backend{owner = Owner, authority = Authority, supervised = true}
) when
    is_reference(Authority)
->
    {reply, {error, supervised_child}, State};
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
            session => State#backend.session,
            supervised => State#backend.supervised,
            publication => State#backend.publication,
            deferred => State#backend.deferred =/= none,
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
        receive_frame(Receipt, Route, Tag, Payload, State)
    of
        {Next, Acknowledge} ->
            case Acknowledge of
                true -> hls_fabric:ack(lane_broker(Route, State), Receipt);
                false -> ok
            end,
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
%% Owner authority is revocable independently of actor lifetime or outstanding work.
handle_info(
    {'DOWN', Ref, process, _Owner, _Reason},
    State = #backend{owner_monitor = Ref, owner_loss = preserve}
) ->
    {noreply, State#backend{owner = undefined, owner_monitor = undefined, authority = undefined}};
%% Explicit owner-loss failure policy requires an acknowledged hardware command.
handle_info(
    {'DOWN', Ref, process, _Owner, _Reason},
    State = #backend{owner_monitor = Ref, owner_loss = fail}
) ->
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
            %% A disposable host proxy is not evidence that its remote actor failed.
            {stop, {endpoint_down, Reason}, Next}
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
%% A missing watch acknowledgement cannot leave an accepted application frame retained forever.
handle_info({watch_delivery_timeout, Token}, State = #backend{deferred = #{token := Token}}) ->
    {stop, watch_delivery_timeout, State};
%% A missing frontier cannot be replaced with an orderly source-failure notification.
handle_info({delivery_timeout, Token}, State = #backend{retirement = #{token := Token}}) ->
    {stop, delivery_frontier_timeout, State};
%% Broker write completion is distinct from hardware admission and application completion.
handle_info(Message, State = #backend{sends = Sends}) ->
    case gen_server:check_response(Message, Sends, true) of
        {{reply, ok}, Tag, Rest} ->
            Writing = State#backend.management_writing andalso Tag =/= management,
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
    management_kind(), management_input(), gen_server:from(), #backend{}
) -> {reply, term(), #backend{}} | {noreply, #backend{}}.
enqueue(Kind, Input, From, State = #backend{queue = Queue}) ->
    case queue:len(Queue) < 8 of
        true -> {noreply, queue_management(Kind, Input, From, State)};
        false -> {reply, {error, busy}, State}
    end.

%% Internal management work obeys the same bound and is never an unbounded background queue.
-spec queue_management(
    management_kind(), management_input(), gen_server:from() | none, #backend{}
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
            {Tag, Payload} =
                case Input of
                    {Operation, _Epoch} when Operation =:= watch; Operation =:= retire_ack ->
                        hls_domain_wire:publication(State#backend.session, Sequence, Input);
                    _ ->
                        hls_domain_wire:management(
                            State#backend.session, Sequence, Input, Interface
                        )
                end,
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

%% Independent brokers can deliver a new watched effect before the management acknowledgement.
-spec receive_frame(reference(), hls_fabric:route(), byte(), binary(), #backend{}) ->
    {#backend{}, boolean()}.
receive_frame(
    Receipt,
    Route,
    4,
    Payload = <<Session:64/little, _/binary>>,
    State = #backend{
        supervised = true,
        application_route = Route,
        session = Session,
        actors = Actors,
        watch_target = Target,
        received = Received,
        deferred = Held
    }
) when
    map_size(Actors) =:= 0, Target > 0
->
    Response = hls_domain_wire:application(4, Payload),
    case Response of
        #{incarnation := Target, sequence := Sequence} ->
            true = Held =:= none,
            true = Sequence =:= Received + 1,
            Token = make_ref(),
            Timer = erlang:send_after(
                State#backend.delivery_ms, self(), {watch_delivery_timeout, Token}
            ),
            {
                State#backend{
                    deferred = #{
                        route => Route,
                        tag => 4,
                        payload => Payload,
                        receipt => Receipt,
                        incarnation => Target,
                        token => Token,
                        timer => Timer
                    }
                },
                false
            };
        _ ->
            {flush_deferred(frame(Route, 4, Payload, State)), true}
    end;
receive_frame(_Receipt, Route, Tag, Payload, State) ->
    {flush_deferred(frame(Route, Tag, Payload, State)), true}.

%% The held broker receipt is released only after the exact lifetime has a delivery endpoint.
-spec flush_deferred(#backend{}) -> #backend{}.
flush_deferred(
    State = #backend{
        incarnation = Epoch,
        actors = Actors,
        deferred = #{
            incarnation := Epoch,
            route := Route,
            tag := Tag,
            payload := Payload,
            receipt := Receipt,
            timer := Timer
        }
    }
) when map_size(Actors) > 0 ->
    erlang:cancel_timer(Timer),
    Next = frame(Route, Tag, Payload, State#backend{deferred = none}),
    hls_fabric:ack(lane_broker(Route, State), Receipt),
    Next;
flush_deferred(State) ->
    State.

%% Each lane is independently registered and can only carry its declared message families.
-spec frame(hls_fabric:route(), byte(), binary(), #backend{}) -> #backend{}.
%% A complete foreign-session frame cannot update counters, readiness or pending calls.
frame(_Route, _Tag, <<Session:64/little, _/binary>>, State = #backend{session = Current}) when
    Session =/= Current
->
    ignored(State);
frame(
    Route,
    1,
    Payload,
    State = #backend{
        management_route = Route, interface = Interface, session = Session, supervised = true
    }
) ->
    {{Session, Sequence, Output, Source, Actor, Frontier}, Publication} =
        hls_domain_wire:supervision(Payload, Interface),
    supervised_response(Sequence, Output, Source, Actor, Frontier, Publication, State);
frame(
    Route,
    1,
    Payload,
    State = #backend{management_route = Route, interface = Interface, session = Session}
) ->
    {Session, Sequence, Output, Source, Actor, Frontier} = hls_domain_wire:observation(
        Payload, Interface
    ),
    management_response(Sequence, Output, Source, Actor, Frontier, State);
frame(
    Route,
    Tag,
    Payload,
    State = #backend{application_route = Route, received = Received, session = Session}
) when
    Tag >= 2, Tag =< 4
->
    Response =
        #{session := Session, sequence := Sequence} = hls_domain_wire:application(Tag, Payload),
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

%% Only the matching management exchange can install a publication receipt or acknowledge it.
-spec supervised_response(
    hls_nums:u32(),
    hls_domain_lifecycle:output(),
    hls_nums:u16(),
    hls_nums:u32(),
    hls_nums:u32(),
    hls_domain_wire:publication(),
    #backend{}
) -> #backend{}.
supervised_response(
    Sequence,
    Output = #domain_output{state = Current, status = Status},
    _Source,
    _Actor,
    Frontier,
    Publication,
    State = #backend{
        exchange = #{
            sequence := Sequence,
            timer := Timer,
            kind := Kind,
            input := Input,
            from := From
        },
        frontier = Previous,
        publication = Before
    }
) ->
    true = Frontier >= Previous,
    ok = publication_response(Kind, Input, Status, Before, Publication),
    Checked = supervised_identity(Current, State#backend{publication = Publication}),
    erlang:cancel_timer(Timer),
    Next = observe_publication(Publication, Checked#backend{
        lifecycle = Current, frontier = Frontier, exchange = none
    }),
    answer(
        From,
        case Kind of
            status -> status_result(Next);
            _ -> Output
        end
    ),
    Next;
supervised_response(_Sequence, _Output, _Source, _Actor, _Frontier, _Publication, State) ->
    ignored(State).

%% A parent-owned child reset may show zero while its old receipt survives. It never lowers the identity floor.
-spec supervised_identity(hls_domain_lifecycle:state(), #backend{}) -> #backend{}.
supervised_identity(
    #domain_state{current = 0, phase = Phase},
    State = #backend{incarnation_floor = Floor, actors = Actors, publication = Publication}
) when
    Phase =/= ready
->
    #{retirement := Receipt} = Publication,
    true = map_size(Actors) =:= 0 orelse Receipt =/= none,
    State#backend{reset_seen = Floor > 0};
supervised_identity(
    #domain_state{current = Epoch},
    State = #backend{incarnation_floor = Floor, reset_seen = Reset}
) when
    Epoch > 0, Epoch >= Floor, not Reset orelse Epoch > Floor
->
    State#backend{incarnation_floor = Epoch, reset_seen = false};
supervised_identity(_Current, _State) ->
    error(incarnation_regression).

%% An immutable receipt may disappear only in response to its exact acknowledgement.
-spec publication_response(
    management_kind(),
    management_input(),
    hls_domain_lifecycle:status(),
    hls_domain_wire:publication(),
    hls_domain_wire:publication()
) -> ok.
publication_response(
    retire_ack,
    {retire_ack, Epoch},
    Status,
    #{retirement := #{incarnation := Epoch}},
    #{watched := 0, retirement := none}
) when
    Status =:= accepted; Status =:= replay
->
    ok;
publication_response(retire_ack, _Input, _Status, _Before, _After) ->
    error(invalid_retirement_acknowledgement);
publication_response(
    watch,
    {watch, Epoch},
    Status,
    #{retirement := none},
    #{watched := Epoch}
) when Status =:= accepted; Status =:= replay ->
    ok;
publication_response(
    watch,
    {watch, _Epoch},
    stale,
    #{retirement := none},
    #{watched := 0, retirement := none}
) ->
    ok;
publication_response(watch, _Input, _Status, _Before, _After) ->
    error(invalid_watch_acknowledgement);
publication_response(_Kind, _Input, _Status, #{retirement := Before}, #{retirement := After}) ->
    true = Before =:= none orelse Before =:= After,
    ok.

%% A skipped incarnation never supplies a guessed terminal cause for a published endpoint.
-spec observe_publication(hls_domain_wire:publication(), #backend{}) -> #backend{}.
observe_publication(
    #{retirement := Receipt = #{incarnation := Epoch, frontier := Frontier}},
    State = #backend{incarnation = Epoch, actors = Actors, retirement = none}
) when
    map_size(Actors) > 0
->
    Reason = receipt_reason(Receipt),
    reconcile(retirement(Reason, Frontier, State#backend{fault_reason = Reason}));
observe_publication(
    #{retirement := Receipt = #{incarnation := Epoch, frontier := Frontier}},
    State = #backend{watch_target = Epoch, actors = Actors, retirement = none}
) when
    map_size(Actors) =:= 0
->
    Reason = receipt_reason(Receipt),
    Closing = create_endpoints(Epoch, State),
    reconcile(retirement(Reason, Frontier, Closing#backend{fault_reason = Reason}));
observe_publication(
    #{watched := Epoch, retirement := none},
    State = #backend{
        incarnation = Epoch,
        actors = Actors,
        lifecycle = #domain_state{current = Epoch, phase = ready}
    }
) when map_size(Actors) > 0 ->
    State;
observe_publication(
    #{retirement := #{incarnation := Epoch}},
    State = #backend{incarnation = Epoch, retirement = Retirement}
) when Retirement =/= none ->
    reconcile(State);
observe_publication(_Publication, State = #backend{actors = Actors}) when map_size(Actors) =:= 0 ->
    reconcile(State);
observe_publication(_Publication, _State) ->
    error(missing_retirement_evidence).

%% The cause belongs to the departed lifetime, never the latest replacement snapshot.
-spec receipt_reason(hls_domain_wire:retirement()) -> term().
receipt_reason(#{
    incarnation := Epoch,
    phase := Phase,
    fault := Fault,
    source := Source,
    actor := Actor
}) ->
    retirement_reason(
        #domain_state{
            current = Epoch,
            previous = Epoch,
            target = Epoch,
            phase = Phase,
            fault = Fault
        },
        Source,
        Actor
    ).

%% One receipt and one exact watch command bound publication independently of application work.
-spec publication_progress(#backend{}) -> #backend{}.
publication_progress(
    State = #backend{
        retired_epoch = Epoch,
        publication = #{retirement := #{incarnation := Epoch}}
    }
) ->
    publication_command(retire_ack, Epoch, State);
publication_progress(#backend{publication = #{retirement := Receipt}}) when Receipt =/= none ->
    error(unowned_retirement_evidence);
publication_progress(
    State = #backend{
        retired_epoch = Retired,
        publication = #{watched := 0, retirement := none},
        lifecycle = #domain_state{phase = ready, current = Epoch}
    }
) when Epoch =< Retired ->
    State;
publication_progress(#backend{
    retired_epoch = Retired,
    publication = #{watched := Epoch, retirement := none}
}) when Epoch > 0, Epoch =< Retired ->
    error(retired_incarnation_reused);
publication_progress(
    State = #backend{
        publication = #{watched := Epoch, retirement := none},
        lifecycle = #domain_state{phase = ready, current = Epoch}
    }
) when Epoch > 0 ->
    publish_endpoints(State);
publication_progress(
    State = #backend{
        publication = #{watched := 0, retirement := none},
        lifecycle = #domain_state{phase = ready, current = Epoch},
        owner = Owner
    }
) when
    Epoch > 0, is_pid(Owner)
->
    publication_command(watch, Epoch, State);
publication_progress(State) ->
    State.

%% Queued calls cannot create duplicate internal commands or exceed the existing finite queue.
-spec publication_command(watch | retire_ack, hls_nums:u64(), #backend{}) -> #backend{}.
publication_command(Kind, Epoch, State = #backend{exchange = Exchange, queue = Queue}) ->
    Pending =
        case Exchange of
            #{kind := Kind} -> true;
            _ -> false
        end orelse
            lists:any(fun(#{kind := K}) -> K =:= Kind end, queue:to_list(Queue)),
    case not Pending andalso queue:len(Queue) < 8 of
        true ->
            Next =
                case Kind of
                    watch -> State#backend{watch_target = Epoch};
                    retire_ack -> State
                end,
            queue_management(Kind, {Kind, Epoch}, none, Next);
        false ->
            State
    end.

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
    Reason = retirement_reason(Current, Source, Actor),
    Next =
        case map_size(Actors) > 0 andalso Retirement =:= none of
            true -> retirement(Reason, Frontier, State);
            false -> State
        end,
    reconcile(Next#backend{lifecycle = Current, fault_reason = Reason}).

%% Explicit stop has ordinary shutdown semantics; existing source failures retain their cause.
-spec retirement_reason(hls_domain_lifecycle:state(), hls_nums:u16(), hls_nums:u32()) -> term().
retirement_reason(
    #domain_state{
        phase = Phase, current = Current, previous = Current, target = Current, fault = none
    },
    0,
    _Actor
) when Current =/= 0, Phase =:= closing orelse Phase =:= stopped ->
    shutdown;
retirement_reason(#domain_state{fault = Fault}, 0, _Actor) ->
    {domain_retired, Fault};
retirement_reason(_Current, Source, Actor) ->
    {hls_actor_failure, Actor, #{
        source_code => Source, source_site => Source bsr 4, kind => Source band 15
    }}.

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
    reconcile(State#backend{
        retirement = none,
        retired_epoch = State#backend.incarnation,
        incarnation = 0
    });
reconcile(State = #backend{retirement = Retirement}) when Retirement =/= none -> State;
reconcile(State = #backend{supervised = true}) ->
    publication_progress(State);
reconcile(State) ->
    publish_endpoints(State).

%% All publication paths share the same bounded immutable incarnation endpoints.
-spec publish_endpoints(#backend{}) -> #backend{}.
publish_endpoints(
    State = #backend{
        lifecycle = #domain_state{phase = ready, current = Incarnation},
        owner = Owner,
        retiring_owner = false,
        actors = Actors
    }
) when is_pid(Owner), map_size(Actors) =:= 0 ->
    create_endpoints(Incarnation, State);
publish_endpoints(State) ->
    State.

%% Private closing endpoints can deliver an accepted watch's output without publishing a dead lifetime.
-spec create_endpoints(hls_nums:u64(), #backend{}) -> #backend{}.
create_endpoints(Incarnation, State = #backend{interface = #{actors := Bindings}, limit = Limit}) ->
    {Endpoints, Monitors} = maps:fold(
        fun(Id, Binding = #{contract := Contract}, {Ps, Ms}) ->
            Ingress = maps:get(ingress, Binding, #{}),
            Addresses = maps:from_list([
                {Tag, maps:get(Tag, Ingress, #{})}
             || Tag <- maps:get(casts, Contract)
            ]),
            Limits = #{
                cast => Limit,
                call => maps:get(pending_calls, Contract, 0),
                addresses => Addresses
            },
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
        watch_target = 0,
        fault_reason = none
    }.

%% Failures remain observable during drain; ready/stopped completion also requires endpoint retirement.
-spec status_result(#backend{}) -> {ok, hls_domain_backend:snapshot()} | {error, atom()}.
status_result(#backend{retiring_owner = true}) ->
    {error, retirement_pending};
status_result(#backend{lifecycle = #domain_state{phase = Phase}, retirement = Retirement}) when
    Retirement =/= none, Phase =:= ready orelse Phase =:= stopped
->
    {error, delivery_pending};
status_result(#backend{
    supervised = true,
    owner = Owner,
    actors = Actors,
    lifecycle = #domain_state{phase = ready}
}) when is_pid(Owner), map_size(Actors) =:= 0 ->
    {error, publication_pending};
status_result(State = #backend{lifecycle = Lifecycle, actors = Actors, retirement = Retirement}) ->
    Visible =
        case Lifecycle#domain_state.phase =:= ready andalso Retirement =:= none of
            true -> Actors;
            false -> #{}
        end,
    {ok, #{state => Lifecycle, actors => Visible, fault_reason => State#backend.fault_reason}}.

%% Type validation precedes I/O; bounded call slots remain owned until an actual typed reply.
-spec application(
    pid(),
    reference(),
    term(),
    hls_nums:u64(),
    call | cast | {rectangle, hls_domain_wire:bounds()},
    term(),
    #backend{}
) ->
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
-spec admit(
    pid(),
    reference(),
    term(),
    hls_nums:u64(),
    call | cast | {rectangle, hls_domain_wire:bounds()},
    term(),
    #backend{}
) ->
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
    Credit =
        case Mode of
            {rectangle, _} -> cast;
            _ -> Mode
        end,
    case slot(Actor, Credit, Binding, Pending, maps:get(Actor, State#backend.slot_cursor, 0)) of
        busy ->
            result(Endpoint, Ref, {error, busy}),
            State;
        Slot ->
            Encoded =
                try
                    hls_domain_wire:request(
                        Binding, Mode, Message, State#backend.session, Incarnation, Request, Slot
                    )
                of
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
                        mode => Credit,
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
                            request_next = Request + 1,
                            pending = Pending#{Request => Entry},
                            slot_cursor =
                                case Credit of
                                    call ->
                                        (State#backend.slot_cursor)#{
                                            Actor => (Slot + 1) rem
                                                maps:get(
                                                    pending_calls, maps:get(contract, Binding), 1
                                                )
                                        };
                                    cast ->
                                        State#backend.slot_cursor
                                end
                        }
                    );
                {error, Failure} ->
                    result(Endpoint, Ref, {error, Failure}),
                    State
            end
    end.

%% Rotate among host-free slots so repeated pre-admission busy rejections can pass an abandoned hardware slot. Never retry an uncertain request.
-spec slot(term(), call | cast, hls_domain_wire:actor(), #{hls_nums:u32() => pending()}, byte()) ->
    byte() | busy.
slot(_Actor, cast, _Binding, _Pending, _Cursor) ->
    255;
slot(Actor, call, #{contract := Contract}, Pending, Cursor) ->
    Used = [S || #{actor := A, mode := call, slot := S} <- maps:values(Pending), A =:= Actor],
    Bound = maps:get(pending_calls, Contract, 1),
    Slots = [(Cursor + Offset) rem Bound || Offset <- lists:seq(0, Bound - 1)],
    case Slots -- Used of
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
    Lane =
        case Broker =:= State#backend.management of
            true -> management;
            false -> application
        end,
    State#backend{sends = gen_server:reqids_add(Id, Lane, Sends)}.

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
    maps:foreach(
        fun(_Actor, Endpoint) -> Endpoint ! {domain_closing, self()} end,
        State#backend.actors
    ),
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
        (Phase =:= failed orelse Phase =:= unbound orelse Phase =:= stopped)
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
