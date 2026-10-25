-module(hls_protocol_mixed_queue).
-moduledoc "Bounded sender-aware host admission for a source-protocol partition. One transport owner holds queues, slot credits and event sequences; actors do not create forwarding processes.".
-export([new/4, offer/4, next/1, credit/5, delivery/6, invalidate/1, info/1]).
-export_type([state/0, attachment/0, packet/0, report/0]).

%% Logical actor identity is independent of a local PID or packet link index.
-type actor() :: non_neg_integer().
%% Link indices identify per-sender/destination queues and hardware credit slots.
-type link() :: non_neg_integer().
%% A session is fixed for one reset-owned attachment; event counters never wrap.
-type session() :: 1 .. ((1 bsl 64) - 1).
%% The terminal counter value is retained but cannot reserve another event.
-type sequence() :: 0 .. ((1 bsl 32) - 1).
%% Queue operations need checked actor routing and the corresponding source/destination codec.
-type route() :: hls_protocol_mixed:link() |
    #{index := link(), source_index := actor(), destination_index := actor(), direction := to_rtl,
      source_module := module(), destination_module => module(), classes := [hls_protocol_mixed:codec_class()]} |
    #{index := link(), source_index := actor(), destination_index := actor(), direction := to_beam,
      source_module => module(), destination_module := module(), classes := [hls_protocol_mixed:codec_class()]}.

-doc "The emitted host attachment view: exact host actors, checked crossing codecs and native build identity. Session ownership and PID binding are established by new/4.".
-type attachment() :: #{host_actors := [actor()], links := [route()], identity := binary()}.
-doc "One data reservation without its transport kind; the stream owner adds kind=1 when framing it.".
-type packet() :: #{session := session(), sequence := sequence(), link := link(),
    slot := byte(), frame := non_neg_integer()}.

%% Only one head per logical pair competes; selection does not remove or acknowledge it.
-record(head, {position :: non_neg_integer(), link :: link(), slot :: byte(), frame :: non_neg_integer()}).
%% Runtime ownership is private, including PID authentication and credits already consumed by writes.
-record(state, {
    live = true :: boolean(), session :: session(), identity :: binary(),
    pids = #{} :: #{actor() => pid()}, senders = #{} :: #{pid() => actor()},
    links = #{} :: #{link() => route()}, order = [] :: [link()], cursor = 0 :: non_neg_integer(),
    limit :: pos_integer(), queued = 0 :: non_neg_integer(), next_event = 0 :: sequence(),
    queues = #{} :: #{link() => queue:queue({byte(), non_neg_integer()})},
    sequence = #{} :: #{link() => sequence()}, credits = #{} :: #{{link(), byte()} => boolean()}
}).

-doc "One host attachment's private PID, queue, sequence and credit ownership. Retain only the newest returned value and inspect through info/1.".
-opaque state() :: #state{}.
-doc "Payload-free lifecycle and bounded admission counts; sent records may remain in native captures until final release.".
-type report() :: #{live := boolean(), queued := non_neg_integer(), limit := pos_integer(),
    available_credits := non_neg_integer(), next_event := sequence()}.

-doc "Creates an uncredited incarnation with exact local PID bindings for every host actor. Caller owns a freshly reset attachment, authenticates senders and monitors actors/transport. Replacement after rebinding or an ambiguous write requires invalidation, transport retirement and coordinated reset. Limit bounds queued records; native credits separately bound sent records.".
-spec new(attachment(), #{actor() => pid()}, session(), pos_integer()) -> state().
new(#{host_actors := Host, links := Links, identity := Identity}, Pids, Session, Limit)
        when Session > 0, Session < (1 bsl 64), Limit > 0 ->
    true = lists:sort(Host) =:= lists:sort(maps:keys(Pids)),
    true = lists:all(fun(Pid) -> is_pid(Pid) andalso node(Pid) =:= node() end, maps:values(Pids)),
    true = map_size(Pids) =:= length(lists:usort(maps:values(Pids))),
    ToRtl = [Link || Link = #{direction := to_rtl} <- Links],
    #state{session = Session, identity = Identity, pids = Pids, limit = Limit,
        senders = maps:from_list([{Pid, I} || {I, Pid} <- maps:to_list(Pids)]),
        links = maps:from_list([{I, Link} || Link = #{index := I} <- Links]),
        order = [I || #{index := I} <- ToRtl],
        queues = maps:from_list([{I, queue:new()} || #{index := I} <- ToRtl]),
        sequence = maps:from_list([{I, 0} || #{index := I} <- ToRtl]),
        credits = maps:from_list([{{I, Slot}, false}
            || #{index := I, classes := Classes} <- ToRtl, #{slot := Slot} <- Classes])}.

-doc "Queues an ordinary cast from an exactly bound sender PID to one native actor. Source-bound class selection includes omitted constants and propagates real packing errors. Unknown identities or ambiguous classes fail; a full queue returns busy without admission. Offer order is preserved within each logical sender/destination pair.".
-spec offer(state(), pid(), actor(), tuple()) -> {ok, state()} | {error, busy}.
offer(State = #state{live = true, queued = Count, limit = Limit, senders = Senders,
        links = Links, queues = Queues}, Sender, Target, Message) when Count < Limit ->
    Source = maps:get(Sender, Senders),
    [Link = #{index := I}] = [Candidate || Candidate = #{source_index := S,
        destination_index := D, direction := to_rtl} <- maps:values(Links), S =:= Source, D =:= Target],
    {Slot, Frame} = hls_protocol_mixed:encode(Link, Message),
    Queue = maps:get(I, Queues),
    {ok, State#state{queued = Count + 1, queues = Queues#{I := queue:in({Slot, Frame}, Queue)}}};
offer(#state{live = true}, _, _, _) -> {error, busy}.

-doc "Reserves one credited pair head, consuming its credit and input sequence before returning. Round-robin arbitration may pass a blocked different sender, never a pair's head. Caller serializes physical writes; no sequence wrap, rollback or replay is permitted after reservation. Ambiguous outcomes invalidate the incarnation.".
-spec next(state()) -> none | {packet(), state()}.
next(State = #state{live = true, order = Order, cursor = Cursor}) ->
    {Before, After} = lists:split(Cursor, Order),
    case credited_head(After ++ Before, Cursor, State) of
        none -> none;
        Head -> reserve(Head, State)
    end.

%% Read only each pair's head; a later record cannot bypass a blocked head on that pair.
-spec credited_head([link()], non_neg_integer(), state()) -> none | #head{}.
credited_head([], _, _) -> none;
credited_head([I | Rest], Position, State = #state{queues = Queues, credits = Credits, order = Order}) ->
    case queue:peek(maps:get(I, Queues)) of
        {value, {Slot, Frame}} ->
            case maps:get({I, Slot}, Credits) of
                true -> #head{position = Position, link = I, slot = Slot, frame = Frame};
                false -> credited_head(Rest, (Position + 1) rem length(Order), State)
            end;
        empty -> credited_head(Rest, (Position + 1) rem length(Order), State)
    end.

%% Transfer one queued head to the physical writer and leave all other pairs untouched.
-spec reserve(#head{}, state()) -> {packet(), state()}.
reserve(#head{position = Position, link = I, slot = Slot, frame = Frame},
        State = #state{session = Session, sequence = Sequences, queues = Queues,
            credits = Credits, queued = Count, order = Order}) ->
    Sequence = maps:get(I, Sequences),
    true = Sequence < 16#ffffffff,
    {{value, {Slot, Frame}}, Tail} = queue:out(maps:get(I, Queues)),
    Packet = #{session => Session, sequence => Sequence, link => I, slot => Slot, frame => Frame},
    {Packet, State#state{cursor = (Position + 1) rem length(Order), queued = Count - 1,
        queues = Queues#{I := Tail}, credits = Credits#{{I, Slot} := false},
        sequence = Sequences#{I := Sequence + 1}}}.

-doc "Accepts one native credit in the common ordered output stream. Exact session/event sequence rejects stale, duplicate and skipped packets before reuse; an available or unknown slot rejects. Hardware may return credits only after native final release. Events cover both credits and data and never wrap.".
-spec credit(state(), session(), sequence(), link(), byte()) -> state().
credit(State, Session, Event, Link, Slot) ->
    Next = #state{credits = Credits} = event(State, Session, Event),
    false = maps:get({Link, Slot}, Credits),
    Next#state{credits = Credits#{{Link, Slot} := true}}.

-doc "Validates and decodes one hardware-to-BEAM cast in the ordered event stream. Returns its exact bound destination PID and record. The owner must deliver once and acknowledge only after actual admission; delivery failure ends the incarnation without replay. This operation alone gives no BEAM mailbox-capacity guarantee.".
-spec delivery(state(), session(), sequence(), link(), byte(), non_neg_integer()) -> {pid(), tuple(), state()}.
delivery(State, Session, Event, Link, Slot, Frame) ->
    Next = #state{links = Links, pids = Pids} = event(State, Session, Event),
    Route = #{direction := to_beam, destination_index := Target} = maps:get(Link, Links),
    Message = hls_protocol_mixed:decode(Route, Slot, Frame),
    {maps:get(Target, Pids), Message, Next}.

%% Output order protects credit grants from delayed duplicates as well as data replay.
-spec event(state(), session(), sequence()) -> state().
event(State = #state{live = true, session = Session, next_event = Event}, Session, Event)
        when Event < 16#ffffffff ->
    State#state{next_event = Event + 1}.

-doc "Permanently cancels this owner's queues, bindings and credits. A dead state cannot be reused by admission or reservation; replacement requires a fresh new/4 after coordinated reset and transport retirement.".
-spec invalidate(state()) -> state().
invalidate(State) -> State#state{live = false, pids = #{}, senders = #{}, queues = #{}, credits = #{}, queued = 0}.

-doc "Returns bounded queue/credit counts without exposing application payloads, PID bindings or mutable ownership.".
-spec info(state()) -> report().
info(#state{live = Live, queued = Count, limit = Limit, credits = Credits, next_event = Event}) ->
    #{live => Live, queued => Count, limit => Limit,
        available_credits => length([ok || true <- maps:values(Credits)]), next_event => Event}.
