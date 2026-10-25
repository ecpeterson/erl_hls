-module(hls_protocol_relay_queue).
-moduledoc "Bounded packet ownership among a fixed deployment of source-protocol RTL partitions. Each directed logical pair retains one record through forwarding and source acknowledgment. This state machine does not establish transport retirement, reset or application progress.".
-export([new/2, event/3, next/1, complete/2, invalidate/1, info/1]).
-export_type([state/0, packet/0, token/0, report/0]).

%% Wire link indices identify one directed actor pair.
-type link() :: 0 .. ((1 bsl 16) - 1).
%% Each participant binds one nonzero attachment identity.
-type session() :: 1 .. ((1 bsl 64) - 1).
%% The terminal counter value is retained but cannot reserve another event.
-type sequence() :: 0 .. ((1 bsl 32) - 1).
%% Deployment keys need not resemble wire addresses.
-type role() :: hls_protocol_routing:role().

-doc "A source-bound data or zero-payload credit packet; kind and canonical payload are validated against its route.".
-type packet() :: #{kind := 1 | 2, session := session(), sequence := sequence(),
    link := link(), slot := byte(), frame := non_neg_integer()}.
-doc "The reserved physical write whose exact completion advances one logical pair.".
-type token() :: {data | ack, link(), sequence()}.

%% The original source packet survives both writes; only its ownership phase changes.
-record(transfer, {phase :: pending | writing | ack | acking, packet :: packet()}).
%% A selected pending head records its round-robin position and bypass count before reservation.
-record(head, {position :: non_neg_integer(), link :: link(), packet :: packet(), bypassed = 0 :: non_neg_integer()}).
%% Static routes never own runtime credits, sequence counters or a writer reservation.
-record(state, {
    live = true :: boolean(), sessions = #{} :: #{role() => session()},
    routes = #{} :: #{link() => hls_protocol_routing:route()}, events = #{} :: #{role() => sequence()},
    pending = #{} :: #{link() => #transfer{}}, order = [] :: [link()], cursor = 0 :: non_neg_integer(),
    writer = none :: none | token(), credits = #{} :: #{{link(), byte()} => boolean()},
    sequences = #{} :: #{link() => sequence()}, forwarded = 0 :: non_neg_integer(),
    acknowledged = 0 :: non_neg_integer(), bypassed = 0 :: non_neg_integer()
}).

-doc "One relay incarnation's private credit, retained-packet and physical-write ownership. Use queue operations and info/1 rather than inspecting or modifying its representation.".
-opaque state() :: #state{}.
-doc "Payload-free lifecycle, record/credit counts and completed-transfer observations; bypass counts are not a fairness or progress proof.".
-type report() :: #{live := boolean(), events := #{role() => sequence()}, records := non_neg_integer(),
    available_credits := non_neg_integer(), writer := boolean(), forwarded := non_neg_integer(),
    acknowledged := non_neg_integer(), bypassed := non_neg_integer()}.

-doc "Creates a fresh queue from checked routing and distinct nonzero 64-bit sessions, one per role. The routing plan is reusable; credits, retained packets and counters start empty. Old transports must be retired and participating devices reset before replacement.".
-spec new(hls_protocol_routing:plan(), #{role() => session()}) -> state().
new(Plan, Sessions) ->
    Roles = hls_protocol_routing:roles(Plan),
    Routes = hls_protocol_routing:routes(Plan),
    Roles = lists:sort(maps:keys(Sessions)),
    Values = maps:values(Sessions),
    true = length(Values) =:= length(lists:usort(Values)),
    true = lists:all(fun(S) -> is_integer(S) andalso S > 0 andalso S < (1 bsl 64) end, Values),
    #state{sessions = Sessions, routes = Routes, events = maps:from_keys(Roles, 0),
        order = lists:sort(maps:keys(Routes)), sequences = maps:from_keys(maps:keys(Routes), 0),
        credits = maps:from_list([{{I, Slot}, false}
            || {I, #{link := #{classes := Classes}}} <- maps:to_list(Routes), #{slot := Slot} <- Classes])}.

-doc "Accepts a route-bound participant's credit or data packet in exact output-event order. Rejects stale sessions, duplicate/skipped events, unknown routes/classes, noncanonical frames, duplicate grants and a second retained record for a pair. Output events are independent of destination input sequences.".
-spec event(role(), packet(), state()) -> state().
event(Role, Packet = #{session := Session, sequence := Event, link := I},
        State = #state{live = true, sessions = Sessions, events = Events, routes = Routes})
        when Event < 16#ffffffff ->
    Session = maps:get(Role, Sessions),
    Event = maps:get(Role, Events),
    accept(Role, Packet, maps:get(I, Routes), State#state{events = Events#{Role := Event + 1}}).

%% Credits advertise destination capacity; data retains the original source ACK identity.
-spec accept(role(), packet(), hls_protocol_routing:route(), state()) -> state().
accept(Role, #{kind := 2, link := I, slot := Slot, frame := 0}, #{to := Role},
        State = #state{credits = Credits}) ->
    false = maps:get({I, Slot}, Credits),
    State#state{credits = Credits#{{I, Slot} := true}};
accept(Role, Packet = #{kind := 1, link := I, slot := Slot, frame := Frame},
        Route = #{from := Role}, State = #state{pending = Pending}) ->
    false = maps:is_key(I, Pending),
    ok = canonical(Route, Slot, Frame),
    State#state{pending = Pending#{I => #transfer{phase = pending, packet = Packet}}}.

-doc "Reserves at most one physical write. ACKs take priority; otherwise round-robin selection may bypass an uncredited different pair, never a pair's head. Destination credit and its input sequence are consumed before returning a write. No rollback or replay is permitted after reservation.".
-spec next(state()) -> none | {role(), packet(), token(), state()}.
next(#state{live = true, writer = Writer}) when Writer =/= none -> none;
next(State = #state{live = true, pending = Pending}) ->
    case acknowledgments(Pending) of
        [{I, Packet} | _] -> reserve_ack(I, Packet, State);
        [] ->
            case pending_head(State) of
                none -> none;
                Head -> reserve_data(Head, State)
            end
    end.

%% Completed destination writes compete for ACK ownership in deterministic link order.
-spec acknowledgments(#{link() => #transfer{}}) -> [{link(), packet()}].
acknowledgments(Pending) ->
    [{I, Packet} || {I, #transfer{phase = ack, packet = Packet}} <- lists:sort(maps:to_list(Pending))].

%% Reserve the source acknowledgment without releasing the pair until physical completion.
-spec reserve_ack(link(), packet(), state()) -> {role(), packet(), token(), state()}.
reserve_ack(I, Packet = #{sequence := Sequence}, State = #state{routes = Routes, pending = Pending}) ->
    #{from := From} = maps:get(I, Routes),
    Token = {ack, I, Sequence},
    Next = State#state{writer = Token, pending = Pending#{I := #transfer{phase = acking, packet = Packet}}},
    {From, Packet#{kind := 2, frame := 0}, Token, Next}.

%% Scan each pair once from the cursor; only blocked pending heads count as bypasses.
-spec pending_head(state()) -> none | #head{}.
pending_head(State = #state{order = Order, cursor = Cursor}) ->
    {Before, After} = lists:split(Cursor, Order),
    credited_head(After ++ Before, Cursor, 0, State).

%% Selection is read-only: skipped pairs retain their head, credit and sequence.
-spec credited_head([link()], non_neg_integer(), non_neg_integer(), state()) -> none | #head{}.
credited_head([], _, _, _) -> none;
credited_head([I | Rest], Position, Bypassed,
        State = #state{pending = Pending, credits = Credits, order = Order}) ->
    NextPosition = (Position + 1) rem length(Order),
    case maps:find(I, Pending) of
        {ok, #transfer{phase = pending, packet = Packet = #{slot := Slot}}} ->
            case maps:get({I, Slot}, Credits) of
                true -> #head{position = Position, link = I, packet = Packet, bypassed = Bypassed};
                false -> credited_head(Rest, NextPosition, Bypassed + 1, State)
            end;
        _ -> credited_head(Rest, NextPosition, Bypassed, State)
    end.

%% Consume destination ownership once, retaining the source packet for its eventual ACK.
-spec reserve_data(#head{}, state()) -> {role(), packet(), token(), state()}.
reserve_data(#head{position = Position, link = I, packet = Original = #{slot := Slot}, bypassed = Skipped},
        State = #state{routes = Routes, sessions = Sessions, sequences = Sequences,
            pending = Pending, credits = Credits, order = Order, bypassed = Bypassed}) ->
    #{to := To} = maps:get(I, Routes),
    Sequence = maps:get(I, Sequences),
    true = Sequence < 16#ffffffff,
    Packet = Original#{session := maps:get(To, Sessions), sequence := Sequence},
    Token = {data, I, Sequence},
    Next = State#state{writer = Token, cursor = (Position + 1) rem length(Order),
        pending = Pending#{I := #transfer{phase = writing, packet = Original}},
        sequences = Sequences#{I := Sequence + 1}, credits = Credits#{{I, Slot} := false},
        bypassed = Bypassed + Skipped},
    {To, Packet, Token, Next}.

-doc "Commits the sole reserved write after complete physical transmission. Data completion makes the original source ACK eligible; ACK completion releases the pair. Failed or ambiguous transmission requires invalidation and transport retirement, never completion or retry.".
-spec complete(token(), state()) -> state().
%% Destination completion permits an ACK while retaining original source identity.
complete(Token = {data, I, _}, State = #state{live = true, writer = Token, pending = Pending, forwarded = Count}) ->
    #transfer{phase = writing, packet = Packet} = maps:get(I, Pending),
    State#state{writer = none, pending = Pending#{I := #transfer{phase = ack, packet = Packet}}, forwarded = Count + 1};
%% Source ACK completion alone releases the retained logical pair.
complete(Token = {ack, I, _}, State = #state{live = true, writer = Token, pending = Pending, acknowledged = Count}) ->
    #transfer{phase = acking} = maps:get(I, Pending),
    State#state{writer = none, pending = maps:remove(I, Pending), acknowledged = Count + 1}.

-doc "Cancels all routes, credits and retained records permanently. This does not cancel a physical write or prove transport retirement; the owner must retire every connection and coordinate reset before replacement.".
-spec invalidate(state()) -> state().
invalidate(State) -> State#state{live = false, routes = #{}, credits = #{}, pending = #{}, writer = none}.

-doc "Reports bounded records, available credits and completed transfers without exposing payloads or mutable queue state.".
-spec info(state()) -> report().
info(#state{live = Live, pending = Pending, credits = Credits, writer = Writer, events = Events,
        forwarded = Forwarded, acknowledged = Acknowledged, bypassed = Bypassed}) ->
    #{live => Live, events => Events, records => map_size(Pending),
        available_credits => length([ok || true <- maps:values(Credits)]), writer => Writer =/= none,
        forwarded => Forwarded, acknowledged => Acknowledged, bypassed => Bypassed}.

%% Destination codec validation does not decode or rewrite the application record.
-spec canonical(hls_protocol_routing:route(), byte(), non_neg_integer()) -> ok.
canonical(#{link := #{classes := Classes}}, Slot, Frame) ->
    [#{codec := Codec}] = [Class || Class = #{slot := S} <- Classes, S =:= Slot],
    {ok, _} = hls_protocol_codec:encode(Codec, Frame),
    ok.
