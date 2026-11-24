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
%% Acknowledged casts carry a reply destination without reserving an application call slot.
-type operation() :: hls_node_requests:operation().

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
handle_call(info, _From, State = #{clients := Clients, requests := Requests, channels := Channels}) ->
    {reply,
        #{
            carrier => carrier(State),
            queued => hls_node_requests:waiting(Requests),
            domain_pending => hls_node_requests:pending(domain, Requests),
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
handle_cast({domain_publish, Ref, Kind, Old, Targets}, State = #{domain_publication := none}) ->
    {noreply,
        install_domain(State#{
            domain_publication := #{
                reference => Ref,
                old => Old,
                targets => Targets,
                fresh_monitors => monitor_domains(Targets, Kind)
            }
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
%% Connection loss ends existing observations; only an actual actor exit retires its virtual identity.
handle_info({'DOWN', Ref, process, _Endpoint, Reason}, State = #{domain_monitors := Monitors}) when
    is_map_key(Ref, Monitors)
->
    {Pid, Kind} = maps:get(Ref, Monitors),
    Retired = State#{domain_monitors := maps:remove(Ref, Monitors)},
    Next =
        case endpoint_reason(Reason, Kind) of
            noconnection -> disconnect_domain(Pid, Retired);
            _ -> retire_domain(Pid, Reason, Retired)
        end,
    continue(install_domain(Next));
%% Fresh proxies are monitored during the old-DOWN barrier; their exit reasons must not collapse into later noproc.
handle_info(
    {'DOWN', Ref, process, _Endpoint, Reason},
    State = #{domain_publication := Publication = #{fresh_monitors := Monitors, targets := Targets}}
) when
    is_map_key(Ref, Monitors)
->
    {Pid, Kind} = maps:get(Ref, Monitors),
    Observed = endpoint_reason(Reason, Kind),
    Updated = [
        case Target of
            #{pid := Pid} -> Target#{endpoint_status := {down, Observed}};
            _ -> Target
        end
     || Target <- Targets
    ],
    continue(
        install_domain(State#{
            domain_publication := Publication#{
                targets := Updated,
                fresh_monitors := maps:remove(Ref, Monitors)
            }
        })
    );
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
%% An endpoint separates admission from eventual completion, freeing peer input credit once.
handle_info({hls_admitted, Endpoint, Token}, State = #{clients := Clients, requests := Requests}) ->
    case hls_node_requests:find(Token, Requests) of
        {ok, #{target := Pid, group := {domain, Pid}}} ->
            case maps:find(Pid, Clients) of
                {ok, #{endpoint := Endpoint}} ->
                    continue(State#{requests := hls_node_requests:admit(Token, Requests)});
                _ ->
                    {noreply, State}
            end;
        _ ->
            {noreply, State}
    end;
%% Only this legacy channel waits; independent channels continue admitting work.
handle_info({retry, Token}, State = #{requests := Requests}) ->
    continue(State#{requests := hls_node_requests:retry(Token, Requests)});
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
        {{error, {_Reason, _}}, {Kind, Token}, Remaining} when
            Kind =:= domain_request; Kind =:= domain_capacity
        ->
            %% The endpoint's own DOWN is authoritative; never turn death into an ordinary reply.
            continue(forget(Token, State#{sends := Remaining}));
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
        requests => hls_node_requests:new(),
        sends => gen_server:reqids_new(),
        monitors => #{},
        config => Config,
        source_owner => Owner,
        source_monitor => monitor(process, Owner),
        source_senders => maps:from_list([{P, true} || P <- Senders]),
        source_pending => false,
        armed => false,
        last_received => now_ms()
    };
attach_mode({ok, Brokers, Actors, Source, Config}, Peer, Identity, State) ->
    Clients = maps:from_list([
        {Pid, Actor}
     || #{pid := Pid} = Actor <- Actors, visible_domain(Actor)
    ]),
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
        domain_publication => none,
        domain_withdrawn => #{},
        channels => Channels,
        routes => Routes,
        names => Names,
        requests => hls_node_requests:new(),
        sends => gen_server:reqids_new(),
        monitors => #{},
        config => Config,
        armed => false,
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
        disconnected -> send(State, hls_node_wire:encode({21, To, From, Ref, noconnection}));
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
-spec target(pid() | atom(), map()) -> pid() | none | disconnected.
target(net_kernel, #{kernel_pid := Pid}) ->
    Pid;
target(Pid, #{kernel_pid := Pid}) ->
    Pid;
target(To, #{clients := Clients}) when is_pid(To), is_map_key(To, Clients) ->
    case maps:get(To, Clients) of
        #{endpoint_status := {down, noconnection}} -> disconnected;
        _ -> To
    end;
target(Name, #{names := Names}) when is_atom(Name) -> maps:get(Name, Names, none);
target(_, _) ->
    none.

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
        disconnected -> State;
        Pid -> operation(Pid, Message, State)
    end.

%% Handle proxy observations and supported gen_server calls/casts.
-spec operation(pid(), term(), map()) -> map().
operation(
    Pid,
    {'$gen_call', From = {Caller, _}, '$hls_fabric_info'},
    State = #{clients := Clients, peer := Peer, requests := Requests}
) when
    node(Caller) =:= Peer,
    map_get(kind, map_get(Pid, Clients)) =:= domain
->
    #{incarnation := Incarnation, identity := Actor} = maps:get(Pid, Clients),
    send(
        State,
        hls_node_wire:reply(Pid, From, #{
            domain => Incarnation,
            actor => Actor,
            connection_pending => hls_node_requests:pending(domain, Requests)
        })
    );
operation(
    Pid,
    {'$gen_call', From = {Caller, _}, {'$hls_domain_cast', Request}},
    State = #{clients := Clients, peer := Peer}
) when
    node(Caller) =:= Peer,
    map_get(kind, map_get(Pid, Clients)) =:= domain
->
    issue_domain(Pid, cast, From, Request, State);
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
    issue_domain(Pid, cast, none, Request, State);
operation(
    Pid,
    {'$gen_call', From, '$hls_fabric_info'},
    State = #{clients := Clients, channels := Channels, requests := Requests}
) ->
    #{channel := Key} = maps:get(Pid, Clients),
    #{pending := Pending, route := {Endpoint, Source}, ignored_replies := Ignored} = maps:get(
        Key, Channels
    ),
    Reply = #{
        pending => length([
            ok
         || #{token := Token} <- maps:values(Pending),
            {ok, #{target := Owner}} <- [hls_node_requests:find(Token, Requests)],
            Owner =:= Pid
        ]),
        queued => hls_node_requests:waiting_target(Pid, Requests),
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

%% Both adapters retain caller ownership in the same ordered admission ledger.
-spec enqueue(pid(), operation(), map()) -> map().
enqueue(Pid, Op, State = #{clients := Clients, requests := Requests}) ->
    #{channel := Key} = maps:get(Pid, Clients),
    {_, Next} = hls_node_requests:enqueue(Key, Pid, Op, Requests),
    State#{requests := Next}.

%% Submit available work before rearming distribution input.
-spec continue(map()) -> {noreply, map()}.
continue(State) ->
    Next = pump(State),
    {noreply, arm(Next)}.
%% Only work awaiting admission consumes connection-wide input credit.
-spec arm(map()) -> map().
arm(State = #{source_pending := true}) ->
    State;
arm(
    State = #{
        armed := false,
        socket := {local, Handle},
        requests := Requests,
        config := #{queue_limit := Limit}
    }
) ->
    case hls_node_requests:waiting(Requests) < Limit of
        true ->
            ok = erlang:dist_ctrl_get_data_notification(Handle),
            State#{armed := true};
        false ->
            State
    end;
arm(
    State = #{
        armed := false,
        socket := Socket,
        requests := Requests,
        config := #{queue_limit := Limit}
    }
) ->
    case hls_node_requests:waiting(Requests) < Limit of
        true ->
            ok = inet:setopts(Socket, [{active, once}]),
            State#{armed := true, last_received := now_ms()};
        false ->
            State
    end;
arm(State) ->
    State.

%% Attempt one admission per waiting group; held replies never exclude another actor.
-spec pump(map()) -> map().
pump(State = #{requests := Requests}) ->
    lists:foldl(fun pump_group/2, State, hls_node_requests:groups(Requests)).

%% Managed actors and legacy channels share eligibility while retaining their distinct wire adapters.
-spec pump_group(hls_node_requests:group(), map()) -> map().
pump_group(Group, State = #{requests := Requests}) ->
    case hls_node_requests:head(Group, Requests) of
        none -> State;
        {Token, Entry} -> pump_entry(Token, Entry, State)
    end.

%% A managed endpoint acknowledges admission before its final call result or cast response.
-spec pump_entry(reference(), hls_node_requests:entry(), map()) -> map().
pump_entry(
    Token,
    #{target := Pid, group := {domain, Pid}, operation := {Mode, _, Request}},
    State = #{clients := Clients, requests := Requests, sends := Sends}
) ->
    #{endpoint := Endpoint} = maps:get(Pid, Clients),
    RequestId = gen_server:send_request(Endpoint, {'$hls_submit', Token, Mode, Request}),
    State#{
        requests := hls_node_requests:submit(Token, Requests),
        sends := gen_server:reqids_add(RequestId, {domain_request, Token}, Sends)
    };
pump_entry(
    Token,
    #{target := Pid, group := Key = {Kind, _}, operation := Op = {Mode, _, _}},
    State = #{channels := Channels}
) ->
    #{transmitting := Busy, pending := Pending} = Channel = maps:get(Key, Channels),
    Capacity =
        case Kind of
            application -> 255;
            debug -> 256
        end,
    case not Busy andalso (Mode =:= cast orelse map_size(Pending) < Capacity) of
        true -> issue(Key, Token, Pid, Op, Channel, State);
        false -> State
    end.

%% Pack a legacy operation and retain only its wire correlation and decode context in the channel.
-spec issue(channel_key(), reference(), pid(), operation(), map(), map()) -> map().
issue(
    Key = {Kind, _},
    Token,
    Pid,
    {Mode, _From, Request},
    Channel = #{broker := Broker, route := {Endpoint, Source}, pending := Pending, next := Next},
    State = #{requests := Requests, clients := Clients, channels := Channels, sends := Sends}
) ->
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
    Entry = #{id => ID, token => Token, context => Context},
    Updated =
        case Mode of
            call -> Pending#{Tx => Entry};
            cast -> Pending
        end,
    Req = hls_fabric:send_request(Broker, {Source, Endpoint}, {Tag, Tx, Flags}, Payload, infinity),
    Label = {channel_request, Key, Tx, ID, Token},
    State#{
        requests := hls_node_requests:submit(Token, Requests),
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

%% Final responses retire shared ownership; only proven non-admission permits a retry.
-spec written(
    source_handoff
    | {domain_request | domain_capacity, reference()}
    | {channel_request, channel_key(), byte(), reference(), reference()},
    term(),
    map()
) -> map().
written({domain_request, Token}, Reply, State = #{requests := Requests}) ->
    case hls_node_requests:find(Token, Requests) of
        {ok, #{target := Pid, operation := {cast, From, _}, phase := Phase}} ->
            case {Reply, Phase} of
                {{error, busy}, submitting} -> wait_capacity(Token, Pid, State);
                {ok, _} -> complete(Token, ok, State);
                _ when From =/= none -> complete(Token, Reply, State);
                _ -> withdraw_domain(Pid, State)
            end;
        {ok, _} ->
            complete(Token, Reply, State);
        error ->
            State
    end;
written({domain_capacity, Token}, ok, State = #{requests := Requests}) ->
    State#{requests := hls_node_requests:retry(Token, Requests)};
written({domain_capacity, Token}, Failure, State = #{requests := Requests}) ->
    case hls_node_requests:find(Token, Requests) of
        {ok, #{operation := {cast, From, _}}} when From =/= none -> complete(Token, Failure, State);
        {ok, #{target := Pid}} -> withdraw_domain(Pid, State);
        error -> State
    end;
written(source_handoff, ok, State = #{source_pending := true}) ->
    State#{source_pending := false};
written(
    {channel_request, Key, _Tx, _ID, Token},
    ok,
    State = #{channels := Channels, requests := Requests}
) ->
    Channel = maps:get(Key, Channels),
    Next = State#{
        channels := Channels#{Key := Channel#{transmitting := false}},
        requests := hls_node_requests:admit(Token, Requests)
    },
    case hls_node_requests:find(Token, Requests) of
        {ok, #{operation := {cast, _, _}}} -> complete(Token, ok, Next);
        _ -> Next
    end;
written(
    {channel_request, Key, Tx, ID, Token},
    {error, {not_sent, Reason}},
    State = #{channels := Channels}
) ->
    true = retryable(Reason),
    #{pending := Pending} = Channel = maps:get(Key, Channels),
    Remaining =
        case Pending of
            #{Tx := #{id := ID}} -> maps:remove(Tx, Pending);
            _ -> Pending
        end,
    %% The ledger retains this head while only this channel waits for known-unsent retry.
    erlang:send_after(5, self(), {retry, Token}),
    State#{channels := Channels#{Key := Channel#{pending := Remaining, transmitting := false}}};
written(_Label, Result, _State) ->
    error({transport_failed, Result}).

%% A rejected cast stays at its actor's queue head until explicit capacity notification.
-spec wait_capacity(reference(), pid(), map()) -> map().
wait_capacity(Token, Pid, State = #{clients := Clients, sends := Sends}) ->
    #{endpoint := Endpoint} = maps:get(Pid, Clients),
    RequestId = gen_server:send_request(Endpoint, '$hls_capacity'),
    State#{sends := gen_server:reqids_add(RequestId, {domain_capacity, Token}, Sends)}.

%% Caller/result ownership is identical for legacy decoded replies and managed endpoint replies.
-spec complete(reference(), term(), map()) -> map().
complete(Token, Reply, State = #{requests := Requests, clients := Clients}) ->
    {Entry, Next} = hls_node_requests:finish(Token, Requests),
    Base = State#{requests := Next},
    case Entry of
        #{target := Pid, operation := {_, From, _}} when From =/= none, is_map_key(Pid, Clients) ->
            send(Base, hls_node_wire:reply(Pid, From, Reply));
        _ ->
            Base
    end.

%% Dropping a local observer never manufactures an application response or cancels device work.
-spec forget(reference(), map()) -> map().
forget(Token, State = #{requests := Requests}) ->
    {_, Next} = hls_node_requests:finish(Token, Requests),
    State#{requests := Next}.

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
        #{Tx := #{token := Token, context := Context}} ->
            Decoded =
                case Kind of
                    application -> hls_gs:decode_reply(Tag, Payload, Context);
                    debug -> hls_debug:response(Tag, Payload, Context)
                end,
            case Decoded of
                {reply, Reply} ->
                    Sent = complete(Token, Reply, State),
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
-spec monitor_domains([map()]) -> #{reference() => {pid(), replacement | reattach}}.
monitor_domains(Targets) -> monitor_domains(Targets, replacement).

%% Preserve which monitors cover a connection candidate rather than a newly allocated actor identity.
-spec monitor_domains([map()], replacement | reattach) ->
    #{reference() => {pid(), replacement | reattach}}.
monitor_domains(Targets, Kind) ->
    maps:from_list([
        {monitor(process, Endpoint), {Pid, Kind}}
     || #{kind := domain, endpoint := Endpoint, pid := Pid, endpoint_status := connected} <- Targets
    ]).

%% A reconnect candidate which died before monitor setup cannot establish death of the surviving hardware actor.
-spec endpoint_reason(term(), replacement | reattach) -> term().
endpoint_reason(noproc, reattach) -> noconnection;
endpoint_reason(Reason, _) -> Reason.

%% Bound unfinished calls per actor, independently of its cast admission and other actors' progress.
-spec issue_domain(pid(), call | cast, gen_server:from() | none, term(), map()) -> map().
issue_domain(
    Pid,
    Mode,
    From,
    Request,
    State = #{requests := Requests, config := #{queue_limit := Limit}}
) ->
    case Mode =:= call andalso hls_node_requests:calls(Pid, Requests) >= Limit of
        true ->
            send(State, hls_node_wire:reply(Pid, From, {error, busy}));
        false ->
            {_, Next} = hls_node_requests:enqueue(
                {domain, Pid}, Pid, {Mode, From, Request}, Requests
            ),
            State#{requests := Next}
    end.

%% Irrecoverable raw-cast rejection remains a permanent withdrawal for this peer, even after proxy reattachment.
-spec withdraw_domain(pid(), map()) -> map().
withdraw_domain(Pid, State = #{domain_withdrawn := Withdrawn}) ->
    Retired = retire_domain(Pid, noconnection, State),
    Retired#{domain_withdrawn := Withdrawn#{Pid => true}}.

%% A terminal actor exit removes the binding; a replacement will receive a distinct virtual PID.
-spec retire_domain(pid(), term(), map()) -> map().
retire_domain(Pid, Reason, State = #{clients := Clients}) ->
    Sent = finish_domain_observers(Pid, Reason, State),
    Sent#{clients := maps:remove(Pid, Clients)}.

%% A dead host proxy does not imply dead hardware. Keep only its identity, never pending work or monitors.
-spec disconnect_domain(pid(), map()) -> map().
disconnect_domain(Pid, State = #{clients := Clients}) ->
    Sent = finish_domain_observers(Pid, noconnection, State),
    case maps:find(Pid, Clients) of
        {ok, Target} ->
            Sent#{clients := Clients#{Pid := Target#{endpoint_status := {down, noconnection}}}};
        error ->
            Sent
    end.

%% Deliver one terminal event to each installed monitor and forget every uncertain queued or admitted request.
-spec finish_domain_observers(pid(), term(), map()) -> map().
finish_domain_observers(Pid, Reason, State = #{monitors := Monitors, requests := Requests}) ->
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
    Sent#{monitors := Kept, requests := hls_node_requests:remove_target(Pid, Requests)}.

%% Peers created after a disconnect retain its noconnection meaning; genuine terminated actors remain absent.
-spec visible_domain(map()) -> boolean().
visible_domain(#{endpoint_status := {down, Reason}}) -> Reason =:= noconnection;
visible_domain(_) -> true.

%% The manager has checked physical endpoint death, but its signal may still be queued here.
%% Delay replacement until local DOWN consumption has emitted all corresponding remote monitor exits.
-spec install_domain(map()) -> map().
install_domain(
    State = #{
        domain_publication := #{
            reference := Ref, old := Old, targets := Targets, fresh_monitors := FreshMonitors
        },
        clients := Clients,
        manager := Manager,
        domain_monitors := Monitors,
        domain_withdrawn := Withdrawn
    }
) ->
    case
        lists:any(fun(Pid) -> lists:member(Pid, [P || {P, _} <- maps:values(Monitors)]) end, Old)
    of
        true ->
            State;
        false ->
            NewIds = [Pid || #{pid := Pid} <- Targets],
            KeptWithdrawn = maps:without(Old -- NewIds, Withdrawn),
            Allowed = [
                Target
             || Target = #{pid := Pid} <- Targets,
                visible_domain(Target),
                not maps:is_key(Pid, KeptWithdrawn)
            ],
            Fresh = maps:from_list([{Pid, Target} || Target = #{pid := Pid} <- Allowed]),
            KeptMonitors = maps:filter(
                fun(Monitor, {Pid, _}) ->
                    case maps:is_key(Pid, Fresh) of
                        true ->
                            true;
                        false ->
                            demonitor(Monitor, [flush]),
                            false
                    end
                end,
                FreshMonitors
            ),
            Manager ! {domain_published, Ref, self()},
            State#{
                clients := maps:merge(maps:without(Old, Clients), Fresh),
                domain_monitors := maps:merge(Monitors, KeptMonitors),
                domain_publication := none,
                domain_withdrawn := KeptWithdrawn
            }
    end;
install_domain(State) ->
    State.
