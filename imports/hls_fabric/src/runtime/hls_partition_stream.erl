-module(hls_partition_stream).
-moduledoc """
Application clients open this legacy partition connection over existing brokers. The process uses hls_partition_wire for retained codecs and owns control admission, event buffering and closure.

One owner's bounded, ordered control/event connection to a partition.

Attachment verifies both gateways before returning. Submission acknowledges
host queue admission, not device execution. Submitting `start` orders activation
after earlier setup; `{ok, Device, application, {started}}` confirms the device
accepted activation. It is not a global barrier or a completion fence for later work.
`next/2` releases receive credit
only when returning an event; its timeout cannot abandon a later reply.
Transport or protocol failure ends the connection without replay. Stopping
retires its routes but does not reset hardware: replacement requires a reset
covering both graphs, gateways, links and transport buffers.
""".
-behaviour(gen_server).
%% Public partition-session API.
-export([start_link/3, submit/2, next/2, info/1, stop/1]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-doc "Attaches one broker per device for the calling owner. Options are queue_limit (128 frames) and write_timeout (10000 ms).".
-spec start_link(map(), #{term() => pid()}, map()) -> {ok, pid()} | {error, term()}.
start_link(Deployment, Brokers, Options) ->
    gen_server:start_link(?MODULE, {self(), Deployment, Brokers, Options}, []).

-doc "Admits a whole command batch or returns busy before sending any part. start is single-use per explicit-start connection; its admission does not acknowledge activation. Delivery across devices is not atomic.".
-spec submit(pid(), hls_partition_wire:command()) -> {ok, non_neg_integer()} | {error, term()}.
submit(Pid, Command) -> gen_server:call(Pid, {submit, Command}, infinity).

-doc "Returns the next event or timeout after the given milliseconds; only the connection owner may consume.".
-spec next(pid(), non_neg_integer()) -> {ok, term(), term(), tuple()} | timeout | {error, term()}.
next(Pid, Timeout) when is_integer(Timeout), Timeout >= 0 ->
    gen_server:call(Pid, {next, Timeout}, infinity).

-doc "Reports host queue/receipt occupancy, write/event counts and per-device activation state without device traffic. Only a canonical started reply marks running.".
-spec info(pid()) -> map().
info(Pid) -> gen_server:call(Pid, info).

-doc "Retires this connection's routes and queued commands; leaves deployment-owned brokers open.".
-spec stop(pid()) -> ok.
stop(Pid) -> gen_server:stop(Pid).

-doc "Validates all bindings, reserves routes and verifies each device before accepting owner work.".
-spec init({pid(), map(), map(), map()}) -> {ok, map()} | {stop, term()}.
init({Owner, Deployment = #{devices := Devices}, Brokers, Options}) ->
    process_flag(trap_exit, true),
    Defaults = #{queue_limit => 128, write_timeout => 10000},
    true = maps:without(maps:keys(Defaults), Options) =:= #{},
    true = lists:all(fun(V) -> is_integer(V) andalso V > 0 end, maps:values(Options)),
    true = lists:sort(maps:keys(Devices)) =:= lists:sort(maps:keys(Brokers)),
    true = length(lists:usort(maps:values(Brokers))) =:= map_size(Brokers),
    ok = hls_partition_wire:check(Deployment),
    Settings = maps:merge(Defaults, Options),
    Sessions = open_sessions(lists:sort(maps:to_list(Brokers)), #{}),
    try
        Routes = maps:fold(
            fun(D, #{host := Host, control := Control, events := Events}, Acc) ->
                Session = maps:get(D, Sessions),
                lists:foldl(
                    fun(Endpoint, A) ->
                        Route = {Endpoint, Host},
                        ok = hls_fabric:register_route(Session, Route, self()),
                        A#{Route => {D, Session}}
                    end,
                    Acc,
                    [Control | maps:keys(Events)]
                )
            end,
            #{},
            Devices
        ),
        maps:foreach(
            fun(D, Binding) ->
                attach(maps:get(D, Sessions), Binding, maps:get(write_timeout, Settings))
            end,
            Devices
        ),
        Monitor = monitor(process, Owner),
        {ok, Settings#{
            owner => Owner,
            owner_monitor => Monitor,
            deployment => Deployment,
            sessions => Sessions,
            routes => Routes,
            queues => maps:map(fun(_, _) -> queue:new() end, Devices),
            activation => maps:map(
                fun(_, B) ->
                    case maps:get(activation, B, automatic) of
                        explicit_start -> configured;
                        automatic -> automatic
                    end
                end,
                Devices
            ),
            active => #{},
            pending => 0,
            events => queue:new(),
            waiter => none,
            written => 0,
            received => 0,
            delivered => 0
        }}
    catch
        Class:Reason ->
            close_sessions(Sessions),
            {stop, {attachment_failed, Class, Reason}}
    end.

%% Close earlier reservations if opening a later logical session fails.
-spec open_sessions([{term(), pid()}], map()) -> map().
open_sessions([], Sessions) ->
    Sessions;
open_sessions([{Device, Broker} | Rest], Sessions) ->
    case hls_fabric:open_session(Broker) of
        {ok, Session} ->
            open_sessions(Rest, Sessions#{Device => Session});
        Error ->
            close_sessions(Sessions),
            error({session_open, Device, Error})
    end.

%% Attachment is a single-use identity check, not an application completion fence.
-spec attach(pid(), map(), pos_integer()) -> ok.
attach(Session, #{host := Host, control := Control, identity := Identity}, Timeout) ->
    ok = hls_fabric:send(Session, {Host, Control}, {1, 0, 0}, Identity, Timeout),
    receive
        {'$gen_cast', {'$hls_fabric_frame', Receipt, {Control, Host}, Header, Payload}} ->
            ok = hls_fabric:ack(Session, Receipt),
            case {Header, Payload} of
                {{16#81, 0, 0}, Identity} -> ok;
                Other -> error({identity_response, Other})
            end;
        {'EXIT', Session, Reason} ->
            error({session_down, Reason})
    after Timeout -> error(attachment_timeout)
    end.

-doc "Admits owner commands, delivers credited events and reports responsive host status.".
-spec handle_call(term(), gen_server:from(), map()) -> {reply, term(), map()} | {noreply, map()}.
%% Inspection remains available while writes or the event consumer are stalled.
handle_call(info, _From, State = #{events := Events}) ->
    {reply,
        (maps:with([pending, written, received, delivered, activation], State))#{
            buffered => queue:len(Events)
        },
        State};
%% Foreign callers cannot consume another owner's data or order its commands.
handle_call(_Request, {Caller, _}, State = #{owner := Owner}) when Caller =/= Owner ->
    {reply, {error, not_owner}, State};
%% Validate and reserve the complete batch before any device receives a frame.
handle_call(
    {submit, Command},
    _From,
    State = #{deployment := Deployment, pending := Pending, queue_limit := Limit}
) ->
    Checked =
        try
            ok = admit_start(Command, maps:get(activation, State)),
            {ok, hls_partition_wire:command(Deployment, Command)}
        catch
            error:Reason -> {error, {invalid_command, Reason}}
        end,
    case Checked of
        {ok, Packets} when length(Packets) + Pending =< Limit ->
            Admitted =
                case Command of
                    start ->
                        State#{
                            activation := maps:map(
                                fun(_, _) -> start_pending end, maps:get(activation, State)
                            )
                        };
                    _ ->
                        State
                end,
            Next = lists:foldl(fun enqueue/2, Admitted, Packets),
            {reply, {ok, length(Packets)}, pump(Next)};
        {ok, _} ->
            {reply, {error, busy}, State};
        Error ->
            {reply, Error, State}
    end;
%% A server-owned timer returns timeout without leaving an orphaned future event reply.
handle_call({next, Timeout}, From, State = #{waiter := none}) ->
    Timer = erlang:start_timer(Timeout, self(), next),
    {noreply, deliver(State#{waiter := {From, Timer}})};
%% Permit only one pending receive, even if an owner uses the raw OTP interface.
handle_call({next, _}, _From, State) ->
    {reply, {error, already_waiting}, State};
%% Unknown requests do not disturb the live activation.
handle_call(_, _From, State) ->
    {reply, {error, bad_request}, State}.

-doc "Retains each valid frame's broker receipt until the owner consumes it; protocol errors terminate the activation.".
-spec handle_cast(term(), map()) -> {noreply, map()} | {stop, term(), map()}.
%% Route ownership supplies device identity; application effects are unsolicited records.
handle_cast(
    {'$hls_fabric_frame', Receipt, Route, Header, Payload},
    State = #{
        routes := Routes, deployment := #{devices := Devices}, events := Events, received := Count
    }
) ->
    {Device, Session} = maps:get(Route, Routes),
    try
        {Stream0, Event0} = hls_partition_wire:event(
            maps:get(Device, Devices), Route, Header, Payload
        ),
        {Stream0, Event0, accept_start(Device, Route, Header, State)}
    of
        {Stream, Event, Accepted} ->
            Next = Accepted#{
                events := queue:in({Device, Stream, Event, Session, Receipt}, Events),
                received := Count + 1
            },
            {noreply, deliver(Next)}
    catch
        error:Reason ->
            ok = hls_fabric:ack(Session, Receipt),
            {stop, {invalid_event, Device, Header, Reason}, State}
    end;
%% No other cast is part of this connection's API.
handle_cast(_, State) ->
    {noreply, State}.

-doc "Completes writes, bounds receive waits, retries proven non-transmission and aborts lost ownership.".
-spec handle_info(term(), map()) -> {noreply, map()} | {stop, term(), map()}.
%% A timeout returns no event and releases the receive request before any later event arrives.
handle_info({timeout, Timer, next}, State = #{waiter := {From, Timer}}) ->
    gen_server:reply(From, timeout),
    {noreply, State#{waiter := none}};
%% Obsolete receive timers cannot affect the next request.
handle_info({timeout, _, next}, State) ->
    {noreply, State};
%% Capacity retries keep the same frame at the head with its original deadline.
handle_info(retry, State) ->
    {noreply, pump(State)};
%% Caller death abandons the whole connection, including all retained receipts.
handle_info({'DOWN', Monitor, process, _Owner, _Reason}, State = #{owner_monitor := Monitor}) ->
    {stop, normal, State};
%% A lost broker/session leaves delivery uncertain; no accepted work is replayed.
handle_info({'EXIT', _Session, Reason}, State) ->
    {stop, {connection_down, Reason}, State};
%% Asynchronous broker replies permit event consumption while a physical write stalls.
handle_info(Message, State = #{active := Active}) ->
    response(Message, maps:to_list(Active), State).

-doc "Retires logical sessions without closing deployment-owned device brokers.".
-spec terminate(term(), map()) -> ok.
terminate(_Reason, #{sessions := Sessions}) -> close_sessions(Sessions).

%% Bound queued plus in-flight frames together; each device keeps its original ordering.
-spec enqueue({term(), hls_fabric:route(), hls_fabric:header(), binary()}, map()) -> map().
enqueue(
    {Device, Route, Header, Payload},
    State = #{queues := Queues, pending := Count, write_timeout := Timeout}
) ->
    Frame = {Route, Header, Payload, {abs, erlang:monotonic_time(millisecond) + Timeout}},
    State#{
        queues := Queues#{Device := queue:in(Frame, maps:get(Device, Queues))}, pending := Count + 1
    }.

%% At most one physical write per device can be outstanding from this connection.
-spec pump(map()) -> map().
pump(State = #{sessions := Sessions}) -> maps:fold(fun pump_device/3, State, Sessions).

%% Transfer a device's queue head to the broker while preserving the frame for a safe retry.
-spec pump_device(term(), pid(), map()) -> map().
pump_device(Device, Session, State = #{active := Active, queues := Queues}) ->
    case {maps:is_key(Device, Active), queue:out(maps:get(Device, Queues))} of
        {false, {{value, Frame = {Route, Header, Payload, Deadline}}, Rest}} ->
            Request = hls_fabric:send_request(Session, Route, Header, Payload, Deadline),
            State#{
                active := Active#{Device => {Request, Frame}}, queues := Queues#{Device := Rest}
            };
        _ ->
            State
    end.

%% Match each broker's OTP request without confusing owner/session monitor messages.
-spec response(term(), [{term(), tuple()}], map()) -> {noreply, map()} | {stop, term(), map()}.
response(_Message, [], State) ->
    {noreply, State};
response(
    Message,
    [{Device, {Request, Frame}} | Rest],
    State = #{
        active := Active,
        pending := Pending,
        queues := Queues,
        written := Written
    }
) ->
    Next = State#{active := maps:remove(Device, Active)},
    case gen_server:check_response(Message, Request) of
        {reply, ok} ->
            {noreply, pump(Next#{pending := Pending - 1, written := Written + 1})};
        {reply, {error, {not_sent, Reason}}} when
            Reason =:= tx_limit;
            is_tuple(Reason), element(1, Reason) =:= route_tx_limit
        ->
            erlang:send_after(5, self(), retry),
            {noreply, Next#{
                queues := Queues#{Device := queue:in_r(Frame, maps:get(Device, Queues))}
            }};
        no_reply ->
            response(Message, Rest, State);
        Error ->
            {stop, {write_failed, Device, Error}, Next}
    end.

%% Release exactly one receipt after handing its decoded event to the owner.
-spec deliver(map()) -> map().
deliver(State = #{waiter := {From, Timer}, events := Events, delivered := Count}) ->
    case queue:out(Events) of
        {{value, {Device, Stream, Event, Session, Receipt}}, Rest} ->
            erlang:cancel_timer(Timer),
            gen_server:reply(From, {ok, Device, Stream, Event}),
            ok = hls_fabric:ack(Session, Receipt),
            State#{events := Rest, waiter := none, delivered := Count + 1};
        {empty, _} ->
            State
    end;
deliver(State) ->
    State.

%% Session retirement discards late frames and cancels only writes which have not begun.
-spec close_sessions(map()) -> ok.
close_sessions(Sessions) ->
    maps:foreach(fun(_, Session) -> catch hls_fabric:stop(Session) end, Sessions),
    ok.

%% Duplicate start is rejected before queue admission; ordinary commands remain ordered.
-spec admit_start(hls_partition_wire:command(), map()) -> ok.
admit_start(start, Activation) ->
    case
        map_size(Activation) > 0 andalso
            lists:all(fun(S) -> S =:= configured end, maps:values(Activation))
    of
        true -> ok;
        false -> error(start_unavailable)
    end;
admit_start(_, _) ->
    ok.

%% A write receipt cannot mark running; only the bound control route can.
-spec accept_start(term(), hls_fabric:route(), hls_fabric:header(), map()) -> map().
accept_start(
    Device, Route, Header, State = #{activation := Activation, deployment := #{devices := Devices}}
) ->
    #{host := Host, control := Control} = maps:get(Device, Devices),
    case {Route, Header} of
        {{Control, Host}, {16#83, 0, 0}} ->
            case maps:get(Device, Activation) of
                start_pending -> State#{activation := Activation#{Device := running}};
                _ -> error(unexpected_start_response)
            end;
        _ ->
            State
    end.
