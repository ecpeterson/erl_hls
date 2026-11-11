-module(hls_node_connection).
-moduledoc """
hls_node_connections owns one worker per distribution peer. The worker uses hls_node_wire for framing and hls_node for service routing, monitors and incarnation retirement.
""".
-behaviour(gen_server).
%% Connection supervision entry.
-export([start_link/2]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, format_status/1]).

-export_type([carrier/0]).
-doc "An accepted TCP socket or a local distribution owner with node identity.".
-type carrier() ::
    gen_tcp:socket() | {local, pid(), #{name := node(), creation := non_neg_integer()}}.
%% Physical service channel shared by its logical actor PIDs.
-type channel_key() :: {application | debug, 0..((1 bsl 16) - 1)}.
%% Calls carry their reply destination; casts need no reply slot.
-type operation() :: {call, gen_server:from(), term()} | {cast, none, term()}.

-doc "Starts an adapter for a TCP socket or local distribution owner. TCP ownership must transfer before connected is sent.".
-spec start_link(pid(), carrier()) -> gen_server:start_ret().
start_link(Manager, Socket) -> gen_server:start_link(?MODULE, {Manager, Socket}, []).
-doc "Initializes connection state; local owner death terminates the connection.".
-spec init({pid(), carrier()}) -> {ok, map()}.
init({Manager, {local, Owner, Identity}}) ->
    link(Owner),
    Ref = monitor(process, Owner),
    {ok, #{
        manager => Manager,
        socket => local,
        identity => Identity,
        handshake => hls_node_wire:handshake_start(Identity, erlang:get_cookie()),
        handshake_packets => [],
        owner_monitor => Ref,
        received => 0,
        sent => 0
    }};
init({Manager, Socket}) ->
    {ok, #{manager => Manager, socket => Socket}}.

-doc "Removes the handshake cookie from gen_server status reports.".
-spec format_status(map()) -> map().
format_status(Status = #{state := #{handshake := Handshake} = State}) ->
    Status#{state := State#{handshake := maps:remove(cookie, Handshake)}};
format_status(Status) ->
    Status.

-doc "Serves local handshake, connection statistics and diagnostic queries.".
-spec handle_call(term(), gen_server:from(), map()) -> {reply, term(), map()}.
%% Advance the incoming side of the local handshake.
handle_call(
    {handshake_send, Packet}, _From, State = #{handshake := Handshake, handshake_packets := []}
) ->
    {Packets, Next} = hls_node_wire:handshake_step(iolist_to_binary(Packet), Handshake),
    {reply, ok, State#{handshake := Next, handshake_packets := Packets}};
%% Return the next queued handshake response.
handle_call(handshake_recv, _From, State = #{handshake_packets := [Packet | Rest]}) ->
    {reply, {ok, binary_to_list(Packet)}, State#{handshake_packets := Rest}};
%% Attach authenticated local distribution and begin bounded admission.
handle_call(
    {local_up, Handle},
    _From,
    State = #{handshake := #{phase := up, peer := Peer}, identity := Identity}
) ->
    ok = erlang:dist_ctrl_input_handler(Handle, self()),
    Next = attach(
        Peer,
        Identity,
        maps:without([handshake, handshake_packets, identity], State#{socket := {local, Handle}})
    ),
    {reply, ok, arm(Next)};
%% Report carrier progress to ERTS liveness checks.
handle_call(local_stats, _From, State = #{received := Received, sent := Sent}) ->
    {reply, {ok, Received, Sent, 0}, State};
%% Source mode retains at most one distribution handoff until its central owner accepts it.
handle_call(info, _From, State = #{source_pending := Pending, clients := Clients}) ->
    {reply, #{carrier => carrier(State), source_pending => Pending, clients => map_size(Clients)},
        State};
%% Expose per-channel pending and transmitting observations.
handle_call(info, _From, State = #{clients := Clients, queues := Queues, channels := Channels}) ->
    {reply,
        #{
            carrier => carrier(State),
            queued => queued(Queues),
            domain_pending => maps:get(domain_pending, State, 0),
            clients => maps:map(
                fun(_, C) -> client_info(C, Channels) end,
                Clients
            )
        },
        State}.
%% The peer is the adapter in this process; a serviced heartbeat proves it
%% is alive even while device admission pauses the distribution data stream.
-doc "Services local heartbeats and acknowledges device frames after processing.".
-spec handle_cast(term(), map()) -> {noreply, map()}.
%% Publication waits for actual old endpoint DOWN signals, preserving preceding replies.
handle_cast({domain_publish, Ref, Old, Targets}, State = #{domain_publication := none}) ->
    {noreply,
        install_domain(State#{
            domain_publication := #{reference => Ref, old => Old, targets => Targets}
        })};
%% A serviced local heartbeat establishes that this adapter is alive.
handle_cast(local_tick, State = #{received := N}) ->
    {noreply, State#{received := N + 1}};
%% Process one device frame before acknowledging broker delivery.
handle_cast({'$hls_fabric_frame', Receipt, Route, Header, Payload}, State = #{routes := Routes}) ->
    #{Route := {Key, Broker}} = Routes,
    Next = frame(Key, Header, Payload, State),
    hls_fabric:ack(Broker, Receipt),
    continue(Next).

-doc "Processes distribution traffic, broker completions, retries and connection failure.".
-spec handle_info(term(), map()) -> {noreply, map()} | {stop, term(), map()}.
%% Authenticate a socket after ownership transfer, then attach its routes.
handle_info(connected, State = #{manager := Manager, socket := Socket}) ->
    Identity = gen_server:call(Manager, handshake),
    Peer = hls_node_wire:handshake(Socket, Identity, erlang:get_cookie()),
    Next = attach(Peer, Identity, State),
    #{config := #{tick_ms := Tick}} = Next,
    erlang:send_after(Tick, self(), tick),
    continue(Next);
%% Stop when the local distribution owner exits.
handle_info({'DOWN', Ref, process, _Owner, Reason}, State = #{owner_monitor := Ref}) ->
    {stop, {connection_owner_down, Reason}, State};
%% The central source owner cannot be replaced while this incarnation is live.
handle_info({'DOWN', Ref, process, _Owner, Reason}, State = #{source_monitor := Ref}) ->
    {stop, {source_owner_down, Reason}, State};
%% A managed endpoint's native monitor retires only that virtual actor and its remote monitors.
handle_info({'DOWN', Ref, process, _Endpoint, Reason}, State = #{domain_monitors := Monitors}) when
    is_map_key(Ref, Monitors)
->
    Pid = maps:get(Ref, Monitors),
    Next = retire_domain(Pid, Reason, State#{domain_monitors := maps:remove(Ref, Monitors)}),
    continue(install_domain(Next));
%% Consume one local distribution packet under the same queue bound as TCP.
handle_info(dist_data, State = #{socket := {local, Handle}, sent := Sent}) ->
    case erlang:dist_ctrl_get_data(Handle) of
        none ->
            continue(State#{armed := false});
        Data ->
            true = iolist_size(Data) =< 1048576,
            {Control, Message} = hls_node_wire:decode(iolist_to_binary(Data)),
            continue(signal(Control, Message, State#{armed := false, sent := Sent + 1}))
    end;
%% Answer a TCP heartbeat.
handle_info({tcp, Socket, <<>>}, State = #{socket := Socket}) ->
    continue(send(State#{armed := false, last_received := now_ms()}, <<>>));
%% Decode one admitted TCP distribution packet.
handle_info({tcp, Socket, Packet}, State = #{socket := Socket}) ->
    {Control, Message} = hls_node_wire:decode(Packet),
    continue(signal(Control, Message, State#{armed := false, last_received := now_ms()}));
%% End the connection when its peer closes TCP.
handle_info({tcp_closed, Socket}, State = #{socket := Socket}) ->
    {stop, normal, State};
%% Surface a TCP transport error.
handle_info({tcp_error, Socket, Reason}, State = #{socket := Socket}) ->
    {stop, {tcp, Reason}, State};
%% Retry operations previously refused without transmission.
handle_info(retry, State) ->
    continue(State#{retry := false});
%% Probe TCP liveness, excluding intervals when local admission pauses reads.
handle_info(
    tick,
    State = #{
        config := #{tick_ms := Tick},
        last_received := Last,
        armed := Armed
    }
) ->
    case Armed andalso now_ms() - Last > 4 * Tick of
        true ->
            {stop, net_tick_timeout, State};
        false ->
            %% Paused input is transport backpressure, not evidence of peer
            %% failure. Writes still detect a closed connection in this state.
            erlang:send_after(Tick, self(), tick),
            {noreply, send(State, <<>>)}
    end;
%% Complete asynchronous broker sends; broker failure ends the connection.
handle_info(Message, State = #{sends := Sends}) ->
    case gen_server:check_response(Message, Sends, true) of
        {{reply, Result}, Label, Remaining} ->
            continue(written(Label, Result, State#{sends := Remaining}));
        {{error, {_Reason, _}}, {domain_request, _Pid, _Mode, _From}, Remaining} ->
            %% The endpoint's own DOWN is authoritative; never turn death into an ordinary reply.
            continue(domain_completed(State#{sends := Remaining}));
        {{error, {Reason, _}}, _, _} ->
            {stop, {broker_down, Reason}, State};
        _ ->
            {noreply, State}
    end.

%% Reserve fresh return routes and build this peer's PID/channel indexes.
-spec attach(node(), map(), map()) -> map().
attach(Peer, Identity, State = #{manager := Manager}) ->
    Attachment = gen_server:call(Manager, {attach, Peer, carrier(State)}),
    attach_mode(Attachment, Peer, Identity, State).

%% Source mode uses one bounded owner handoff and no scheduler-slot channel or transaction router.
-spec attach_mode(tuple(), node(), map(), map()) -> map().
attach_mode(
    {source, Owner, Actors = [#{senders := Senders} | _], Config},
    Peer,
    #{name := Name, creation := Creation},
    State
) ->
    State#{
        peer => Peer,
        kernel_pid => hls_node_wire:pid(Name, Creation, 0),
        clients => maps:from_list([{Pid, A} || A = #{pid := Pid} <- Actors]),
        names => #{},
        channels => #{},
        routes => #{},
        queues => #{},
        sends => gen_server:reqids_new(),
        monitors => #{},
        config => Config,
        source_owner => Owner,
        source_monitor => monitor(process, Owner),
        source_senders => maps:from_list([{P, true} || P <- Senders]),
        source_pending => false,
        armed => false,
        retry => false,
        last_received => now_ms()
    };
attach_mode({ok, Brokers, Actors, Source, Config}, Peer, Identity, State) ->
    Clients = maps:from_list([{Pid, Actor} || #{pid := Pid} = Actor <- Actors]),
    Channels = maps:from_list([
        {Key, channel(Key, Brokers, Source)}
     || Key <- lists:usort(
            [Key || #{channel := Key} <- Actors]
        )
    ]),
    Routes = maps:from_list([
        {Route, {Key, Broker}}
     || {Key, #{route := Route, broker := Broker}} <- maps:to_list(Channels)
    ]),
    Names = maps:from_list([
        {Name, Pid}
     || #{name := Name, kind := application, pid := Pid} <- Actors
    ]),
    #{name := Name, creation := Creation} = Identity,
    State#{
        peer => Peer,
        kernel_pid => hls_node_wire:pid(Name, Creation, 0),
        clients => Clients,
        domain_monitors => monitor_domains(Actors),
        domain_pending => 0,
        domain_publication => none,
        channels => Channels,
        routes => Routes,
        names => Names,
        queues => #{},
        sends => gen_server:reqids_new(),
        monitors => #{},
        config => Config,
        armed => false,
        retry => false,
        last_received => now_ms()
    }.

%% Initialize request tracking for one application or debug channel.
-spec channel(channel_key(), hls_node:brokers(), pos_integer()) -> map().
channel({Kind, Endpoint}, Brokers, Source) ->
    Offset =
        case Kind of
            application -> 0;
            debug -> 1
        end,
    #{
        broker => maps:get(Kind, Brokers),
        route => {Endpoint, Source + Offset},
        pending => #{},
        next => 0,
        transmitting => false,
        ignored_replies => 0
    }.

%% Monitor signals are handled separately from the FPGA's data-plane queue.
%% PIDs belong to the node incarnation; monitors belong to this connection.
%% Dispatch negotiated distribution signals; reject unsupported operations.
-spec signal(tuple(), none | {message, term()}, map()) -> map().
signal({19, From, To, Ref}, none, State = #{monitors := Monitors}) ->
    case target(To, State) of
        none -> send(State, hls_node_wire:encode({21, To, From, Ref, noproc}));
        _ -> State#{monitors := Monitors#{Ref => {From, To}}}
    end;
signal({20, _From, _To, Ref}, none, State = #{monitors := Monitors}) ->
    State#{monitors := maps:remove(Ref, Monitors)};
signal({35, ID, From, To}, none, State) ->
    send(State, hls_node_wire:encode({36, ID, To, From}));
signal({22, From, To}, {message, Message}, State = #{source_owner := _}) ->
    source_message(From, To, Message, State);
signal({2, _Cookie, To}, {message, Message}, State) ->
    deliver(To, Message, State);
signal({22, _From, To}, {message, Message}, State) ->
    deliver(To, Message, State);
signal({6, _From, _Cookie, Name}, {message, Message}, State) ->
    deliver(Name, Message, State);
signal({33, _From, _Alias}, {message, _Message}, State) ->
    State;
signal(Control, _Message, _State) ->
    error({unsupported_distribution_signal, element(1, Control)}).

%% Authenticate the actual negotiated sender and current target before one asynchronous handoff.
%% The central owner must independently check source codecs, target routes and total capacity.
-spec source_message(pid(), pid(), term(), map()) -> map().
source_message(
    From,
    To,
    {'$gen_cast', Record},
    State = #{
        source_owner := Owner,
        source_senders := Senders,
        source_pending := false,
        clients := Clients,
        peer := Peer,
        sends := Sends
    }
) when
    is_pid(From),
    node(From) =:= Peer,
    is_map_key(From, Senders),
    is_map_key(To, Clients),
    is_tuple(Record)
->
    #{destination := Destination} = maps:get(To, Clients),
    Req = gen_server:send_request(Owner, {source_send, From, Destination, Record}),
    State#{source_pending := true, sends := gen_server:reqids_add(Req, source_handoff, Sends)};
source_message(_From, To, Message, State = #{kernel_pid := Kernel}) when
    To =:= net_kernel; To =:= Kernel
->
    deliver(To, Message, State);
source_message(_, _, _, _) ->
    error(unauthenticated_source_message).

%% Resolve a current-incarnation PID or advertised name; stale targets are absent.
-spec target(pid() | atom(), map()) -> pid() | none.
target(net_kernel, #{kernel_pid := Pid}) -> Pid;
target(Pid, #{kernel_pid := Pid}) -> Pid;
target(To, #{clients := Clients}) when is_pid(To), is_map_key(To, Clients) -> To;
target(Name, #{names := Names}) when is_atom(Name) -> maps:get(Name, Names, none);
target(_, _) -> none.

%% Answer node authentication probes or dispatch messages to known services.
-spec deliver(pid() | atom(), term(), map()) -> map().
deliver(To, {'$gen_call', From, {is_auth, _}}, State = #{kernel_pid := Sender}) when
    To =:= net_kernel; To =:= Sender
->
    send(State, hls_node_wire:reply(Sender, From, yes));
deliver(_To, _Message, #{source_owner := _}) ->
    error(sender_required);
deliver(To, Message, State) ->
    case target(To, State) of
        % Ordinary sends to absent processes are discarded.
        none -> State;
        Pid -> operation(Pid, Message, State)
    end.

%% Handle proxy observations and supported gen_server calls/casts.
-spec operation(pid(), term(), map()) -> map().
operation(
    Pid,
    {'$gen_call', From = {Caller, _}, '$hls_fabric_info'},
    State = #{clients := Clients, peer := Peer, domain_pending := Pending}
) when
    node(Caller) =:= Peer,
    map_get(kind, map_get(Pid, Clients)) =:= domain
->
    #{incarnation := Incarnation, identity := Actor} = maps:get(Pid, Clients),
    send(
        State,
        hls_node_wire:reply(Pid, From, #{
            domain => Incarnation, actor => Actor, connection_pending => Pending
        })
    );
operation(
    Pid,
    {'$gen_call', From = {Caller, _}, Request},
    State = #{clients := Clients, peer := Peer}
) when
    node(Caller) =:= Peer,
    map_get(kind, map_get(Pid, Clients)) =:= domain
->
    issue_domain(Pid, call, From, Request, State);
operation(Pid, {'$gen_cast', Request}, State = #{clients := Clients}) when
    map_get(kind, map_get(Pid, Clients)) =:= domain
->
    issue_domain(Pid, cast, none, {'$hls_domain_cast', Request}, State);
operation(
    Pid,
    {'$gen_call', From, '$hls_fabric_info'},
    State = #{clients := Clients, channels := Channels, queues := Queues}
) ->
    #{channel := Key} = maps:get(Pid, Clients),
    #{pending := Pending, route := {Endpoint, Source}, ignored_replies := Ignored} = maps:get(
        Key, Channels
    ),
    Reply = #{
        pending => length([ok || #{pid := Owner} <- maps:values(Pending), Owner =:= Pid]),
        queued => length([
            ok
         || {Owner, _} <- queue:to_list(maps:get(Key, Queues, queue:new())), Owner =:= Pid
        ]),
        route => {Source, Endpoint},
        ignored_replies => Ignored
    },
    send(State, hls_node_wire:reply(Pid, From, Reply));
operation(
    Pid, {'$gen_call', From = {Caller, _}, Request}, State = #{peer := Peer, clients := Clients}
) when node(Caller) =:= Peer ->
    case maps:get(Pid, Clients) of
        #{kind := actor} -> send(State, hls_node_wire:reply(Pid, From, {error, unsupported_call}));
        _ -> enqueue(Pid, {call, From, Request}, State)
    end;
operation(Pid, {'$gen_cast', Request}, State) ->
    enqueue(Pid, {cast, none, Request}, State);
operation(_Pid, _Message, _State) ->
    error(unsupported_actor_message).

%% Append an operation to its physical channel's ordered queue.
-spec enqueue(pid(), operation(), map()) -> map().
enqueue(Pid, Op, State = #{clients := Clients, queues := Queues}) ->
    #{channel := Key} = maps:get(Pid, Clients),
    Q = maps:get(Key, Queues, queue:new()),
    State#{queues := Queues#{Key => queue:in({Pid, Op}, Q)}}.

%% Submit available work before rearming distribution input.
-spec continue(map()) -> {noreply, map()}.
continue(State) ->
    Next = pump(State),
    {noreply, arm(Next)}.
%% Request one more distribution packet only while queued operations remain below the limit.
-spec arm(map()) -> map().
arm(State = #{source_pending := true}) ->
    State;
arm(
    State = #{
        armed := false,
        socket := {local, Handle},
        queues := Queues,
        config := #{queue_limit := Limit}
    }
) ->
    case queued(Queues) + maps:get(domain_pending, State, 0) < Limit of
        true ->
            ok = erlang:dist_ctrl_get_data_notification(Handle),
            State#{armed := true};
        false ->
            State
    end;
arm(
    State = #{armed := false, socket := Socket, queues := Queues, config := #{queue_limit := Limit}}
) ->
    case queued(Queues) + maps:get(domain_pending, State, 0) < Limit of
        true ->
            ok = inet:setopts(Socket, [{active, once}]),
            State#{armed := true, last_received := now_ms()};
        false ->
            State
    end;
arm(State) ->
    State.
%% Count queued operations across channels for connection-wide admission.
-spec queued(#{channel_key() => queue:queue()}) -> non_neg_integer().
queued(Queues) -> lists:sum([queue:len(Q) || Q <- maps:values(Queues)]).

%% Attempt one send on each queued channel unless waiting for a retry timer.
-spec pump(map()) -> map().
pump(State = #{retry := true}) -> State;
pump(State = #{queues := Queues}) -> lists:foldl(fun pump_channel/2, State, maps:keys(Queues)).
%% Send the head operation when the channel and transaction space permit it.
-spec pump_channel(channel_key(), map()) -> map().
pump_channel(Key = {Kind, _Endpoint}, State = #{queues := Queues, channels := Channels}) ->
    #{Key := Q} = Queues,
    #{Key := #{transmitting := Busy, pending := Pending} = Channel} = Channels,
    Capacity =
        case Kind of
            application -> 255;
            debug -> 256
        end,
    case {Busy, queue:peek(Q), map_size(Pending) < Capacity} of
        {false, {value, {Pid, {cast, _, _} = Op}}, _} -> issue(Key, Pid, Op, Channel, State);
        {false, {value, {Pid, Op}}, true} -> issue(Key, Pid, Op, Channel, State);
        _ -> State
    end.

%% Pack one operation, reserve its reply slot and track asynchronous broker admission.
-spec issue(channel_key(), pid(), operation(), map(), map()) -> map().
issue(
    Key = {Kind, _},
    Pid,
    Op = {Mode, From, Request},
    Channel = #{
        broker := Broker,
        route := {Endpoint, Source},
        pending := Pending,
        next := Next
    },
    State = #{queues := Queues, clients := Clients, channels := Channels, sends := Sends}
) ->
    {_, Q} = queue:out(maps:get(Key, Queues)),
    Base = State#{queues := Queues#{Key := Q}},
    {Tag, Flags, Payload, Context} = encode(maps:get(Pid, Clients), Mode, Request),
    Capacity =
        case Kind of
            application -> 255;
            debug -> 256
        end,
    Tx =
        case Mode of
            call -> slot(Next, Capacity, Pending);
            cast -> 255
        end,
    ID = make_ref(),
    Entry = #{id => ID, pid => Pid, from => From, context => Context},
    Updated =
        case Mode of
            call -> Pending#{Tx => Entry};
            cast -> Pending
        end,
    Req = hls_fabric:send_request(Broker, {Source, Endpoint}, {Tag, Tx, Flags}, Payload, infinity),
    Label = {Key, Tx, ID, Pid, Op},
    Base#{
        channels := Channels#{
            Key := Channel#{
                pending := Updated,
                transmitting := true,
                next :=
                    case Mode of
                        call -> (Tx + 1) rem Capacity;
                        cast -> Next
                    end
            }
        },
        sends := gen_server:reqids_add(Req, Label, Sends)
    }.

%% Select the standalone, scheduled-actor or debug request codec.
-spec encode(map(), call | cast, term()) -> {byte(), byte(), binary(), term()}.
encode(#{kind := actor} = Actor, cast, Request) ->
    {{Tag, 255, Flags}, Payload} = hls_node_binding:encode_cast(Actor, Request),
    {Tag, Flags, Payload, none};
encode(#{kind := application, module := Module}, Mode, Request) ->
    {Tag, Payload, Context} = hls_gs:encode_request(Module, Mode, Request),
    {Tag, 0, Payload, Context};
encode(#{kind := debug, module := Module}, call, Request) ->
    {Tag, Payload, Context} = hls_debug:encode_request(Module, Request),
    {Tag, 0, Payload, Context}.
%% Find an unused transaction ID; the caller must establish spare capacity first.
-spec slot(byte(), pos_integer(), map()) -> byte().
slot(Tx, Capacity, Pending) ->
    case is_map_key(Tx, Pending) of
        true -> slot((Tx + 1) rem Capacity, Capacity, Pending);
        false -> Tx
    end.

%% Release send admission, or retry only when the broker proves the operation was not sent.
-spec written(
    source_handoff
    | {domain_request, pid(), call | cast, gen_server:from() | none}
    | {channel_key(), byte(), reference(), pid(), operation()},
    term(),
    map()
) -> map().
written({domain_request, Pid, call, From}, Reply, State = #{clients := Clients}) ->
    Next = domain_completed(State),
    case maps:is_key(Pid, Clients) of
        true -> send(Next, hls_node_wire:reply(Pid, From, Reply));
        false -> Next
    end;
written({domain_request, _Pid, cast, none}, ok, State) ->
    domain_completed(State);
written({domain_request, _Pid, cast, none}, Result, _State) ->
    %% A cast has no return channel. Refused admission must become visible as connection loss.
    %% No replay is attempted: the remote sender can only regard its work as uncertain.
    error({domain_cast_admission, Result});
written(source_handoff, ok, State = #{source_pending := true}) ->
    State#{source_pending := false};
written({Key, _Tx, _ID, _Pid, _Op}, ok, State = #{channels := Channels}) ->
    Channel = maps:get(Key, Channels),
    State#{channels := Channels#{Key := Channel#{transmitting := false}}};
written(
    {Key, Tx, ID, Pid, Op},
    {error, {not_sent, Reason}},
    State = #{channels := Channels, queues := Queues}
) ->
    true = retryable(Reason),
    #{pending := Pending} = Channel = maps:get(Key, Channels),
    Remaining =
        case Pending of
            #{Tx := #{id := ID}} -> maps:remove(Tx, Pending);
            _ -> Pending
        end,
    Q = queue:in_r({Pid, Op}, maps:get(Key, Queues)),
    %% The broker has proved non-delivery, so retrying cannot duplicate work.
    %% Keep this operation ahead of later sends to the same actor.
    case maps:get(retry, State) of
        false -> erlang:send_after(5, self(), retry);
        true -> ok
    end,
    State#{
        channels := Channels#{Key := Channel#{pending := Remaining, transmitting := false}},
        queues := Queues#{Key := Q},
        retry := true
    };
written(_Label, Result, _State) ->
    error({transport_failed, Result}).
%% Recognize admission limits for which a delayed retry is safe.
-spec retryable(term()) -> boolean().
retryable(tx_limit) -> true;
retryable({route_tx_limit, _}) -> true;
retryable(_) -> false.

%% Decode a matching reply, deliver it to the caller and free its transaction slot.
-spec frame(channel_key(), {byte(), byte(), byte()}, binary(), map()) -> map().
frame(Key = {Kind, _}, {Tag, Tx, 0}, Payload, State = #{channels := Channels}) ->
    #{pending := Pending} = Channel = maps:get(Key, Channels),
    case Pending of
        #{Tx := #{pid := Pid, from := From, context := Context}} ->
            Decoded =
                case Kind of
                    application -> hls_gs:decode_reply(Tag, Payload, Context);
                    debug -> hls_debug:response(Tag, Payload, Context)
                end,
            case Decoded of
                {reply, Reply} ->
                    Sent = send(State, hls_node_wire:reply(Pid, From, Reply)),
                    Sent#{
                        channels := Channels#{Key := Channel#{pending := maps:remove(Tx, Pending)}}
                    };
                ignore ->
                    ignored(Key, State)
            end;
        _ ->
            ignored(Key, State)
    end;
frame(Key, _Header, _Payload, State) ->
    ignored(Key, State).

%% Count unmatched or invalid replies without releasing a pending request.
-spec ignored(channel_key(), map()) -> map().
ignored(Key, State = #{channels := Channels}) ->
    #{ignored_replies := N} = Channel = maps:get(Key, Channels),
    State#{channels := Channels#{Key := Channel#{ignored_replies := N + 1}}}.

%% Return a distribution packet through the active local or TCP carrier.
-spec send(map(), iodata()) -> map().
send(State = #{socket := {local, Handle}, received := N}, Bytes) ->
    ok = erlang:dist_ctrl_put_data(Handle, Bytes),
    State#{received := N + 1};
send(State = #{socket := Socket}, Bytes) ->
    ok = gen_tcp:send(Socket, Bytes),
    State.
%% Classify the initialized distribution carrier for attachment and observations.
-spec carrier(map()) -> local | tcp.
carrier(#{socket := {local, _}}) -> local;
carrier(#{socket := _}) -> tcp.
%% Use monotonic milliseconds for peer liveness deadlines.
-spec now_ms() -> integer().
now_ms() -> erlang:monotonic_time(millisecond).

%% Domain observations expose endpoint identity instead of pretending there is a legacy wire route.
-spec client_info(map(), map()) -> map().
client_info(#{kind := domain, endpoint := Endpoint, incarnation := Incarnation}, _Channels) ->
    #{domain => Incarnation, endpoint => Endpoint};
client_info(#{channel := Key}, Channels) ->
    maps:with([route, pending, transmitting], maps:get(Key, Channels)).

%% Local managed actors have one monitor per peer adapter; endpoint death leaves unrelated actors up.
-spec monitor_domains([map()]) -> #{reference() => pid()}.
monitor_domains(Targets) ->
    maps:from_list([
        {monitor(process, Endpoint), Pid}
     || #{kind := domain, endpoint := Endpoint, pid := Pid} <- Targets
    ]).

%% Forward directly from this adapter so source replies and endpoint DOWN retain ERTS signal ordering.
-spec issue_domain(pid(), call | cast, gen_server:from() | none, term(), map()) -> map().
issue_domain(
    Pid,
    Mode,
    From,
    Request,
    State = #{
        clients := Clients,
        sends := Sends,
        domain_pending := Pending,
        config := #{queue_limit := Limit},
        queues := Queues
    }
) ->
    true = Pending + queued(Queues) < Limit,
    #{endpoint := Endpoint} = maps:get(Pid, Clients),
    RequestId = gen_server:send_request(Endpoint, Request),
    Label = {domain_request, Pid, Mode, From},
    State#{domain_pending := Pending + 1, sends := gen_server:reqids_add(RequestId, Label, Sends)}.

%% Every acknowledged or failed request releases exactly one connection-owned admission slot.
-spec domain_completed(map()) -> map().
domain_completed(State = #{domain_pending := Pending}) when Pending > 0 ->
    State#{domain_pending := Pending - 1}.

%% Only actual monitor delivery emits terminal actor signals; management never manufactures source death.
-spec retire_domain(pid(), term(), map()) -> map().
retire_domain(Pid, Reason, State = #{clients := Clients, monitors := Monitors}) ->
    {Kept, Sent} = maps:fold(
        fun(Ref, {From, To} = Entry, {Rest, Acc}) ->
            case To =:= Pid of
                true -> {Rest, send(Acc, hls_node_wire:encode({21, To, From, Ref, Reason}))};
                false -> {Rest#{Ref => Entry}, Acc}
            end
        end,
        {#{}, State},
        Monitors
    ),
    Sent#{clients := maps:remove(Pid, Clients), monitors := Kept}.

%% The manager has checked physical endpoint death, but its signal may still be queued here.
%% Delay replacement until local DOWN consumption has emitted all corresponding remote monitor exits.
-spec install_domain(map()) -> map().
install_domain(
    State = #{
        domain_publication := #{reference := Ref, old := Old, targets := Targets},
        clients := Clients,
        manager := Manager,
        domain_monitors := Monitors
    }
) ->
    case lists:any(fun(Pid) -> maps:is_key(Pid, Clients) end, Old) of
        true ->
            State;
        false ->
            Fresh = maps:from_list([{Pid, Target} || Target = #{pid := Pid} <- Targets]),
            Manager ! {domain_published, Ref, self()},
            State#{
                clients := maps:merge(Clients, Fresh),
                domain_monitors := maps:merge(Monitors, monitor_domains(Targets)),
                domain_publication := none
            }
    end;
install_domain(State) ->
    State.
