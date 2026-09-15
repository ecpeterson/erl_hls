-module(hls_fabric).
-moduledoc """
Owns one routed frame device with bounded transmit admission and receive
credits. Application and debug streams use separate device brokers. Logical
sessions may close independently while the device and its two raw I/O workers
remain open. Route ownership, deadlines, and inspection stay responsive when
either physical direction stalls.

`send/4` waits for write completion; `send_request/5` uses OTP's asynchronous
request interface. A `{not_sent, Reason}` rejection guarantees that this frame
never reached the writer. Failure after writing starts is ambiguous and closes
the transport. No operation is retried. A write does not prove device admission.

Each delivered cast is `{'$hls_fabric_frame', Receipt, Route, Header, Payload}`.
The registered owner must call `ack/2` after processing it. Receipts are single
use and owner-specific. A slow route eventually blocks the shared receive
stream; it cannot accumulate an unbounded number of frames in its mailbox.
The route remains transport metadata, not an actor-message sender identity.

Routes are retired when their owners or sessions exit. Retirement survives
logical session replacement. Reuse requires a drained/reset device boundary;
see `docs/host-transactions.md`. Device closure is confirmed separately from
broker death; unconfirmed raw I/O release prevents a competing open in this VM.
""".

-behavior(gen_server).

-export([start_link/2, start_link/3, stop/1, close/2, await_closed/2, open_session/1, drain_session/2]).
-export([register_route/3, send/4, send/5, send_request/5, ack/2, info/1, client_info/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-type endpoint() :: 0..65535.
-type route() :: {endpoint(), endpoint()}.
-type header() :: {byte(), byte(), byte()}.
-type deadline() :: timeout() | {abs, integer()}.
-export_type([route/0, header/0, deadline/0]).

-record(route_owner, {pid :: pid(), monitor :: reference(), session = none :: pid() | none}).
-record(session, {monitor :: reference(), status = open :: open | draining}).
-record(tx, {
    id :: reference(),
    session = none :: pid() | none,
    from :: gen_server:from() | none,
    monitor :: reference(),
    timer :: reference() | none,
    deadline :: integer() | infinity,
    route :: route(),
    bytes :: binary()
}).
-record(state, {
    lease :: reference(),
    sessions = #{} :: #{pid() => #session{}},
    writer :: pid(),
    writer_ready = false :: boolean(),
    reader :: pid(),
    reading = false :: boolean(),
    routes = #{} :: #{route() => #route_owner{} | retired},
    queued = {[], []} :: queue:queue(#tx{}),
    active = none :: none | #tx{},
    tx_limit :: pos_integer(),
    tx_route_limit :: pos_integer(),
    rx_limit :: pos_integer(),
    rx_route_limit :: pos_integer(),
    receipts = #{} :: #{reference() => {pid(), route()}},
    buffered = none :: none | {route(), header(), binary()},
    counts = #{written => 0, received => 0, discarded => 0,
        rejected => 0, expired => 0, ignored_acks => 0} :: map()
}).

start_link(WritePath, ReadPath) -> start_link(WritePath, ReadPath, #{}).

-doc "Options: tx_limit (1024), tx_route_limit (512), rx_limit (64), rx_route_limit (1), in frames.".
start_link(WritePath, ReadPath, Options) ->
    gen_server:start_link(?MODULE, {WritePath, ReadPath, Options}, []).

-doc "Stops a session or device broker. Raw I/O release may still be pending; use close/2 to await it.".
stop(Pid) -> gen_server:stop(Pid).

-doc "Stops the device broker and waits for confirmed descriptor closure. Timeout leaves its lease held.".
-spec close(pid(), timeout()) -> ok | {error, term()}.
close(Device, Timeout) when Timeout =:= infinity; is_integer(Timeout), Timeout >= 0 ->
    Lease = gen_server:call(Device, io_lease),
    ok = stop(Device),
    await_closed(Lease, Timeout).

-doc "Waits on the io.lease returned by info/1, including after the device broker exits.".
-spec await_closed(reference(), timeout()) -> ok | {error, term()}.
await_closed(Lease, Timeout) when is_reference(Lease), Timeout =:= infinity;
        is_reference(Lease), is_integer(Timeout), Timeout >= 0 ->
    hls_fabric_lease:await(Lease, Timeout).

-doc "Opens a replaceable logical session on a persistent device broker. Accepts the same frame API.".
-spec open_session(pid()) -> {ok, pid()} | {error, term()}.
open_session(Device) when node(Device) =:= node() -> hls_fabric_session:start_link(Device).

-doc "Stops session admission, waits for host writes and receipts, then retires its routes. Does not fence device work.".
-spec drain_session(pid(), timeout()) -> ok | {error, draining}.
drain_session(Session, Timeout) -> gen_server:call(Session, drain_session, Timeout).

-spec register_route(pid(), route(), pid()) -> ok | {error, term()}.
register_route(Pid, Route, Owner) when node(Pid) =:= node(), node(Owner) =:= node() ->
    gen_server:call(Pid, {register_route, Route, Owner}).

-spec send(pid(), route(), header(), binary()) -> ok | {error, term()}.
send(Pid, Route, Header, Payload) -> send(Pid, Route, Header, Payload, 5000).

-spec send(pid(), route(), header(), binary(), deadline()) -> ok | {error, term()}.
send(Pid, Route, Header, Payload, Timeout) ->
    Request = send_request(Pid, Route, Header, Payload, Timeout),
    case gen_server:receive_response(Request, infinity) of
        {reply, Result} -> Result;
        {error, {Reason, _Server}} -> {error, {transport_down, Reason}}
    end.

-doc "Returns an OTP request ID. The broker owns the queue/write deadline, including time before admission.".
-spec send_request(pid(), route(), header(), binary(), deadline()) -> gen_server:request_id().
send_request(Pid, Route, Header, Payload, Timeout) when node(Pid) =:= node() ->
    gen_server:send_request(Pid, {send, Route, Header, Payload, deadline(Timeout)}).

deadline(infinity) -> infinity;
deadline({abs, Deadline}) when is_integer(Deadline) -> Deadline;
deadline(Timeout) when is_integer(Timeout), Timeout >= 0 ->
    erlang:monotonic_time(millisecond) + Timeout.

-spec ack(pid(), reference()) -> ok.
ack(Pid, Receipt) -> gen_server:cast(Pid, {ack, self(), Receipt}).

-doc "Inspects broker admission, physical I/O, receive credits, and route ownership without device traffic.".
-spec info(pid()) -> map().
info(Pid) -> gen_server:call(Pid, info).

-doc "Returns local transaction occupancy for an hls_gs or hls_debug proxy; a CPU hls_gs returns none.".
-spec client_info(pid()) -> map() | none.
client_info(Pid) -> gen_server:call(Pid, '$hls_fabric_info').

init({WritePath, ReadPath, Options}) ->
    Defaults = #{tx_limit => 1024, tx_route_limit => 512, rx_limit => 64, rx_route_limit => 1},
    case is_map(Options) andalso maps:without(maps:keys(Defaults), Options) =:= #{}
            andalso lists:all(fun(V) -> is_integer(V) andalso V > 0 end, maps:values(Options)) of
        false -> {stop, {invalid_options, Options}};
        true ->
            #{tx_limit := Tx, tx_route_limit := TxRoute,
                rx_limit := Rx, rx_route_limit := RxRoute} = maps:merge(Defaults, Options),
            process_flag(trap_exit, true),
            case hls_fabric_lease:open(WritePath, ReadPath, self()) of
                {ok, Lease, Writer, Reader} ->
                    {ok, pump_rx(#state{lease = Lease, writer = Writer, reader = Reader,
                        tx_limit = Tx, tx_route_limit = TxRoute, rx_limit = Rx, rx_route_limit = RxRoute})};
                {error, Reason} -> {stop, Reason}
            end
    end.

handle_call(attach_session, {Session, _}, State = #state{sessions = Sessions}) ->
    case Sessions of
        #{Session := _} -> {reply, ok, State};
        _ ->
            Entry = #session{monitor = monitor(process, Session)},
            {reply, ok, State#state{sessions = Sessions#{Session => Entry}}}
    end;
handle_call(io_lease, _From, State = #state{lease = Lease}) -> {reply, Lease, State};
handle_call({session, Session, Request}, From, State = #state{sessions = Sessions}) ->
    case {Request, Sessions} of
        {info, _} -> request(info, Session, From, State);
        {_, #{Session := #session{status = open}}} -> settle(request(Request, Session, From, State));
        {{send, _, _, _, _}, _} -> reject(session_closed, State);
        _ -> {reply, {error, session_closed}, State}
    end;
handle_call(Request, From, State) -> settle(request(Request, none, From, State)).

request({register_route, Route, Owner}, Session, _From, State = #state{routes = Routes})
        when is_pid(Owner) ->
    case {hls_fabric_io:valid_route(Route), Routes} of
        {true, #{Route := #route_owner{pid = Owner, session = Session}}} ->
            case is_process_alive(Owner) of
                true -> {reply, ok, State};
                false -> {reply, {error, {route_retired, Route}}, retire(Owner, State)}
            end;
        {true, #{Route := retired}} -> {reply, {error, {route_retired, Route}}, State};
        {true, #{Route := #route_owner{pid = Existing, monitor = Monitor}}} ->
            case is_process_alive(Existing) of
                true -> {reply, {error, {route_in_use, Route, Existing}}, State};
                false ->
                    demonitor(Monitor, [flush]),
                    {reply, {error, {route_retired, Route}}, retire(Existing, State)}
            end;
        {true, _} ->
            Entry = #route_owner{pid = Owner, monitor = monitor(process, Owner), session = Session},
            {reply, ok, State#state{routes = Routes#{Route => Entry}}};
        {false, _} -> {reply, {error, {invalid_route, Route}}, State}
    end;
request({send, Route, Header, Payload, Deadline}, Session, From, State)
        when is_integer(Deadline); Deadline =:= infinity ->
    case hls_fabric_io:encode(Route, Header, Payload) of
        {error, Reason} -> reject(Reason, State);
        {ok, Bytes} -> admit(Route, Bytes, Deadline, Session, From, State)
    end;
request(info, Session, _From, State) ->
    {reply, (snapshot(State))#{session => Session}, State};
request(Request, _Session, _From, State) -> {reply, {error, {invalid_request, Request}}, State}.

handle_cast(Message, State) -> settle(cast(Message, State)).
handle_info(Message, State) -> settle(event(Message, State)).

settle({noreply, State}) -> {noreply, finish_draining(State)};
settle({reply, Reply, State}) -> {reply, Reply, finish_draining(State)};
settle(Result) -> Result.

cast({drain_session, Session}, State = #state{sessions = Sessions}) ->
    case Sessions of
        #{Session := Entry} ->
            {noreply, State#state{sessions = Sessions#{Session := Entry#session{status = draining}}}};
        _ -> {noreply, State}
    end;
cast({ack, Owner, Receipt}, State = #state{receipts = Receipts}) ->
    case Receipts of
        #{Receipt := {Owner, _Route}} ->
            {noreply, pump_rx(State#state{receipts = maps:remove(Receipt, Receipts)})};
        _ -> {noreply, count(ignored_acks, State)}
    end;
cast(_Message, State) -> {noreply, State}.

event({writer_ready, Writer}, State = #state{writer = Writer}) ->
    {noreply, pump_tx(State#state{writer_ready = true})};
event({written, Writer, ID, ok},
        State = #state{writer = Writer, active = #tx{id = ID, deadline = Deadline, route = Route} = Tx}) ->
    case expired(Deadline) of
        false ->
            complete(Tx, ok),
            {noreply, pump_tx(count(written, State#state{active = none}))};
        true ->
            complete(Tx, {error, {write_timeout, Route}}),
            {stop, {write_timeout, Route}, State#state{active = none}}
    end;
event({written, Writer, ID, {error, Reason}},
        State = #state{writer = Writer, active = #tx{id = ID} = Tx}) ->
    complete(Tx, {error, Reason}),
    {stop, {write_failed, Reason}, State#state{active = none}};
event({timeout, Timer, ID}, State = #state{active = #tx{id = ID, timer = Timer, route = Route} = Tx}) ->
    complete(Tx, {error, {write_timeout, Route}}),
    {stop, {write_timeout, Route}, State#state{active = none}};
event({timeout, Timer, ID}, State = #state{queued = Queued}) ->
    {Expired, Remaining} = lists:partition(fun(#tx{id = Ref, timer = T}) ->
        Ref =:= ID andalso T =:= Timer
    end, queue:to_list(Queued)),
    [complete(Tx, {error, {not_sent, timeout}}) || Tx <- Expired],
    Next = lists:foldl(fun(_, Acc) -> count(expired, Acc) end,
        State#state{queued = queue:from_list(Remaining)}, Expired),
    {noreply, pump_tx(Next)};
event({received, Reader, Route, Header, Payload}, State = #state{reader = Reader, reading = true}) ->
    {noreply, pump_rx(State#state{reading = false, buffered = {Route, Header, Payload}})};
event({'DOWN', Monitor, process, Session, _Reason}, State = #state{sessions = Sessions})
        when is_map_key(Session, Sessions), (map_get(Session, Sessions))#session.monitor =:= Monitor ->
    {noreply, pump_tx(retire_session(Session, State))};
event({'DOWN', Monitor, process, Owner, _Reason}, State) ->
    case owns_monitor(Monitor, State) of
        true -> {noreply, pump_tx(retire(Owner, State))};
        false -> {noreply, State}
    end;
event({'EXIT', Writer, Reason}, State = #state{writer = Writer}) ->
    {stop, {writer_down, Reason}, State};
event({'EXIT', Reader, Reason}, State = #state{reader = Reader}) ->
    {stop, {reader_down, Reason}, State};
event(_Message, State) -> {noreply, State}.

admit(Route, Bytes, Deadline, Session, From = {Owner, _}, State = #state{
    queued = Queued, tx_limit = Limit, tx_route_limit = RouteLimit
}) ->
    Transactions = transactions(State),
    SameRoute = [T || T = #tx{route = R} <- Transactions, R =:= Route],
    case {expired(Deadline), length(Transactions) >= Limit, length(SameRoute) >= RouteLimit} of
        {true, _, _} -> reject(timeout, count(expired, State));
        {_, true, _} -> reject(tx_limit, State);
        {_, _, true} -> reject({route_tx_limit, Route}, State);
        _ ->
            ID = make_ref(),
            Timer = case Deadline of
                infinity -> none;
                _ -> erlang:start_timer(max(0, Deadline - erlang:monotonic_time(millisecond)), self(), ID)
            end,
            Tx = #tx{id = ID, session = Session, from = From, monitor = monitor(process, Owner), timer = Timer,
                deadline = Deadline, route = Route, bytes = Bytes},
            {noreply, pump_tx(State#state{queued = queue:in(Tx, Queued)})}
    end.

reject(Reason, State) -> {reply, {error, {not_sent, Reason}}, count(rejected, State)}.
expired(infinity) -> false;
expired(Deadline) -> Deadline =< erlang:monotonic_time(millisecond).

pump_tx(State = #state{writer_ready = true, active = none, writer = Writer, queued = Queued}) ->
    case queue:out(Queued) of
        {empty, _} -> State;
        {{value, Tx = #tx{id = ID, deadline = Deadline, bytes = Bytes}}, Rest} ->
            case expired(Deadline) of
                true ->
                    complete(Tx, {error, {not_sent, timeout}}),
                    pump_tx(count(expired, State#state{queued = Rest}));
                false ->
                    Writer ! {write, ID, Bytes},
                    State#state{queued = Rest, active = Tx}
            end
    end;
pump_tx(State) -> State.

complete(#tx{from = From, monitor = Monitor, timer = Timer}, Reply) ->
    demonitor(Monitor, [flush]),
    case Timer of none -> ok; _ -> erlang:cancel_timer(Timer) end,
    case From of none -> ok; _ -> gen_server:reply(From, Reply) end.

transactions(#state{queued = Queued, active = none}) -> queue:to_list(Queued);
transactions(#state{queued = Queued, active = Tx}) -> [Tx | queue:to_list(Queued)].

owns_monitor(Monitor, State = #state{routes = Routes}) ->
    lists:any(fun
        (#route_owner{monitor = Ref}) -> Ref =:= Monitor;
        (retired) -> false
    end, maps:values(Routes)) orelse
        lists:any(fun(#tx{monitor = Ref}) -> Ref =:= Monitor end, transactions(State)).

retire(Owner, State = #state{routes = Routes, receipts = Receipts, queued = Queued, active = Active}) ->
    NewRoutes = maps:map(fun
        (_Route, #route_owner{pid = Pid, monitor = Monitor}) when Pid =:= Owner ->
            demonitor(Monitor, [flush]), retired;
        (_Route, Entry) -> Entry
    end, Routes),
    {Abandoned, Live} = lists:partition(fun(#tx{from = From}) ->
        case From of {Pid, _} -> Pid =:= Owner; none -> false end
    end, queue:to_list(Queued)),
    [complete(Tx, {error, {not_sent, owner_down}}) || Tx <- Abandoned],
    NextActive = case Active of
        #tx{from = {Owner, _}} -> Active#tx{from = none};
        _ -> Active
    end,
    Remaining = maps:filter(fun(_Receipt, {Pid, _Route}) -> Pid =/= Owner end, Receipts),
    pump_rx(State#state{routes = NewRoutes, receipts = Remaining,
        queued = queue:from_list(Live), active = NextActive}).

finish_draining(State = #state{sessions = Sessions}) ->
    maps:fold(fun
        (Session, #session{status = draining}, Acc) ->
            case session_busy(Session, Acc) of
                true -> Acc;
                false ->
                    gen_server:cast(Session, {session_drained, self()}),
                    retire_session(Session, Acc)
            end;
        (_Session, _Entry, Acc) -> Acc
    end, State, Sessions).

session_busy(Session, State = #state{routes = Routes, receipts = Receipts, buffered = Buffered}) ->
    Owns = fun(Route) ->
        case Routes of #{Route := #route_owner{session = Session}} -> true; _ -> false end
    end,
    lists:any(fun(#tx{session = S}) -> S =:= Session end, transactions(State)) orelse
        lists:any(fun({_Owner, Route}) -> Owns(Route) end, maps:values(Receipts)) orelse
        case Buffered of {Route, _, _} -> Owns(Route); none -> false end.

retire_session(Session, State = #state{sessions = Sessions, routes = Routes,
        queued = Queued, active = Active, receipts = Receipts}) ->
    #session{monitor = Monitor} = maps:get(Session, Sessions),
    demonitor(Monitor, [flush]),
    Retired = [Route || {Route, #route_owner{session = S}} <- maps:to_list(Routes), S =:= Session],
    NewRoutes = lists:foldl(fun(Route, Acc) ->
        #route_owner{monitor = Ref} = maps:get(Route, Acc),
        demonitor(Ref, [flush]), Acc#{Route := retired}
    end, Routes, Retired),
    {Abandoned, Remaining} = lists:partition(fun(#tx{session = S}) -> S =:= Session end,
        queue:to_list(Queued)),
    [complete(Tx, {error, {not_sent, session_closed}}) || Tx <- Abandoned],
    NextActive = case Active of
        #tx{session = Session} = Tx ->
            case Tx#tx.from of
                none -> ok;
                From -> gen_server:reply(From, {error, {transport_down, session_closed}})
            end,
            Tx#tx{from = none};
        _ -> Active
    end,
    pump_rx(State#state{sessions = maps:remove(Session, Sessions), routes = NewRoutes,
        queued = queue:from_list(Remaining), active = NextActive,
        receipts = maps:filter(fun(_Receipt, {_Owner, Route}) ->
            not lists:member(Route, Retired)
        end, Receipts)}).

pump_rx(State = #state{buffered = {Route, Header, Payload}, routes = Routes, receipts = Receipts,
        rx_limit = Limit, rx_route_limit = RouteLimit}) ->
    case Routes of
        #{Route := #route_owner{pid = Owner}} ->
            Outstanding = length([ok || {_, R} <- maps:values(Receipts), R =:= Route]),
            case map_size(Receipts) < Limit andalso Outstanding < RouteLimit of
                false -> State;
                true ->
                    Receipt = make_ref(),
                    gen_server:cast(Owner, {'$hls_fabric_frame', Receipt, Route, Header, Payload}),
                    pump_rx(count(received, State#state{buffered = none,
                        receipts = Receipts#{Receipt => {Owner, Route}}}))
            end;
        _ -> pump_rx(count(discarded, State#state{buffered = none}))
    end;
pump_rx(State = #state{buffered = none, reading = false, reader = Reader,
        receipts = Receipts, rx_limit = Limit}) when map_size(Receipts) < Limit ->
    Reader ! read,
    State#state{reading = true};
pump_rx(State) -> State.

count(Key, State = #state{counts = Counts}) -> State#state{counts = Counts#{Key := maps:get(Key, Counts) + 1}}.

snapshot(State = #state{lease = Lease, reader = Reader, writer = Writer, sessions = Sessions, routes = Routes, queued = Queued, active = Active, writer_ready = Ready,
        reading = Reading, buffered = Buffered, receipts = Receipts, counts = Counts,
        tx_limit = TxLimit, tx_route_limit = TxRouteLimit, rx_limit = RxLimit, rx_route_limit = RxRouteLimit}) ->
    RouteInfo = maps:map(fun
        (_Route, retired) -> retired;
        (Route, #route_owner{pid = Owner}) ->
            #{owner => Owner, outstanding => length([ok || {_, R} <- maps:values(Receipts), R =:= Route])}
    end, Routes),
    ActiveInfo = case Active of
        none -> none;
        #tx{route = Route, bytes = Bytes, deadline = Deadline} ->
            #{route => Route, bytes => byte_size(Bytes), deadline => Deadline}
    end,
    #{device => self(), io => #{lease => Lease, reader => Reader, writer => Writer},
        sessions => maps:map(fun(_Pid, #session{status = Status}) -> Status end, Sessions),
        tx => #{capacity => TxLimit, route_capacity => TxRouteLimit, queued => queue:len(Queued),
            active => ActiveInfo, writer_ready => Ready,
            per_route => lists:foldl(fun(#tx{route = R}, Acc) ->
                maps:update_with(R, fun(N) -> N + 1 end, 1, Acc)
            end, #{}, transactions(State))},
        rx => #{capacity => RxLimit, route_capacity => RxRouteLimit,
            outstanding => map_size(Receipts), reading => Reading,
            buffered => case Buffered of none -> none; {R, _, _} -> R end},
        routes => RouteInfo, counts => Counts}.

terminate(Reason, #state{writer = Writer, reader = Reader, queued = Queued, active = Active}) ->
    %% The workers finish any raw operation before closing their descriptors.
    %% Their lease remains held until both explicitly confirm closure.
    [complete(Tx, {error, {not_sent, {transport_down, Reason}}}) || Tx <- queue:to_list(Queued)],
    case Active of none -> ok; _ -> complete(Active, {error, {transport_down, Reason}}) end,
    [Pid ! stop || Pid <- [Writer, Reader]],
    ok.
