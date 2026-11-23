-module(hls_protocol_mixed_stream).
-moduledoc """
Application clients start this owner from a checked mixed deployment and existing brokers. It combines hls_protocol_mixed_queue, actual BEAM admission and retained wire codecs under one incarnation.

One bounded owner for source actors, shared framing and BEAM admission. A failed incarnation never reconnects or replays. Trusted source actors must use this owner as their exclusive input writer; ERTS outbound queues are outside the 128-record transport budget.
""".
-behaviour(gen_server).
%% Public mixed-session API.
-export([start_link/5, submit/2, next/2, info/1, stop/1]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% Logical actor indices bind admitted records to exact local processes.
-type actor_id() :: non_neg_integer().
%% A source handoff names either a native actor or an application endpoint.
-type destination() :: {actor, actor_id()} | {external, atom()}.
%% The command retains only recipients that have not yet admitted its one record.
-type command() :: start | {control, binary(), [actor_id()], tuple()}.
%% One application waiter owns both its timeout token and timer.
-type waiter() :: none | {gen_server:from(), reference(), reference()}.
%% The distribution connection retains one authenticated handoff until admission.
-type handoff() :: none | {gen_server:from(), pid(), destination(), tuple()}.
%% Broker receipt credit is distinct from the native packet's delivery acknowledgment.
-type receipt() :: none | {reference(), hls_fabric:header(), binary()}.
%% Packet identity is retained until admission authorizes its exact reverse ACK.
-type packet() :: #{
    kind := 1 | 2,
    session := pos_integer(),
    sequence := non_neg_integer(),
    link := non_neg_integer(),
    slot := byte(),
    frame := non_neg_integer()
}.
%% Only a completed BEAM admission changes pending data into an eligible ACK.
-type reverse_delivery() :: {pending, actor_id(), tuple(), packet()} | {ack, packet()}.
%% The single response alias retains the purpose of an outstanding physical write.
-type writer_tag() :: attach | ack | start | control | data.
%% A prepared write includes its exact envelope; it must not be reserved again.
-type write_request() :: #{kind := writer_tag(), frame := {hls_fabric:header(), binary()}}.
%% Preparation may admit BEAM records or connect actors, even when it returns wait.
-type write_decision() :: {wait, state()} | {send, write_request(), state()}.
%% Owner state separates lifecycle, bounded categories, physical completion and client waiting.
-type state() :: #{
    plan := map(),
    broker := pid(),
    pids := #{actor_id() => pid()},
    session := pos_integer(),
    client := pid(),
    route := hls_fabric:route(),
    monitors := #{reference() => broker | consumer | manager | connection},
    admission := hls_protocol_mixed_admission:state(),
    queue := hls_protocol_mixed_queue:state(),
    phase := attaching | attached | starting | running,
    bound := boolean(),
    connected := boolean(),
    beam_connected := boolean(),
    starts := boolean(),
    manager => pid(),
    handles => #{term() => pid()},
    connection => pid(),
    commands := queue:queue(command()),
    events := queue:queue({atom(), tuple()}),
    reverse := #{non_neg_integer() => reverse_delivery()},
    handoff := handoff(),
    held := receipt(),
    writer := none | writer_tag(),
    sends := gen_server:request_id_collection(),
    waiter := waiter(),
    retry := boolean(),
    retiring := none | gen_server:from(),
    received := non_neg_integer(),
    written := non_neg_integer(),
    source_messages := non_neg_integer()
}.

-doc "Starts a fresh owner with exact source-bound host plan, broker, disconnected BEAM PIDs and nonzero fresh session. Options accepts admission_timeout only. Caller becomes the sole control/event consumer. Prior transport retirement and hardware reset must be established externally; this does not reset hardware. Starts one framed attachment, admits retained startup through public BEAM barriers, and requires a separately bound sealed virtual node before start.".
-spec start_link(map(), pid(), #{actor_id() => pid()}, pos_integer(), map()) ->
    gen_server:start_ret().
start_link(Plan, Broker, Pids, Session, Options) ->
    gen_server:start_link(?MODULE, {Plan, Broker, Pids, Session, Options, self()}, []).

-doc "Queues one checked rectangle or single-use start, returning busy without admission at the 16-command limit. Only the owner client may call. An accepted command may be partially executed on later failure; never replay.".
-spec submit(pid(), hls_partition_wire:command()) -> {ok, 1} | {error, busy}.
submit(Stream, Command) -> gen_server:call(Stream, {submit, Command}, infinity).

-doc "Takes one typed event, or timeout without abandoning an invisible waiter. Only one call by the owner client may be outstanding; consumer death retires the activation.".
-spec next(pid(), pos_integer()) -> {ok, pos_integer(), atom(), tuple()} | timeout.
next(Stream, Timeout) -> gen_server:call(Stream, {next, Timeout}, infinity).

-doc "Returns bounded counters and lifecycle, excluding payloads and actor bindings.".
-spec info(pid()) -> map().
info(Stream) -> gen_server:call(Stream, info).

-doc "Retires this owner after its current physical write completes, then retires the broker route; does not reset hardware or stop source actors. Complete transport retirement and coordinated reset precede any new owner.".
-spec stop(pid()) -> ok.
stop(Stream) -> gen_server:call(Stream, retire, infinity).

-doc "Checks current codec availability and retained widths before startup admission or route registration, then installs actor/transport/consumer monitors and reserves one broker route. Startup admission and any write ambiguity are terminal on failure.".
-spec init(tuple()) -> {ok, state()}.
init({
    Plan = #{
        actors := Actors,
        mixed := Mixed = #{identity := Identity, links := Links},
        binding := #{host := Host, control := Service}
    },
    Broker,
    Pids,
    Session,
    Options,
    Client
}) ->
    ok = hls_protocol_mixed_codec:check(Plan),
    #{admission_timeout := Timeout} = Config = maps:merge(#{admission_timeout => 1000}, Options),
    1 = map_size(Config),
    true = Timeout > 0,
    true = lists:sort(maps:keys(Pids)) =:= lists:sort(maps:keys(Actors)),
    Bindings = maps:map(
        fun(I, #{capacity := Capacity}) ->
            #{pid => maps:get(I, Pids), capacity => Capacity}
        end,
        Actors
    ),
    Reverse = length([ok || #{direction := to_beam} <- Links]),
    true = Reverse > 0 andalso Reverse =< 12,
    Queue = hls_protocol_mixed_queue:new(Mixed, Pids, Session, min(64, 77 - Reverse)),
    Admission0 = hls_protocol_mixed_admission:new(Bindings, Timeout),
    Admission = lists:foldl(
        fun({I, Record}, Acc) ->
            {ok, Next} = hls_protocol_mixed_admission:deliver(I, Record, Acc),
            Next
        end,
        Admission0,
        hls_protocol_mixed_host:startup(Plan)
    ),
    true = lists:all(
        fun(P) ->
            #{lifecycle := disconnected} = hls_statem:info(P, Timeout),
            true
        end,
        maps:values(Pids)
    ),
    ok = hls_fabric:register_route(Broker, {Service, Host}, self()),
    State = #{
        plan => Plan,
        broker => Broker,
        pids => Pids,
        session => Session,
        client => Client,
        route => {Host, Service},
        monitors => #{monitor(process, Broker) => broker, monitor(process, Client) => consumer},
        admission => Admission,
        queue => Queue,
        phase => attaching,
        bound => false,
        connected => false,
        beam_connected => false,
        starts => false,
        commands => queue:new(),
        events => queue:new(),
        reverse => #{},
        handoff => none,
        held => none,
        writer => none,
        sends => gen_server:reqids_new(),
        waiter => none,
        retry => false,
        received => 0,
        written => 0,
        source_messages => 0,
        retiring => none
    },
    Request = #{kind => attach, frame => hls_protocol_bridge_wire:attach(Identity, Session)},
    {ok, issue_write({send, Request, State})}.

-doc "Binds one virtual incarnation/connection, admits bounded source handoffs and serves the single application client.".
-spec handle_call(term(), gen_server:from(), state()) ->
    {reply, term(), state()} | {noreply, state()} | {stop, normal, ok, state()}.
%% Stop issuing packets; complete an already reserved physical write before releasing the route.
handle_call(
    retire, From = {Client, _}, State = #{client := Client, retiring := none, writer := Writer}
) ->
    case Writer of
        none -> {stop, normal, ok, State};
        _ -> {noreply, State#{retiring := From}}
    end;
%% Binding is one-shot and must match every source-derived virtual destination.
handle_call(
    {source_bind, Identity, Handles},
    {Manager, _},
    State = #{bound := false, plan := #{targets := Targets}, monitors := Monitors}
) ->
    true = lists:sort(maps:keys(Handles)) =:= lists:sort(maps:keys(Targets)),
    #{name := Node} = Identity,
    true = lists:all(fun(P) -> is_pid(P) andalso node(P) =:= Node end, maps:values(Handles)),
    true = length(lists:usort(maps:values(Handles))) =:= map_size(Handles),
    {reply, ok, State#{
        bound := true,
        manager => Manager,
        handles => Handles,
        monitors := Monitors#{monitor(process, Manager) => manager}
    }};
%% The bound manager may attach exactly one distribution connection.
handle_call(
    {source_attach, Connection},
    {Manager, _},
    State = #{manager := Manager, connected := false, monitors := Monitors}
) ->
    {reply, ok, State#{
        connected := true,
        connection => Connection,
        monitors := Monitors#{monitor(process, Connection) => connection}
    }};
%% Withhold the sole handoff reply until the correct bounded queue has room.
handle_call(
    {source_send, Sender, Destination, Record},
    From = {Connection, _},
    State = #{connection := Connection, handoff := none, pids := Pids}
) ->
    true = lists:member(Sender, maps:values(Pids)),
    {noreply, work(State#{handoff := {From, Sender, Destination, Record}})};
%% Admission preserves command order; start is explicitly one-shot.
handle_call(
    {submit, Command},
    {Client, _},
    State = #{client := Client, commands := Commands, starts := Started, plan := Plan}
) ->
    case queue:len(Commands) < 16 of
        false ->
            {reply, {error, busy}, State};
        true ->
            Entry =
                case Command of
                    start ->
                        false = Started,
                        start;
                    _ ->
                        {Bytes, Targets, Record} = hls_protocol_mixed_host:controls(Plan, Command),
                        {control, Bytes, Targets, Record}
                end,
            Next = State#{
                commands := queue:in(Entry, Commands), starts := Started orelse Command =:= start
            },
            {reply, {ok, 1}, work(Next)}
    end;
%% One pending read is bounded and cancelled by the owner's timer before a timeout reply.
handle_call({next, Timeout}, From = {Client, _}, State = #{client := Client, waiter := none}) when
    Timeout > 0
->
    Token = make_ref(),
    Timer = erlang:send_after(Timeout, self(), {next_timeout, Token}),
    {noreply, work(State#{waiter := {From, Token, Timer}})};
%% Counters include every transport category without private actor-state access.
handle_call(
    info,
    _From,
    State = #{
        queue := Queue,
        admission := Admission,
        commands := Commands,
        events := Events,
        reverse := Reverse,
        handoff := Handoff,
        held := Held,
        writer := Writer
    }
) ->
    Counts = #{
        outgoing => maps:get(queued, hls_protocol_mixed_queue:info(Queue)),
        commands => queue:len(Commands),
        events => queue:len(Events),
        reverse => map_size(Reverse),
        handoff => occupied(Handoff),
        held => occupied(Held),
        writer => occupied(Writer)
    },
    true = lists:sum(maps:values(Counts)) =< 128,
    Info = (maps:with([phase, bound, connected, received, written, source_messages], State))#{
        counts => Counts, admission => hls_protocol_mixed_admission:info(Admission)
    },
    {reply, Info, State}.

-doc "Retains at most one credited broker frame; all other casts are unsupported.".
-spec handle_cast(term(), state()) -> {noreply, state()}.
%% A broker receipt is independent of the later native delivery ACK.
handle_cast(
    {'$hls_fabric_frame', Receipt, {Service, Host}, Header, Payload},
    State = #{route := {Host, Service}, held := none}
) ->
    {noreply, work(State#{held := {Receipt, Header, Payload}})}.

-doc "Completes one physical write, retries capacity checks and retires on any monitored lifetime failure.".
-spec handle_info(term(), state()) -> {noreply, state()} | {stop, term(), state()}.
%% A failed participant makes the whole incarnation unusable; never retry ambiguous input.
handle_info(
    {'DOWN', Ref, process, _Pid, Reason}, State = #{monitors := Monitors, admission := Admission}
) ->
    case maps:find(Ref, Monitors) of
        {ok, Kind} ->
            {stop, {shutdown, {Kind, Reason}}, State};
        error ->
            case hls_protocol_mixed_admission:down(Ref, Reason, Admission) of
                {error, Failure, Next} -> {stop, {shutdown, Failure}, State#{admission := Next}};
                {unrelated, _} -> {noreply, State}
            end
    end;
%% Recheck bounded postponed work without holding a BEAM actor or physical receive lock.
handle_info(retry, State) ->
    {noreply, work(State#{retry := false})};
%% Timeout removes the single waiter before replying, so a later event cannot vanish into an abandoned alias.
handle_info({next_timeout, Token}, State = #{waiter := {From, Token, _}}) ->
    gen_server:reply(From, timeout),
    {noreply, State#{waiter := none}};
%% Ignore a timeout already cancelled by delivery.
handle_info({next_timeout, _}, State) ->
    {noreply, State};
%% A successful writer response frees only the physical slot; BEAM admission already authorized each ACK.
handle_info(
    Message, State = #{sends := Sends, writer := Writer, written := Count, retiring := Retiring}
) ->
    case gen_server:check_response(Message, Sends, true) of
        {{reply, ok}, Writer, Remaining} ->
            Next = State#{writer := none, sends := Remaining, written := Count + 1},
            case Retiring of
                none ->
                    {noreply, work(Next)};
                From ->
                    gen_server:reply(From, ok),
                    {stop, normal, Next}
            end;
        {{reply, Result}, _, _} ->
            {stop, {shutdown, {write_failed, Result}}, State};
        {{error, Reason}, _, _} ->
            {stop, {shutdown, {writer_failed, Reason}}, State};
        _ ->
            {noreply, State}
    end.

-doc "Cancels admission monitors and a pending client timer. Broker owner death retires its route; source actors and hardware require separate coordinated shutdown/reset.".
-spec terminate(term(), state()) -> ok.
terminate(_, #{admission := Admission, waiter := Waiter}) ->
    _ = hls_protocol_mixed_admission:retire(Admission),
    case Waiter of
        none ->
            ok;
        {_, _, Timer} ->
            erlang:cancel_timer(Timer),
            ok
    end.

%% One pass reconsiders each category once. Admission can have effects; only issue_write sends packets.
-spec work(state()) -> state().
work(State = #{retiring := From}) when From =/= none -> State;
work(State) ->
    Notified = notify(State),
    Received = receive_frame(Notified),
    Admitted = admit_reverse(Received),
    HandedOff = handoff(Admitted),
    Delivered = notify(HandedOff),
    Written = issue_write(prepare_write(Delivered)),
    retry(Written).

%% Deliver one queued event to a waiting client without an unbounded notification mailbox.
-spec notify(state()) -> state().
notify(State = #{waiter := none}) ->
    State;
notify(State = #{waiter := {From, _, Timer}, events := Events, session := Session}) ->
    case queue:out(Events) of
        {empty, _} ->
            State;
        {{value, {Id, Record}}, Rest} ->
            erlang:cancel_timer(Timer),
            gen_server:reply(From, {ok, Session, Id, Record}),
            State#{waiter := none, events := Rest}
    end.

%% Keep the broker receipt while event storage is full; packet validation precedes its release.
-spec receive_frame(state()) -> state().
receive_frame(State = #{held := none}) ->
    State;
receive_frame(
    State = #{
        held := {Receipt, Header, Payload},
        session := Session,
        events := Events,
        broker := Broker,
        received := Count
    }
) ->
    Event = hls_protocol_bridge_wire:event(Session, Header, Payload),
    Blocked =
        case Event of
            {external, _, _} -> queue:len(Events) >= 32;
            started -> queue:len(Events) >= 32;
            _ -> false
        end,
    case Blocked of
        true ->
            State;
        false ->
            Next = event(Event, State),
            hls_fabric:ack(Broker, Receipt),
            Next#{held := none, received := Count + 1}
    end.

%% Attachment/start replies are single-use; the queue validates the ordered native credit/data stream.
-spec event(term(), state()) -> state().
event(attached, State = #{phase := attaching}) ->
    State#{phase := attached};
event(started, State = #{phase := starting, events := Events}) ->
    State#{phase := running, events := queue:in({application, {started}}, Events)};
event({external, Index, Frame}, State = #{plan := Plan, events := Events}) ->
    State#{events := queue:in(hls_protocol_mixed_host:native_event(Plan, Index, Frame), Events)};
event(
    {packet, #{kind := 2, session := Session, sequence := Seq, link := Link, slot := Slot}},
    State = #{queue := Queue}
) ->
    State#{queue := hls_protocol_mixed_queue:credit(Queue, Session, Seq, Link, Slot)};
event(
    {packet,
        Packet = #{
            kind := 1,
            session := Session,
            sequence := Seq,
            link := Link,
            slot := Slot,
            frame := Frame
        }},
    State = #{queue := Queue, reverse := Reverse, pids := Pids}
) ->
    false = maps:is_key(Link, Reverse),
    {Pid, Record, Next} = hls_protocol_mixed_queue:delivery(Queue, Session, Seq, Link, Slot, Frame),
    [Target] = [I || {I, P} <- maps:to_list(Pids), P =:= Pid],
    State#{queue := Next, reverse := Reverse#{Link => {pending, Target, Record, Packet}}}.

%% Retain bootstrap queries until actors connect, then try each reverse pair once.
-spec admit_reverse(state()) -> state().
admit_reverse(State = #{beam_connected := false}) ->
    State;
admit_reverse(State = #{reverse := Reverse}) ->
    lists:foldl(fun admit_reverse_pair/2, State, lists:sort(maps:to_list(Reverse))).

%% Busy actors keep their pair pending; independent pairs can still complete admission.
-spec admit_reverse_pair({non_neg_integer(), reverse_delivery()}, state()) -> state().
admit_reverse_pair(
    {Link, {pending, Target, Record, Packet}},
    State = #{admission := Admission, reverse := Reverse}
) ->
    case hls_protocol_mixed_admission:deliver(Target, Record, Admission) of
        {ok, Next} -> State#{admission := Next, reverse := Reverse#{Link := {ack, Packet}}};
        {busy, Next} -> State#{admission := Next};
        {error, Reason, _} -> error(Reason)
    end;
admit_reverse_pair(_, State) ->
    State.

%% The connection retains one authenticated record until its bounded destination queue accepts it.
-spec handoff(state()) -> state().
handoff(State = #{handoff := none}) ->
    State;
handoff(State = #{handoff := {From, Sender, {actor, Target}, Record}, queue := Queue}) ->
    case hls_protocol_mixed_queue:offer(Queue, Sender, Target, Record) of
        {error, busy} -> State;
        {ok, Next} -> accepted(From, State#{queue := Next})
    end;
handoff(
    State = #{
        handoff := {From, Sender, {external, Id}, Record},
        plan := Plan,
        pids := Pids,
        events := Events
    }
) ->
    case queue:len(Events) < 32 of
        false ->
            State;
        true ->
            [Index] = [I || {I, P} <- maps:to_list(Pids), P =:= Sender],
            Event = hls_protocol_mixed_host:external(Plan, Index, Id, Record),
            accepted(From, State#{events := queue:in(Event, Events)})
    end.

%% Acceptance releases distribution handoff credit, not native slot credit.
-spec accepted(gen_server:from(), state()) -> state().
accepted(From, State = #{source_messages := Count}) ->
    gen_server:reply(From, ok),
    State#{handoff := none, source_messages := Count + 1}.

%% Retained writer and attachment precede admitted ACKs, ordered commands and source data.
-spec prepare_write(state()) -> write_decision().
prepare_write(State = #{writer := Writer}) when Writer =/= none -> {wait, State};
prepare_write(State = #{phase := attaching}) ->
    {wait, State};
prepare_write(State = #{reverse := Reverse}) ->
    case [{Link, Packet} || {Link, {ack, Packet}} <- lists:sort(maps:to_list(Reverse))] of
        [{Link, Packet} | _] ->
            Request = #{
                kind => ack,
                frame => hls_protocol_bridge_wire:packet(Packet#{kind := 2, frame := 0})
            },
            {send, Request, State#{reverse := maps:remove(Link, Reverse)}};
        [] ->
            prepare_command(State)
    end.

%% BEAM recipient admission and one-shot connection are effects of preparing the head command.
-spec prepare_command(state()) -> write_decision().
prepare_command(State = #{commands := Commands, session := Session}) ->
    case queue:out(Commands) of
        {empty, _} ->
            prepare_data(State);
        {{value, start}, Rest} ->
            #{connected := true, plan := Plan, pids := Pids, handles := Handles, phase := attached} =
                State,
            ok = hls_protocol_mixed_host:connect(Plan, Pids, Handles),
            Request = #{kind => start, frame => hls_protocol_bridge_wire:command(Session, start)},
            {send, Request, State#{commands := Rest, phase := starting, beam_connected := true}};
        {{value, {control, Bytes, Targets, Record}}, Rest} ->
            {Remaining, Next} = admit_targets(Targets, Record, State),
            case Remaining of
                [] ->
                    Request = #{
                        kind => control, frame => hls_protocol_bridge_wire:command(Session, Bytes)
                    },
                    {send, Request, Next#{commands := Rest}};
                _ ->
                    {wait, Next#{commands := queue:in_r({control, Bytes, Remaining, Record}, Rest)}}
            end
    end.

%% Remove each admitted recipient before retrying; an already admitted cast is never replayed.
-spec admit_targets([actor_id()], tuple(), state()) -> {[actor_id()], state()}.
admit_targets([], _, State) ->
    {[], State};
admit_targets([I | Rest] = Targets, Record, State = #{admission := Admission}) ->
    case hls_protocol_mixed_admission:deliver(I, Record, Admission) of
        {ok, Next} -> admit_targets(Rest, Record, State#{admission := Next});
        {busy, Next} -> {Targets, State#{admission := Next}};
        {error, Reason, _} -> error(Reason)
    end.

%% Reserve source credit and sequence before handing the exact packet to the physical writer.
-spec prepare_data(state()) -> write_decision().
prepare_data(State = #{queue := Queue}) ->
    case hls_protocol_mixed_queue:next(Queue) of
        none ->
            {wait, State};
        {Packet, Next} ->
            Request = #{kind => data, frame => hls_protocol_bridge_wire:packet(Packet#{kind => 1})},
            {send, Request, State#{queue := Next}}
    end.

%% This is the only packet-sending boundary. Reserved requests have no rollback or replay path.
-spec issue_write(write_decision()) -> state().
issue_write({wait, State}) ->
    State;
issue_write(
    {send, #{kind := Kind, frame := {Header, Payload}},
        State = #{broker := Broker, route := Route, writer := none, sends := Sends}}
) ->
    Ref = hls_fabric:send_request(Broker, Route, Header, Payload, infinity),
    State#{writer := Kind, sends := gen_server:reqids_add(Ref, Kind, Sends)}.

%% One timer rechecks local capacity waits; it never retransmits a reserved packet.
-spec retry(state()) -> state().
retry(State = #{retry := true}) ->
    State;
retry(State = #{reverse := Reverse, handoff := Handoff, commands := Commands, held := Held}) ->
    Pending =
        map_size(Reverse) > 0 orelse Handoff =/= none orelse
            not queue:is_empty(Commands) orelse Held =/= none,
    case Pending of
        true ->
            erlang:send_after(5, self(), retry),
            State#{retry := true};
        false ->
            State
    end.

%% Count one occupied transport category without exposing its record.
-spec occupied(term()) -> 0 | 1.
occupied(none) -> 0;
occupied(_) -> 1.
