-module(hls_domain_board_client).
-moduledoc """
Platform client for the independent-role board's bootstrap and passive inspection routes.

This process owns only routes {0,4} and {0,3} on an existing management-bank
broker. Domain/endpoint management remains on its existing routes. Establishing
a host session resets parsers only: it never resets actors, endpoints, carrier
state or a link namespace. The caller must quiesce, drain and acknowledge both
DMA banks at packet boundaries before establishing a session, with no pending
or newly arriving native response throughout establishment. Qualification uses
startup or drained failed domains; an old arbiter lock alone cannot exclude a
same-edge response. In-band control cannot cancel a partial blocked DMA transfer
or promise transparent reconnect.

One request is outstanding, with a finite deadline and no automatic retry. A
lost establish reply retains its target until a later ordered status observation;
that observation reports what happened, without automatically resuming clients.
A fresh process must use a reserved request-ID range or a confirmed drained
boundary. The configured first request is explicit and never wraps.
""".
-behaviour(gen_server).

%% Existing broker ownership and bounded control operations.
-export([start_link/2, status/1, establish/2, inspect/4, stop/1]).
%% Pure canonical wire codec for platform fixtures and diagnostics.
-export([command/2, observation/3]).
-export_type([options/0, operation/0, status_code/0, snapshot/0, reply/0]).
%% Ordinary OTP lifecycle; no application data forwarding.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-doc "An explicit fresh request range and optional finite deadline; route reuse additionally requires the broker's drained-boundary contract.".
-type options() :: #{first_request := 1..((1 bsl 32) - 1), timeout_ms => pos_integer()}.
-doc "Only parser-session establishment mutates state. Inspection addresses a global actor ID under an exact domain lifetime.".
-type operation() :: status | {establish, hls_nums:u64()} |
    {inspect, hls_nums:u64(), hls_nums:u64(), hls_nums:u32()}.
-doc "ABI version one's explicit local response codes.".
-type status_code() :: ok | replay | stale | malformed | not_attached | unsupported.
-doc "One board-status or scoped passive-inspection response. Phase stays a native encoded value; retained domain metadata supplies its names.".
-type snapshot() :: #{kind := board, request := hls_nums:u32(), status := status_code(),
    abi := 1, role := 1 | 2, domain_session := hls_nums:u64(), endpoint_session := hls_nums:u64(),
    incarnation := hls_nums:u64(), health := map()} |
    #{kind := inspection, request := hls_nums:u32(), status := status_code(),
        session := hls_nums:u64(), incarnation := hls_nums:u64(), actor := hls_nums:u32(), value := binary()}.
-doc "A decoded response preserves hardware rejection status. Uncertainty never means a successful session change.".
-type reply() :: {ok, snapshot()} | {error, term()}.
%% One immutable target and response correlation survive a missing reply.
-type pending() :: none | #{request := hls_nums:u32(), operation := operation(),
    route := hls_fabric:route(), from := gen_server:from(), timer := reference()}.
%% No waiting queue, application payload or replay history is retained.
-record(client, {broker :: pid(), monitor :: reference(), next :: pos_integer(),
    timeout = 3000 :: pos_integer(), pending = none :: pending(),
    write = none :: none | gen_server:request_id(), uncertain = none :: none | hls_nums:u64()}).

-doc "Claims the two platform routes on an existing management-bank broker. Does not establish a session, open a device, drain DMA or modify a native lifetime.".
-spec start_link(pid(), options()) -> gen_server:start_ret().
start_link(Broker, Options) -> gen_server:start_link(?MODULE, {Broker, Options}, []).

-doc "Obtains current sessions, lifecycle and fault health. A canonical response resolves retained establish uncertainty; it does not attach any other runtime client.".
-spec status(pid()) -> reply().
status(Client) -> gen_server:call(Client, status, infinity).

-doc "Requests a strictly newer nonzero parser session after both DMA banks are externally quiesced/drained/acknowledged, with no pending or newly arriving native response throughout establishment (startup or drained failed domains). Equal already-attached sessions may return replay. A lost reply requires status before any further establish; no retry is automatic.".
-spec establish(pid(), hls_nums:u64()) -> reply().
establish(Client, Session) -> gen_server:call(Client, {establish, Session}, infinity).

-doc "Reads the existing 128-bit passive snapshot under an exact attached session and ready incarnation. Unknown/nonlocal actor IDs return the hardware's zero value; this client invents no catalog or actor state.".
-spec inspect(pid(), hls_nums:u64(), hls_nums:u64(), hls_nums:u32()) -> reply().
inspect(Client, Session, Incarnation, Actor) ->
    gen_server:call(Client, {inspect, Session, Incarnation, Actor}, infinity).

-doc "Stops this route owner only. The deployment still owns the broker, DMA descriptors and native state.".
-spec stop(pid()) -> ok.
stop(Client) -> gen_server:stop(Client).

-doc "Encodes complete little-endian payload words for the existing routed-frame broker. Header tuples are {operation,txid,flags}; response routes are retained, never swapped. Invalid identifiers raise before transmission.".
-spec command(hls_nums:u32(), operation()) -> {hls_fabric:route(), hls_fabric:header(), binary()}.
command(Request, Operation) when Request > 0, Request < (1 bsl 32) ->
    case Operation of
        status -> {{0, 4}, {0, 0, 0}, <<Request:32/little>>};
        {establish, Session} when Session > 0, Session < (1 bsl 64) ->
            {{0, 4}, {1, 0, 0}, <<Request:32/little, Session:64/little>>};
        {inspect, Session, Incarnation, Actor} when Session > 0, Session < (1 bsl 64),
            Incarnation > 0, Incarnation < (1 bsl 64), Actor >= 0, Actor < (1 bsl 32) ->
            {{0, 3}, {0, 0, 0}, <<Session:64/little, Incarnation:64/little, Actor:32/little, Request:32/little>>}
    end.

-doc "Decodes exactly eleven canonical response words. Rejects wrong route/tag/header flags, ABI, role, status and reserved health bits. Inspection bytes remain four little-endian words in a 16-byte binary.".
-spec observation(hls_fabric:route(), hls_fabric:header(), binary()) -> snapshot().
observation({0, 4}, {128, 0, 0}, <<Request:32/little, Code:32/little, 1:32/little, Role:32/little,
    DomainSession:64/little, EndpointSession:64/little, Incarnation:64/little, Health:32/little>>)
    when Role =:= 1; Role =:= 2 ->
    true = Health bsr 17 =:= 0,
    #{kind => board, request => Request, status => status_code(Code), abi => 1, role => Role,
        domain_session => DomainSession, endpoint_session => EndpointSession, incarnation => Incarnation,
        health => #{phase_code => Health band 7, domain_attached => bit(Health, 3),
            endpoint_attached => bit(Health, 4), domain_wire_fault => bit(Health, 5),
            endpoint_wire_fault => bit(Health, 6), router_fault => bit(Health, 7),
            carrier_fault => (Health bsr 8) band 255, carrier_armed => bit(Health, 16)}};
observation({0, 3}, {128, 0, 0}, <<Request:32/little, Code:32/little, Session:64/little,
    Incarnation:64/little, Actor:32/little, Value:16/binary>>) ->
    Status = status_code(Code),
    true = Status =:= ok orelse Value =:= <<0:128>>,
    #{kind => inspection, request => Request, status => Status, session => Session,
        incarnation => Incarnation, actor => Actor, value => Value}.

%% Status is a fixed platform ABI, independent of the native endpoint atom codec.
-spec status_code(0..5) -> status_code().
status_code(0) -> ok;
status_code(1) -> replay;
status_code(2) -> stale;
status_code(3) -> malformed;
status_code(4) -> not_attached;
status_code(5) -> unsupported.

%% Health bits preserve explicit boolean meaning without copying a second raw-health authority.
-spec bit(non_neg_integer(), non_neg_integer()) -> boolean().
bit(Value, Offset) -> Value band (1 bsl Offset) =/= 0.

-doc "Validates finite local bounds and registers only the two platform routes.".
-spec init({pid(), options()}) -> {ok, #client{}}.
init({Broker, #{first_request := First} = Options}) ->
    true = is_integer(First) andalso First > 0 andalso First < (1 bsl 32),
    [] = maps:keys(Options) -- [first_request, timeout_ms],
    Timeout = maps:get(timeout_ms, Options, 3000),
    true = is_integer(Timeout) andalso Timeout > 0,
    ok = hls_fabric:register_route(Broker, {0, 4}, self()),
    ok = hls_fabric:register_route(Broker, {0, 3}, self()),
    {ok, #client{broker = Broker, monitor = monitor(process, Broker), next = First, timeout = Timeout}}.

-doc "Admits one bounded control request; no queue can accumulate behind a blocked physical write.".
-spec handle_call(term(), gen_server:from(), #client{}) -> {reply, term(), #client{}} | {noreply, #client{}}.
%% A transmitted unknown session change must be observed before another mutation.
handle_call({establish, _}, _From, State = #client{uncertain = Session}) when Session =/= none ->
    {reply, {error, {outcome_unknown, Session}}, State};
%% A finite request and its physical writer must both finish before a successor is admitted.
handle_call(_, _From, State = #client{pending = Pending, write = Write}) when Pending =/= none; Write =/= none ->
    {reply, {error, busy}, State};
%% Request identities never wrap into an old response's correlation range.
handle_call(_, _From, State = #client{next = Next}) when Next >= (1 bsl 32) ->
    {reply, {error, exhausted}, State};
%% Only the documented pure codec can authorize a physical request.
handle_call(Operation, From, State) ->
    case encode(State#client.next, Operation) of
        error -> {reply, {error, invalid}, State};
        {ok, {Route, Header, Payload}} ->
            Request = State#client.next,
            Write = hls_fabric:send_request(State#client.broker, Route, Header, Payload, State#client.timeout),
            Timer = erlang:send_after(State#client.timeout, self(), {deadline, Request}),
            {noreply, State#client{next = Request + 1, write = Write,
                pending = #{request => Request, operation => Operation, route => Route, from => From, timer => Timer}}}
    end.

%% Untyped public requests fail locally instead of constructing a truncated physical frame.
-spec encode(hls_nums:u32(), term()) -> {ok, {hls_fabric:route(), hls_fabric:header(), binary()}} | error.
encode(Request, Operation) -> try {ok, command(Request, Operation)} catch error:_ -> error end.

-doc "Correlates current replies and releases every broker receipt, including stale or invalid traffic.".
-spec handle_cast(term(), #client{}) -> {noreply, #client{}} | {stop, term(), #client{}}.
%% Broker ownership is released even when current evidence is malformed.
handle_cast({'$hls_fabric_frame', Receipt, Route, Header, Payload}, State) ->
    Result = try {noreply, frame(Route, Header, Payload, State)}
        catch error:Reason -> {stop, {invalid_board_frame, Reason}, State} end,
    hls_fabric:ack(State#client.broker, Receipt),
    Result;
%% This client has no application cast path.
handle_cast(_, State) -> {noreply, State}.

%% Drop obsolete request IDs before validating a current response's complete header.
-spec frame(hls_fabric:route(), hls_fabric:header(), binary(), #client{}) -> #client{}.
frame(Route, Header, Payload = <<Request:32/little, _/binary>>,
    State = #client{pending = #{request := Request, route := Route, operation := Operation}}) ->
    Snapshot = observation(Route, Header, Payload),
    ok = matching(Operation, Snapshot),
    Next = finish({ok, Snapshot}, State),
    case Operation of status -> Next#client{uncertain = none}; _ -> Next end;
frame(_, _, _, State) -> State.

%% Inspection response scope is exact even when hardware rejects that request.
-spec matching(operation(), snapshot()) -> ok.
matching({inspect, Session, Incarnation, Actor}, #{kind := inspection, session := Session,
    incarnation := Incarnation, actor := Actor}) -> ok;
matching(status, #{kind := board}) -> ok;
matching({establish, Session}, #{kind := board, status := Status, domain_session := Domain,
    endpoint_session := Endpoint, health := Health}) ->
    case Status of
        ok -> true = Domain =:= Session andalso Endpoint =:= Session,
            true = maps:get(domain_attached, Health) andalso maps:get(endpoint_attached, Health);
        replay -> true = Domain =:= Session andalso Endpoint =:= Session,
            true = maps:get(domain_attached, Health) andalso maps:get(endpoint_attached, Health);
        _ -> ok
    end,
    ok.

-doc "Keeps a missing mutation uncertain and never retries it; broker loss ends this route owner.".
-spec handle_info(term(), #client{}) -> {noreply, #client{}} | {stop, term(), #client{}}.
%% A reply deadline cannot certify that an establish pulse was not applied.
handle_info({deadline, Request}, State = #client{pending = #{request := Request}}) ->
    {noreply, uncertain(State)};
%% The existing broker owns the underlying I/O and cannot be silently replaced here.
handle_info({'DOWN', Ref, process, _, Reason}, State = #client{monitor = Ref}) ->
    {stop, {transport_down, Reason}, uncertain(State)};
%% Physical completion is independent of an already-arrived device response.
handle_info(Message, State = #client{write = Write}) when Write =/= none ->
    case gen_server:check_response(Message, Write) of
        {reply, ok} -> {noreply, State#client{write = none}};
        {reply, {error, {not_sent, Reason}}} ->
            {noreply, finish({error, {not_sent, Reason}}, State#client{write = none})};
        {reply, Failure} -> {stop, {write_failed, Failure}, uncertain(State#client{write = none})};
        {error, Failure} -> {stop, {write_failed, Failure}, uncertain(State#client{write = none})};
        _ -> {noreply, State}
    end;
%% Cancelled deadlines and stale writer messages cannot start new work.
handle_info(_, State) -> {noreply, State}.

%% Return once, retaining a mutation target until a later ordered board status proves current parser state.
-spec uncertain(#client{}) -> #client{}.
uncertain(State = #client{pending = none}) -> State;
uncertain(State = #client{pending = #{operation := {establish, Session}}}) ->
    finish({error, {outcome_unknown, Session}}, State#client{uncertain = Session});
uncertain(State) -> finish({error, noconnection}, State).

%% Caller completion does not abandon an unconfirmed physical write.
-spec finish(reply(), #client{}) -> #client{}.
finish(_Reply, State = #client{pending = none}) -> State;
finish(Reply, State = #client{pending = #{from := From, timer := Timer}}) ->
    erlang:cancel_timer(Timer), gen_server:reply(From, Reply), State#client{pending = none}.

-doc "Returns uncertainty to any outstanding caller; broker/device closure and native state remain deployment-owned.".
-spec terminate(term(), #client{}) -> ok.
terminate(_, State) -> _ = uncertain(State), ok.
