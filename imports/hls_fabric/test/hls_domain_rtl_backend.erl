-module(hls_domain_rtl_backend).
-moduledoc "Local RTL witness backend. Lifecycle state is decoded from the compiled hardware kernel; this adapter supplies no lifecycle algorithm or application replay.".
-behaviour(gen_server).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% The same deployment-owner backend contract as hls_domain_erts.
-export([start_link/2, attach/2, status/1, request/3, endpoint/4, stop/1]).
%% Explicit test-only transport controls and bounded observations.
-export([control/3, info/1, drop_next_request_reply/1, delivery/2, write_codes/2]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-doc "Attaches two already-created independent FIFO pairs using the emitted interface's retained codecs; does not reset hardware or read compiler source.".
-spec start_link(file:filename(), file:filename()) -> gen_server:start_ret().
start_link(Prefix, Interface) -> gen_server:start_link(?MODULE, {Prefix, Interface}, []).
-doc "Claims one native local owner without resetting an existing hardware incarnation.".
-spec attach(pid(), pid()) -> {ok, reference()} | {error, term()}.
attach(Pid, Owner) -> gen_server:call(Pid, {attach, Owner}).
-doc "Requests a fresh hardware snapshot, including currently published local actor endpoints.".
-spec status(pid()) -> {ok, map()} | {error, term()}.
status(Pid) -> gen_server:call(Pid, status).
-doc "Submits an authorized finite management input, awaiting its matching hardware response.".
-spec request(pid(), reference(), hls_domain_lifecycle:input()) -> hls_domain_lifecycle:output() | {error, term()}.
request(Pid, Authority, Input) -> gen_server:call(Pid, {request, Authority, Input}).
-doc "Resolves only the counter's ready incarnation-specific local proxy.".
-spec endpoint(pid(), reference(), pos_integer(), term()) -> {ok, pid()} | {error, term()}.
endpoint(Pid, Authority, Incarnation, Actor) -> gen_server:call(Pid, {endpoint, Authority, Incarnation, Actor}).
-doc "Closes fixture brokers and retires proxies; it never replays or implicitly resets the device.".
-spec stop(pid()) -> ok.
stop(Pid) -> gen_server:stop(Pid).
-doc "Sends one explicit driver-only control frame on the application stream.".
-spec control(pid(), byte(), [non_neg_integer()]) -> ok | {error, term()}.
control(Pid, Tag, Words) -> gen_server:call(Pid, {control, Tag, Words}).
-doc "Returns bounded request metadata and transport leases for the finite witness.".
-spec info(pid()) -> map().
info(Pid) -> gen_server:call(Pid, info).
-doc "Withholds the next actual management command result from its owner; the command is still executed exactly once.".
-spec drop_next_request_reply(pid()) -> ok.
drop_next_request_reply(Pid) -> gen_server:call(Pid, drop_next_request_reply).
-doc "Controls fixture transport delivery independently of hardware acceptance; missing_frontier injects a malformed management response.".
-spec delivery(pid(), hold | resume | missing_frontier) -> ok.
delivery(Pid, Mode) -> gen_server:call(Pid, {delivery, Mode}).

-doc "Writes the fixture driver's numeric constants from the same retained codecs used by host transport; no lifecycle encoding is maintained in C++.".
-spec write_codes(file:filename(), file:filename()) -> ok.
write_codes(Interface, Header) ->
    Codecs = codecs(Interface),
    Constants = [
        ["static constexpr uint32_t ", string:uppercase(atom_to_list(Kind) ++ "_" ++ atom_to_list(Member)),
            " = ", integer_to_list(encode(Kind, Member, Codecs)), ";\n"]
     || {Kind, {hls_type, hls_enum, enum, [Members]}} <- lists:sort(maps:to_list(Codecs)),
        Member <- Members
    ],
    ok = file:write_file(Header, ["// Generated from the emitted lifecycle interface.\n#pragma once\n#include <cstdint>\n", Constants], [exclusive]).

-doc "Opens independent management/application brokers and starts finite-rate fault observation.".
-spec init({file:filename(), file:filename()}) -> {ok, map()}.
init({Prefix, Interface}) ->
    Codecs = codecs(Interface),
    process_flag(trap_exit, true),
    {ok, Management} = hls_fabric:start_link(Prefix ++ "_management_tx", Prefix ++ "_management_rx", #{rx_route_limit => 1}),
    {ok, Application} = hls_fabric:start_link(Prefix ++ "_application_tx", Prefix ++ "_application_rx", #{rx_route_limit => 1}),
    ok = hls_fabric:register_route(Management, {0, 0}, self()),
    ok = hls_fabric:register_route(Application, {0, 0}, self()),
    erlang:send_after(10, self(), poll),
    {ok, #{management => Management, application => Application, codecs => Codecs,
        owner => undefined, owner_monitor => undefined, authority => undefined, actor_monitor => undefined,
        state => #domain_state{}, actors => #{}, actor_incarnation => 0, fault_reason => none,
        management_queue => queue:new(), management_pending => none, sequence => 1,
        sends => gen_server:reqids_new(), app_next => 1, pending => #{},
        ignored => 0, rejected => 0, wire_rejected => 0, drop => false, retiring_owner => false, retirement_attempts => 0,
        controls => [], ready_incarnations => 0, last_ready => 0,
        delivery_received => 0, delivery_frontier => 0, retirement => none}}.

-doc "Handles the owner contract and explicit fixture transport controls.".
-spec handle_call(term(), gen_server:from(), map()) -> term().
%% Attachment is exclusive, and owner loss must first close the old device admission.
handle_call({attach, Owner}, {Owner, _}, State = #{owner := Owner, authority := Ref}) -> {reply, {ok, Ref}, State};
%% A new local authority may attach only after retirement is observed, never from a guessed timeout.
handle_call({attach, Owner}, {Owner, _}, State = #{owner := undefined, retiring_owner := false}) when node(Owner) =:= node() ->
    Ref = make_ref(),
    {reply, {ok, Ref}, State#{owner := Owner, authority := Ref, owner_monitor := monitor(process, Owner)}};
%% Concurrent owners and unfinished retirement remain unavailable.
handle_call({attach, _}, _From, State) -> {reply, {error, owned_or_retiring}, State};
%% Status is obtained through the independent management stream, even while an application frame is partial.
handle_call(status, From, State) -> {noreply, management(status, none, From, State)};
%% Only the exact attached process and capability may request a transition.
handle_call({request, Ref, Input}, {Owner, _} = From, State = #{owner := Owner, authority := Ref, retiring_owner := false}) when is_reference(Ref) ->
    {noreply, management(request, Input, From, State)};
%% Ready endpoint lookup never rebinds an old incarnation.
handle_call({endpoint, Ref, Incarnation, counter}, {Owner, _}, State = #{owner := Owner, authority := Ref,
    state := #domain_state{phase = ready, current = Incarnation}, actors := #{counter := Pid},
    actor_incarnation := Incarnation, retirement := none}) when is_reference(Ref) ->
    {reply, {ok, Pid}, State};
%% An old incarnation or a non-ready domain cannot be resolved through its stable name.
handle_call({endpoint, _, _, _}, _From, State) -> {reply, {error, not_ready_or_stale}, State};
%% Observations retain no work history, only current outstanding ownership and aggregate counts.
handle_call(info, _From, State) ->
    {reply, maps:with([pending, state, ignored, rejected, wire_rejected, controls, actors, management, application,
        ready_incarnations, delivery_received, delivery_frontier, retirement], State), State};
%% A lost reply is injected after real execution, leaving the durable owner to reconcile the transition.
handle_call(drop_next_request_reply, _From, State) -> {reply, ok, State#{drop := true}};
%% Management remains usable while accepted application output waits in its independent lane.
handle_call({delivery, Mode}, From, State) ->
    Value = case Mode of hold -> 0; resume -> 1; missing_frontier -> 2 end,
    {noreply, management({delivery, Value}, none, From, State)};
%% Driver controls are test instrumentation, never management or application recovery policy.
handle_call({control, Tag, Words}, _From, State = #{application := Broker}) ->
    Result = hls_fabric:send(Broker, {0, 0}, {Tag, 0, 0}, words(Words)),
    {reply, Result, State};
%% Unknown authority or requests do not mutate the controller.
handle_call(_Request, _From, State) -> {reply, {error, unauthorized}, State}.

-doc "Routes actual broker frames and incarnation-specific application requests.".
-spec handle_cast(term(), map()) -> {noreply, map()}.
%% Management responses carry their own non-reused sequence; application acknowledgements carry incarnation plus request ID.
handle_cast({'$hls_fabric_frame', Receipt, {0, 0}, {Tag, _Tx, 0}, Payload}, State) ->
    Broker = maps:get(case Tag of 1 -> management; _ -> application end, State),
    Next = response(Tag, payload(Payload), State),
    hls_fabric:ack(Broker, Receipt),
    {noreply, pump(Next)};
%% Only current published proxies may ask the fixture driver to admit source work.
handle_cast({application, Endpoint, Ref, Incarnation, Mode, Request}, State) ->
    {noreply, application(Endpoint, Ref, Incarnation, Mode, Request, State)}.

-doc "Observes source faults, correlates transport writes, and fences on local owner death.".
-spec handle_info(term(), map()) -> term().
%% Poll only when idle so management queue size stays bounded independently of traffic duration.
handle_info(poll, State = #{management_pending := Pending, management_queue := Queue}) ->
    erlang:send_after(10, self(), poll),
    Next = case Pending =:= none andalso queue:is_empty(Queue) of true -> management(status, none, none, State); false -> State end,
    {noreply, Next};
%% Native local monitor is this test backend's declared disconnect indication; no physical watchdog timing is claimed.
handle_info({'DOWN', Ref, process, _Owner, _Reason}, State = #{owner_monitor := Ref}) ->
    Closed = retire(noconnection, State#{owner := undefined, owner_monitor := undefined, authority := undefined}),
    {noreply, begin_retirement(Closed)};
%% An unexpected host proxy death cannot leave an apparently ready hardware binding behind.
handle_info({'DOWN', Ref, process, _Endpoint, Reason}, State = #{actor_monitor := Ref}) ->
    Closed = retire({endpoint_down, Reason}, State#{actor_monitor := undefined}),
    {noreply, begin_retirement(Closed)};
%% A timed-out command remains uncertain; a fresh snapshot may reconcile it without reusing the sequence.
handle_info({management_timeout, Sequence}, State = #{management_pending := #{sequence := Sequence, from := From, kind := Kind}}) ->
    reply(From, {error, management_timeout}),
    Cleared = State#{management_pending := none},
    Next = case Kind of
        retire_status -> management(retire_status, none, none, Cleared);
        retire_command -> management(retire_status, none, none, Cleared);
        _ -> pump(Cleared)
    end,
    {noreply, Next};
%% Missing accepted output leaves transport outcome unknown; never fabricate orderly source death.
handle_info({delivery_timeout, Token}, State = #{retirement := #{token := Token}}) ->
    {stop, delivery_frontier_timeout, retire(noconnection, State)};
%% Broker loss closes the endpoint; continuing from cached readiness would be false evidence.
handle_info({'EXIT', Broker, Reason}, State = #{management := Management, application := Application}) when Broker =:= Management; Broker =:= Application ->
    {stop, {transport_down, Reason}, retire(noconnection, State)};
%% Asynchronous physical writes have their own ownership; no failed write is automatically retried.
handle_info(Message, State = #{sends := Sends}) ->
    case gen_server:check_response(Message, Sends, true) of
        {{reply, ok}, _Label, Rest} -> {noreply, State#{sends := Rest}};
        {{reply, Failure}, _Label, Rest} -> {stop, {write_failed, Failure}, retire(noconnection, State#{sends := Rest})};
        {{error, Reason}, _Label, Rest} -> {stop, {write_failed, Reason}, retire(noconnection, State#{sends := Rest})};
        _ -> {noreply, State}
    end.

-doc "Releases endpoint monitors and brokers; raw FIFO descriptor closure is checked by the outer witness.".
-spec terminate(term(), map()) -> ok.
terminate(_Reason, State) ->
    _ = retire(noconnection, State),
    catch hls_fabric:stop(maps:get(management, State)),
    catch hls_fabric:stop(maps:get(application, State)),
    ok.

%% The immutable interface carries self-contained provider descriptors, not source dependencies.
-spec codecs(file:filename()) -> #{atom() => hls_type:descriptor()}.
codecs(Interface) ->
    {ok, Bytes} = file:read_file(Interface),
    #{codecs := Codecs} = binary_to_term(Bytes),
    Codecs.

%% Atom-to-wire translation follows the ordinary type provider, including its declared width.
-spec encode(atom(), atom(), #{atom() => hls_type:descriptor()}) -> non_neg_integer().
encode(Kind, Value, Codecs) ->
    Descriptor = maps:get(Kind, Codecs),
    Width = hls_type:width(Descriptor),
    <<Code:Width>> = hls_type:pack(Value, Descriptor),
    Code.

%% Reject both unused codes and oversized transport words rather than silently truncating either.
-spec decode(atom(), non_neg_integer(), #{atom() => hls_type:descriptor()}) -> atom().
decode(Kind, Code, Codecs) ->
    Descriptor = maps:get(Kind, Codecs),
    Width = hls_type:width(Descriptor),
    true = Code < (1 bsl Width),
    {Value, <<>>} = hls_type:unpack(<<Code:Width>>, Descriptor),
    Value.

%% Serialize management without coupling it to application packet assembly or output credits.
-spec management(status | request | retire_status | retire_command | {delivery, 0..2}, none | hls_domain_lifecycle:input(), gen_server:from() | none, map()) -> map().
management(Kind, Input, From, State = #{management_queue := Queue}) ->
    true = queue:len(Queue) < 8,
    pump(State#{management_queue := queue:in(#{kind => Kind, input => Input, from => From}, Queue)}).

%% Every command carries a nonwrapping fixture correlation ID in addition to the shared kernel transition identity.
-spec pump(map()) -> map().
pump(State = #{management_pending := none, management_queue := Queue, sequence := Sequence,
    management := Broker, codecs := Codecs}) ->
    case queue:out(Queue) of
        {empty, _} -> State;
        {{value, Entry = #{kind := Kind, input := Input}}, Rest} ->
            true = Sequence < (1 bsl 32),
            {Tag, Payload} = case {Kind, Input} of
                {{delivery, Mode}, none} -> {7, [Sequence, Mode]};
                {StatusKind, none} when StatusKind =:= status; StatusKind =:= retire_status -> {0, [Sequence]};
                {CommandKind, #domain_input{op = Op, expected = Expected, target = Target, transition = Transition, fault = Fault}} when CommandKind =:= request; CommandKind =:= retire_command ->
                    {1, [Sequence, encode(operation, Op, Codecs)] ++ split(Expected) ++ split(Target) ++
                        split(Transition) ++ [encode(fault, Fault, Codecs)]}
            end,
            Attempts = maps:get(retirement_attempts, State) + case Kind of retire_status -> 1; _ -> 0 end,
            true = Attempts =< 8,
            Timer = erlang:send_after(1000, self(), {management_timeout, Sequence}),
            transmit(Broker, Tag, words(Payload), State#{management_queue := Rest, retirement_attempts := Attempts,
                sequence := Sequence + 1, management_pending := Entry#{sequence => Sequence, timer => Timer}})
    end;
pump(State) -> State.

%% Decoded state is authoritative only when it belongs to the exact outstanding management exchange.
-spec response(byte(), [non_neg_integer()], map()) -> map().
response(1, [Sequence, StatusBits, ActionBits, PhaseBits, CL, CH, PL, PH, TL, TH, IL, IH, FaultBits, SourceFault, SourceActor, Frontier],
    State = #{management_pending := #{sequence := Sequence, timer := Timer, kind := Kind, from := From},
        drop := Drop, delivery_frontier := KnownFrontier, codecs := Codecs}) ->
    true = Frontier >= KnownFrontier,
    Status = decode(status, StatusBits, Codecs),
    Action = decode(action, ActionBits, Codecs),
    Phase = decode(phase, PhaseBits, Codecs),
    Fault = decode(fault, FaultBits, Codecs),
    erlang:cancel_timer(Timer),
    Current = #domain_state{phase = Phase, current = join(CL, CH), previous = join(PL, PH),
        target = join(TL, TH), transition = join(IL, IH), fault = Fault},
    Next = observe(Current, SourceFault, SourceActor, Frontier, State#{management_pending := none,
        delivery_frontier := Frontier}),
    Result = case Kind of
        status -> status_result(Next);
        {delivery, _} -> ok;
        _ -> #domain_output{status = Status, action = Action, admit = Phase =:= ready, state = Current}
    end,
    Replied = case Drop andalso Kind =:= request andalso From =/= none of
        true -> reply(From, {error, simulated_lost_reply}), Next#{drop := false};
        false -> reply(From, Result), Next
    end,
    retirement_response(Kind, Replied);
response(1, [Sequence | _] = Words, #{management_pending := #{sequence := Sequence}}) ->
    error({invalid_delivery_frontier, Words});
response(Tag, [Sequence | Words], State = #{delivery_received := Received}) when Tag >= 2, Tag =< 4 ->
    case Sequence =:= Received + 1 of
        true -> reconcile(app_frame(Tag, Words, State#{delivery_received := Sequence}));
        false -> error({invalid_application_sequence, Received, Sequence})
    end;
response(_Tag, _Words, State) -> ignored(State).

%% Application response sequences order all acknowledgements/reports before a management frontier.
-spec app_frame(byte(), [non_neg_integer()], map()) -> map().
app_frame(2, [Lo, Hi, Id, Rejected], State = #{wire_rejected := N}) ->
    Count = case Rejected of 0 -> N; _ -> N + 1 end,
    app_response(ack, join(Lo, Hi), Id, Rejected, State#{wire_rejected := Count});
app_frame(3, [Lo, Hi, Id, Value], State) -> app_response(report, join(Lo, Hi), Id, Value, State);
app_frame(4, [Held], State = #{controls := Controls}) -> State#{controls := [Held | lists:sublist(Controls, 7)]};
app_frame(Tag, Words, _State) -> error({invalid_application_response, Tag, Words}).

%% Only readiness may create endpoint identities; every other phase retires the prior local proxies.
-spec observe(hls_domain_lifecycle:state(), non_neg_integer(), non_neg_integer(), non_neg_integer(), map()) -> map().
observe(Current = #domain_state{phase = ready, current = Incarnation}, _Source, _Actor, _Frontier,
    State = #{owner := Owner, actor_incarnation := Incarnation, actors := Actors, retirement := none}) when is_pid(Owner), map_size(Actors) > 0 ->
    State#{state := Current};
observe(Current, Source, Actor, Frontier, State = #{actors := Actors, retirement := Retirement}) ->
    Reason = case Source of 0 -> {domain_retired, Current#domain_state.fault}; _ -> {hls_actor_failure, Actor, #{source_code => Source, source_site => Source bsr 4, kind => Source band 15}} end,
    Next = case map_size(Actors) > 0 andalso Retirement =:= none of
        true ->
            Token = make_ref(), Timer = erlang:send_after(1000, self(), {delivery_timeout, Token}),
            State#{retirement := #{reason => Reason, frontier => Frontier, token => Token, timer => Timer}};
        false -> State
    end,
    reconcile(Next#{state := Current, fault_reason := Reason}).

%% Readiness publication waits for old accepted output delivery and actual old endpoint termination.
-spec reconcile(map()) -> map().
reconcile(State = #{retirement := #{frontier := Frontier, reason := Reason}, delivery_received := Received}) when Received >= Frontier ->
    reconcile(retire(Reason, State));
reconcile(State = #{retirement := Retirement}) when Retirement =/= none -> State;
reconcile(State = #{state := #domain_state{phase = ready, current = Incarnation}, actors := Actors,
    owner := Owner, retiring_owner := false, ready_incarnations := Resets, last_ready := Last}) when is_pid(Owner), map_size(Actors) =:= 0 ->
    {ok, Endpoint} = hls_domain_rtl_endpoint:start(self(), Incarnation),
    State#{actors := #{counter => Endpoint}, actor_incarnation := Incarnation,
        actor_monitor := monitor(process, Endpoint),
        last_ready := Incarnation, ready_incarnations := Resets + case Last =:= Incarnation of true -> 0; false -> 1 end,
        fault_reason := none};
reconcile(State) -> State.

%% Failure observations remain available while delivery drains; new readiness cannot expose an old PID.
-spec status_result(map()) -> {ok, map()} | {error, atom()}.
status_result(#{retiring_owner := true}) -> {error, retirement_pending};
status_result(#{state := #domain_state{phase = ready}, retirement := Retirement}) when Retirement =/= none ->
    {error, delivery_pending};
status_result(State) -> {ok, snapshot(State)}.

%% Application ownership is checked before submission and again on every return frame.
-spec application(pid(), reference(), pos_integer(), call | cast, term(), map()) -> map().
application(Endpoint, Ref, Incarnation, Mode, Request, State = #{actors := Actors, pending := Pending,
    app_next := Id, state := #domain_state{phase = Phase, current = Current}, application := Broker}) ->
    case Phase =:= ready andalso Incarnation =:= Current andalso maps:get(counter, Actors, none) =:= Endpoint of
        false -> Endpoint ! {rtl_result, Ref, {error, not_ready_or_stale}}, State;
        true when map_size(Pending) >= 8 -> Endpoint ! {rtl_result, Ref, {error, busy}}, State;
        true ->
            true = Id < (1 bsl 32),
            {Tag, Value} = case Request of {add, V} -> {3, V}; read -> {4, 0}; explode -> {5, 0} end,
            Entry = #{endpoint => Endpoint, reference => Ref, incarnation => Incarnation, mode => Mode, admitted => false},
            transmit(Broker, 2, words(split(Incarnation) ++ [Tag, Id, Value]), State#{app_next := Id + 1, pending := Pending#{Id => Entry}})
    end.

%% A stale admission acknowledgement or report cannot acknowledge/remove a new incarnation's request, even with a matching request ID.
-spec app_response(ack | report, non_neg_integer(), non_neg_integer(), non_neg_integer(), map()) -> map().
app_response(Kind, Incarnation, Id, Value, State = #{pending := Pending, actor_incarnation := Incarnation}) ->
    case maps:find(Id, Pending) of
        {ok, Entry = #{incarnation := Incarnation, endpoint := Endpoint, reference := Ref, mode := Mode}} ->
            case {Kind, Value, Mode} of
                {ack, Rejected, _} when Rejected =/= 0 ->
                    Endpoint ! {rtl_result, Ref, {error, rejected_incarnation}},
                    State#{pending := maps:remove(Id, Pending), rejected := maps:get(rejected, State) + 1};
                {ack, 0, cast} -> Endpoint ! {rtl_result, Ref, ok}, State#{pending := maps:remove(Id, Pending)};
                {ack, 0, call} -> State#{pending := Pending#{Id := Entry#{admitted := true}}};
                {report, _, call} -> Endpoint ! {rtl_result, Ref, {value, Value}}, State#{pending := maps:remove(Id, Pending)};
                _ -> ignored(State)
            end;
        error -> ignored(State)
    end;
app_response(_Kind, _Incarnation, _Id, _Value, State) -> ignored(State).

%% Retirement waits for actual proxy death before later readiness can publish a new endpoint.
-spec retire(term(), map()) -> map().
retire(Reason, State = #{actors := Actors, actor_monitor := Monitor, retirement := Retirement}) ->
    case Retirement of none -> ok; #{timer := Timer} -> erlang:cancel_timer(Timer) end,
    case Monitor of undefined -> ok; _ -> demonitor(Monitor, [flush]) end,
    maps:foreach(fun(_Id, Pid) ->
        Ref = monitor(process, Pid), Pid ! {rtl_retire, self(), Reason},
        receive {'DOWN', Ref, process, Pid, _} -> ok after 1000 -> error(proxy_retirement_timeout) end
    end, Actors),
    State#{actors := #{}, actor_incarnation := 0, actor_monitor := undefined, pending := #{}, retirement := none}.

%% Physical write completion is distinct from the hardware's application acknowledgement.
-spec transmit(pid(), byte(), binary(), map()) -> map().
transmit(Broker, Tag, Payload, State = #{sends := Sends}) ->
    true = gen_server:reqids_size(Sends) < 16,
    Id = hls_fabric:send_request(Broker, {0, 0}, {Tag, 0, 0}, Payload, 1000),
    State#{sends := gen_server:reqids_add(Id, Tag, Sends)}.

%% The deployment owner consumes the shared state record without a second transition implementation.
-spec snapshot(map()) -> map().
snapshot(State = #{state := #domain_state{phase = ready}, retirement := none}) ->
    maps:with([state, actors, fault_reason, ready_incarnations], State);
snapshot(State) -> (maps:with([state, fault_reason, ready_incarnations], State))#{actors => #{}}.
%% Polling observations have no caller reply handle.
-spec reply(gen_server:from() | none, term()) -> ok.
reply(none, _) -> ok;
reply(From, Result) -> gen_server:reply(From, Result).
%% Count stale/malformed traffic without retaining its unbounded contents.
-spec ignored(map()) -> map().
ignored(State = #{ignored := N}) -> State#{ignored := N + 1}.
%% Management and source fields use explicit little-endian 32-bit words.
-spec words([non_neg_integer()]) -> binary().
words(Words) -> << <<W:32/little>> || W <- Words >>.
%% Incoming frame payload is already length-checked by the shared broker.
-spec payload(binary()) -> [non_neg_integer()].
payload(Binary) -> [W || <<W:32/little>> <= Binary].
%% Split and join fixed incarnation/transition identities without truncation.
-spec split(non_neg_integer()) -> [non_neg_integer()].
split(Value) -> [Value band 16#ffffffff, Value bsr 32].
%% Decode the high half without narrowing an incarnation or transition.
-spec join(non_neg_integer(), non_neg_integer()) -> non_neg_integer().
join(Lo, Hi) -> Lo bor (Hi bsl 32).

%% Cancel unsent old-owner management work, then reconcile any already transmitted command from hardware.
-spec begin_retirement(map()) -> map().
begin_retirement(State = #{management_queue := Queue}) ->
    [reply(maps:get(from, Entry), {error, retirement_pending}) || Entry <- queue:to_list(Queue)],
    management(retire_status, none, none, State#{management_queue := queue:new(),
        retiring_owner := true, retirement_attempts := 0}).

%% An in-flight transition may have advanced since the owner's death; close the freshly observed identity.
-spec retirement_response(atom() | {delivery, 0..2}, map()) -> map().
retirement_response(Kind, State = #{retiring_owner := true, state := #domain_state{phase = Phase}})
    when (Kind =:= retire_status orelse Kind =:= retire_command) andalso
        (Phase =:= failed orelse Phase =:= unbound) ->
    State#{retiring_owner := false};
retirement_response(retire_status, State = #{retiring_owner := true, state := Current}) ->
    Input = case Current#domain_state.phase of
        Phase when Phase =:= closing; Phase =:= isolated; Phase =:= initializing ->
            #domain_input{op = abort, expected = Current#domain_state.previous,
                target = Current#domain_state.target, transition = Current#domain_state.transition, fault = owner_down};
        _ -> #domain_input{op = fault, expected = Current#domain_state.current, fault = owner_down}
    end,
    management(retire_command, Input, none, State);
%% A stale abort is harmless; read again instead of claiming that the old observation fenced the device.
retirement_response(retire_command, State = #{retiring_owner := true}) ->
    management(retire_status, none, none, State);
retirement_response(_Kind, State) -> State.
