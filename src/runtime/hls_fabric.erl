-module(hls_fabric).
-moduledoc """
Owns one routed frame transport with bounded transmit admission and receive
credits. Application and debug streams use separate brokers. Blocking raw I/O
runs in two linked workers, leaving route ownership, deadlines, and inspection
responsive when either physical direction stalls.

`send/4` waits for write completion; `send_request/5` uses OTP's asynchronous
request interface. A `{not_sent, Reason}` rejection guarantees that this frame
never reached the writer. Failure after writing starts is ambiguous and closes
the transport. No operation is retried. A write does not prove device admission.

Each delivered cast is `{'$hls_fabric_frame', Receipt, Route, Header, Payload}`.
The registered owner must call `ack/2` after processing it. Receipts are single
use and owner-specific. A slow route eventually blocks the shared receive
stream; it cannot accumulate an unbounded number of frames in its mailbox.
The route remains transport metadata, not an actor-message sender identity.

Routes are retired when their owners exit. Reuse requires a fresh, drained or
reset transport session; see `docs/host-transactions.md`.
""".

-behavior(gen_server).

-export([start_link/2, start_link/3, stop/1]).
-export([register_route/3, send/4, send/5, send_request/5, ack/2, info/1, client_info/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-type endpoint() :: 0..65535.
-type route() :: {endpoint(), endpoint()}.
-type header() :: {byte(), byte(), byte()}.
-type deadline() :: timeout() | {abs, integer()}.
-export_type([route/0, header/0, deadline/0]).

-record(route_owner, {pid :: pid(), monitor :: reference()}).
-record(tx, {
    id :: reference(),
    from :: gen_server:from() | none,
    monitor :: reference(),
    timer :: reference() | none,
    deadline :: integer() | infinity,
    route :: route(),
    bytes :: binary()
}).
-record(state, {
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

stop(Pid) -> gen_server:stop(Pid).

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
            Broker = self(),
            Writer = spawn_link(fun() -> hls_fabric_io:writer(WritePath, Broker) end),
            Reader = spawn_link(fun() -> hls_fabric_io:reader(ReadPath, Broker) end),
            {ok, pump_rx(#state{writer = Writer, reader = Reader,
                tx_limit = Tx, tx_route_limit = TxRoute, rx_limit = Rx, rx_route_limit = RxRoute})}
    end.

handle_call({register_route, Route, Owner}, _From, State = #state{routes = Routes})
        when is_pid(Owner) ->
    case {hls_fabric_io:valid_route(Route), Routes} of
        {true, #{Route := #route_owner{pid = Owner}}} ->
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
            Entry = #route_owner{pid = Owner, monitor = monitor(process, Owner)},
            {reply, ok, State#state{routes = Routes#{Route => Entry}}};
        {false, _} -> {reply, {error, {invalid_route, Route}}, State}
    end;
handle_call({send, Route, Header, Payload, Deadline}, From, State)
        when is_integer(Deadline); Deadline =:= infinity ->
    case hls_fabric_io:encode(Route, Header, Payload) of
        {error, Reason} -> reject(Reason, State);
        {ok, Bytes} -> admit(Route, Bytes, Deadline, From, State)
    end;
handle_call(info, _From, State) -> {reply, snapshot(State), State};
handle_call(Request, _From, State) -> {reply, {error, {invalid_request, Request}}, State}.

handle_cast({ack, Owner, Receipt}, State = #state{receipts = Receipts}) ->
    case Receipts of
        #{Receipt := {Owner, _Route}} ->
            {noreply, pump_rx(State#state{receipts = maps:remove(Receipt, Receipts)})};
        _ -> {noreply, count(ignored_acks, State)}
    end;
handle_cast(_Message, State) -> {noreply, State}.

handle_info({writer_ready, Writer}, State = #state{writer = Writer}) ->
    {noreply, pump_tx(State#state{writer_ready = true})};
handle_info({written, Writer, ID, ok},
        State = #state{writer = Writer, active = #tx{id = ID, deadline = Deadline, route = Route} = Tx}) ->
    case expired(Deadline) of
        false ->
            complete(Tx, ok),
            {noreply, pump_tx(count(written, State#state{active = none}))};
        true ->
            complete(Tx, {error, {write_timeout, Route}}),
            {stop, {write_timeout, Route}, State#state{active = none}}
    end;
handle_info({written, Writer, ID, {error, Reason}},
        State = #state{writer = Writer, active = #tx{id = ID} = Tx}) ->
    complete(Tx, {error, Reason}),
    {stop, {write_failed, Reason}, State#state{active = none}};
handle_info({timeout, Timer, ID}, State = #state{active = #tx{id = ID, timer = Timer, route = Route} = Tx}) ->
    complete(Tx, {error, {write_timeout, Route}}),
    {stop, {write_timeout, Route}, State#state{active = none}};
handle_info({timeout, Timer, ID}, State = #state{queued = Queued}) ->
    {Expired, Remaining} = lists:partition(fun(#tx{id = Ref, timer = T}) ->
        Ref =:= ID andalso T =:= Timer
    end, queue:to_list(Queued)),
    [complete(Tx, {error, {not_sent, timeout}}) || Tx <- Expired],
    Next = lists:foldl(fun(_, Acc) -> count(expired, Acc) end,
        State#state{queued = queue:from_list(Remaining)}, Expired),
    {noreply, pump_tx(Next)};
handle_info({received, Reader, Route, Header, Payload}, State = #state{reader = Reader, reading = true}) ->
    {noreply, pump_rx(State#state{reading = false, buffered = {Route, Header, Payload}})};
handle_info({'DOWN', Monitor, process, Owner, _Reason}, State) ->
    case owns_monitor(Monitor, State) of
        true -> {noreply, pump_tx(retire(Owner, State))};
        false -> {noreply, State}
    end;
handle_info({'EXIT', Writer, Reason}, State = #state{writer = Writer}) ->
    {stop, {writer_down, Reason}, State};
handle_info({'EXIT', Reader, Reason}, State = #state{reader = Reader}) ->
    {stop, {reader_down, Reason}, State};
handle_info(_Message, State) -> {noreply, State}.

admit(Route, Bytes, Deadline, From = {Owner, _}, State = #state{
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
            Tx = #tx{id = ID, from = From, monitor = monitor(process, Owner), timer = Timer,
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

snapshot(State = #state{routes = Routes, queued = Queued, active = Active, writer_ready = Ready,
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
    #{tx => #{capacity => TxLimit, route_capacity => TxRouteLimit, queued => queue:len(Queued),
            active => ActiveInfo, writer_ready => Ready,
            per_route => lists:foldl(fun(#tx{route = R}, Acc) ->
                maps:update_with(R, fun(N) -> N + 1 end, 1, Acc)
            end, #{}, transactions(State))},
        rx => #{capacity => RxLimit, route_capacity => RxRouteLimit,
            outstanding => map_size(Receipts), reading => Reading,
            buffered => case Buffered of none -> none; {R, _, _} -> R end},
        routes => RouteInfo, counts => Counts}.

terminate(Reason, #state{writer = Writer, reader = Reader, queued = Queued, active = Active}) ->
    %% Killing a worker cannot undo bytes already transferred by a blocked OS
    %% call. The stream must be drained/reset before a replacement is opened.
    [complete(Tx, {error, {not_sent, {transport_down, Reason}}}) || Tx <- queue:to_list(Queued)],
    case Active of none -> ok; _ -> complete(Active, {error, {transport_down, Reason}}) end,
    [begin unlink(Pid), exit(Pid, kill) end || Pid <- [Writer, Reader]],
    ok.
