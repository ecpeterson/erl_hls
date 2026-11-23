-module(hls_node).
-moduledoc """
Clients activate a supervised virtual-node incarnation through this facade. hls_node_sup owns its connection tree; retained service bindings and the common broker translate remote actor messages.

A virtual FPGA distribution node hosted inside the existing BEAM.
""".
-behaviour(gen_server).
%% Public virtual-node lifecycle and inventory.
-export([start_link/4, stop/1, info/1, services/1, publish_domain/2, reattach_domain/2]).
%% Supervisor and local-carrier entry points.
-export([start_manager/5, local_manager/1]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-export_type([brokers/0, service/0, options/0]).
-doc "Distinct local application and debug brokers, or an empty map for managed-domain-only nodes.".
-type brokers() :: #{} | #{application := pid(), debug := pid()}.
-doc "A named standalone/scheduled service, a managed domain, or one exclusive source partition. Managed domains enroll already-ready local incarnation endpoints; publication of replacements is explicit. Source owner and senders are exact local PIDs; targets map logical identities to owner-validated destination terms. The owner must handle source_bind once and source_attach once, then bounded source_send calls. A source connection loss ends this node incarnation; hardware reset and transport retirement remain external obligations.".
-type service() ::
    #{name := atom(), module := module(), endpoint := 0..((1 bsl 16) - 1)}
    | #{name := atom(), topology := map(), debug_endpoint := 0..((1 bsl 16) - 1)}
    | #{name := atom(), source := #{owner := pid(), senders := [pid()], targets := map()}}
    | #{name := atom(), domain := #{owner := pid(), id := hls_domain:domain()}}.
-doc "Listener address, connection/queue bounds, return-route range and heartbeat interval in milliseconds.".
-type options() :: #{
    ip => inet:ip_address(),
    port => inet:port_number(),
    epmd_port => inet:port_number(),
    max_connections => pos_integer(),
    source_range => {pos_integer(), pos_integer()},
    queue_limit => pos_integer(),
    tick_ms => pos_integer()
}.

-doc "Activates a virtual node using existing application and debug brokers; returns its supervisor.".
-spec start_link(node(), brokers(), [service()], options()) -> supervisor:startlink_ret().
start_link(Name, Brokers, Services, Options) ->
    hls_node_sup:start_link(Name, Brokers, Services, Options).
-doc "Stops a node supervisor and its connections; does not reset hardware or reopen brokers.".
-spec stop(pid()) -> ok.
stop(Node) -> gen_server:stop(Node, normal, infinity).
-doc "Returns node identity, advertised services and current connections.".
-spec info(pid()) -> map().
info(Node) -> gen_server:call(hls_node_sup:child(Node, node), info).
-doc "Returns named application/debug PIDs or topology actor handles for this incarnation.".
-spec services(pid()) -> #{atom() => map()}.
services(Node) -> maps:get(services, info(Node)).
-doc "Publishes a declared managed domain's ready incarnation after its old endpoints have died. Duplicate publication is idempotent; this does not activate, reset or replay work. Completion waits for each connected peer adapter to consume the old endpoints' DOWN signals before it installs fresh virtual PIDs.".
-spec publish_domain(pid(), atom()) -> {ok, map()} | {error, term()}.
publish_domain(Node, Name) ->
    gen_server:call(hls_node_sup:child(Node, node), {publish_domain, Name}).
-doc "Reconnects a declared domain's surviving incarnation to fresh host proxies without changing its virtual PIDs. The owner must already attest readiness for the same incarnation; old proxies must have exited with noconnection. Previously delivered monitor exits and uncertain requests are never replayed or revived.".
-spec reattach_domain(pid(), atom()) -> {ok, map()} | {error, term()}.
reattach_domain(Node, Name) ->
    gen_server:call(hls_node_sup:child(Node, node), {reattach_domain, Name}).
-doc "Starts the node manager under its qualified local registration name.".
-spec start_manager(node(), brokers(), [service()], options(), pid()) -> gen_server:start_ret().
start_manager(Name, Brokers, Services, Options, NodeSup) ->
    Registered = list_to_atom(manager_name(Name)),
    gen_server:start_link(
        {local, Registered}, ?MODULE, {Name, Brokers, Services, Options, NodeSup}, []
    ).

%% Only our module-qualified names identify managers. An arbitrary process
%% registered as Node must not receive local_connection calls. Discovery does
%% not intern names, and callers keep the resolved PID across setup races.
-doc "Finds a locally hosted node manager without creating atoms; returns undefined when absent.".
-spec local_manager(node()) -> pid() | undefined.
local_manager(Node) ->
    try list_to_existing_atom(manager_name(Node)) of
        Registered -> whereis(Registered)
    catch
        error:badarg -> undefined
    end.

%% Qualify registrations so discovery never addresses an unrelated process named after a node.
-spec manager_name(node()) -> string().
manager_name(Node) -> "hls_node:" ++ atom_to_list(Node).

-doc "Validates services, advertises the node through EPMD and allocates its actor PIDs.".
-spec init({node(), brokers(), [service()], options(), pid()}) -> {ok, map()}.
init({Name, Brokers, Services, Options, NodeSup}) ->
    ok = validate(Name, Brokers, Services),
    %% Distribution clients resolve the advertised host name. Loopback is not
    %% necessarily one of that name's addresses (notably on Linux hosts).
    [_Short, Host] = string:split(atom_to_list(Name), "@"),
    IP0 =
        case Options of
            #{ip := Address} ->
                Address;
            #{} ->
                {ok, Address} = inet:getaddr(Host, inet),
                Address
        end,
    Config = maps:merge(
        #{
            ip => IP0,
            port => 0,
            epmd_port => 4369,
            max_connections => 8,
            source_range => {1, 65535},
            queue_limit => 32,
            tick_ms => 15000
        },
        Options
    ),
    #{
        ip := IP,
        port := Port,
        epmd_port := EpmdPort,
        max_connections := Max,
        source_range := {First, Last},
        queue_limit := Limit,
        tick_ms := Tick
    } = Config,
    true = map_size(Config) =:= 7,
    true = is_integer(Max) andalso Max > 0 andalso is_integer(Limit) andalso Limit > 0,
    true =
        is_integer(First) andalso is_integer(Last) andalso First >= 1 andalso Last =< 65535 andalso
            First =< Last,
    true = is_integer(Tick) andalso Tick > 0,
    {ok, Listen} = gen_tcp:listen(Port, [
        binary,
        {packet, 2},
        {active, false},
        {ip, IP},
        {reuseaddr, true},
        {nodelay, true},
        {packet_size, 1048576},
        {send_timeout, 5000},
        {send_timeout_close, true}
    ]),
    {ok, {_, ActualPort}} = inet:sockname(Listen),
    {Epmd, Creation} = hls_node_wire:register(Name, ActualPort, EpmdPort),
    {Actors, Handles, NextId} = lists:foldl(
        fun({_ServiceName, Service}, {Targets, Named, Next}) ->
            {More, Handle, After} = activate(Name, Creation, Service, Next),
            {More ++ Targets, Named#{maps:get(name, Service) => Handle}, After}
        end,
        {[], #{}, 16#20001},
        lists:sort([{maps:get(name, S), S} || S <- Services])
    ),
    SourceOwners = lists:usort([O || #{source := #{owner := O}} <- Services]),
    Monitors = [monitor(process, Owner) || Owner <- maps:values(Brokers) ++ SourceOwners],
    {ok, #{
        name => Name,
        creation => Creation,
        listen => Listen,
        epmd => Epmd,
        port => ActualPort,
        config => Config,
        brokers => Brokers,
        actors => Actors,
        services => Handles,
        domain_monitors => monitor_domains(Actors),
        domain_services => maps:from_list([{maps:get(name, S), S} || S = #{domain := _} <- Services]),
        next_id => NextId,
        publication => none,
        connections => #{},
        node_sup => NodeSup,
        monitors => Monitors,
        source_used => false,
        sealed_source => SourceOwners =/= []
    }}.

%% Assign the application or debug PID for a standalone endpoint.
-spec actor(node(), non_neg_integer(), map(), application | debug) -> map().
actor(Node, Creation, #{endpoint := Endpoint} = Service, Kind) ->
    ID =
        2 * Endpoint +
            case Kind of
                application -> 1;
                debug -> 2
            end,
    Service#{
        kind => Kind, channel => {Kind, Endpoint}, pid => hls_node_wire:pid(Node, Creation, ID)
    }.

%% Create service handles while keeping scheduled actors in a separate dense PID namespace.
-spec activate(node(), non_neg_integer(), service(), non_neg_integer()) ->
    {[map()], map(), non_neg_integer()}.
activate(Node, Creation, Service = #{name := Name, domain := _}, Next) ->
    {ok, Snapshot} = hls_node_domain:snapshot(Service),
    hls_node_domain:allocate(Node, Creation, Name, Snapshot, Next);
activate(
    Node,
    Creation,
    #{source := #{owner := Owner, senders := Senders, targets := Destinations}},
    Next
) ->
    Targets = [
        #{
            kind => source,
            owner => Owner,
            senders => Senders,
            identity => Id,
            destination => Destination,
            pid => hls_node_wire:pid(Node, Creation, Next + Offset)
        }
     || {Offset, {Id, Destination}} <- lists:enumerate(0, lists:sort(maps:to_list(Destinations)))
    ],
    Handles = maps:from_list([{Id, Pid} || #{identity := Id, pid := Pid} <- Targets]),
    ok = gen_server:call(Owner, {source_bind, #{name => Node, creation => Creation}, Handles}),
    {Targets, #{actors => Handles, source_owner => Owner}, Next + length(Targets)};
activate(Node, Creation, #{topology := #{actors := Actors}, debug_endpoint := Endpoint}, Next) ->
    %% Standalone endpoint PIDs occupy 1..16#20000. Logical actor identity has
    %% its own dense namespace and never depends on physical scheduler slots.
    Targets = [
        A#{
            pid => hls_node_wire:pid(Node, Creation, Next + Target),
            channel => {application, E}
        }
     || A = #{target := Target, endpoint := E} <- Actors
    ],
    Debug =
        #{pid := DebugPid} = actor(
            Node, Creation, #{module => undefined, endpoint => Endpoint}, debug
        ),
    Handles = maps:from_list([{Id, Pid} || #{identity := Id, pid := Pid} <- Targets]),
    {[Debug | Targets], #{actors => Handles, debug => DebugPid}, Next + length(Actors)};
activate(Node, Creation, Service, Next) ->
    App = #{pid := AppPid} = actor(Node, Creation, Service, application),
    Debug = #{pid := DebugPid} = actor(Node, Creation, Service, debug),
    {[App, Debug], #{application => AppPid, debug => DebugPid}, Next}.

-doc "Serves node discovery, handshake identity and connection attachment requests.".
-spec handle_call(term(), gen_server:from(), map()) -> {reply, term(), map()} | {noreply, map()}.
%% A single bounded publication transaction updates all existing connections.
handle_call({publish_domain, _Name}, _From, State = #{publication := Pending}) when
    Pending =/= none
->
    {reply, {error, publication_in_progress}, State};
%% New identities are allocated only from current readiness and actual old endpoint retirement.
handle_call({publish_domain, Name}, From, State) ->
    publish(Name, From, State);
%% Reattachment changes host endpoints, not the distributed actor identity.
handle_call({reattach_domain, _}, _From, State = #{publication := Pending}) when Pending =/= none ->
    {reply, {error, publication_in_progress}, State};
%% A ready surviving incarnation may explicitly replace its disconnected host proxies.
handle_call({reattach_domain, Name}, From, State) ->
    reattach(Name, From, State);
%% Create an adapter for a distribution connection inside this BEAM.
handle_call({local_connection, Owner}, _From, State = #{node_sup := Sup}) ->
    Identity = maps:with([name, creation], State),
    Reply = hls_node_connections:start(
        hls_node_sup:child(Sup, connections), self(), {local, Owner, Identity}
    ),
    {reply, Reply, State};
%% Give the acceptor its listener socket.
handle_call(listener, _From, State = #{listen := Listen}) ->
    {reply, Listen, State};
%% Expose advertised identity and connection observations.
handle_call(info, _From, State) ->
    {reply, maps:with([name, creation, port, services, connections], State), State};
%% Supply the identity needed for an incoming handshake.
handle_call(handshake, _From, State) ->
    {reply, maps:with([name, creation], State), State};
%% A source owner already owns its broker route; bind one local-BEAM connection without claiming another.
handle_call(
    {attach, Peer, Carrier},
    {Connection, _},
    State = #{
        sealed_source := true,
        source_used := false,
        config := Config,
        actors := [#{owner := Owner} | _] = Actors
    }
) when Peer =:= node() ->
    ok = gen_server:call(Owner, {source_attach, Connection}),
    Ref = monitor(process, Connection),
    Entry = #{peer => Peer, monitor => Ref, carrier => Carrier},
    {reply, {source, Owner, Actors, Config}, State#{
        source_used := true, connections := #{Connection => Entry}
    }};
%% Reconnection and foreign peers cannot inherit pending source traffic or hardware credits.
handle_call({attach, _, _}, _From, State = #{sealed_source := true}) ->
    {reply, {error, source_incarnation_sealed}, State};
%% A peer must not attach halfway through an incarnation publication transaction.
handle_call({attach, _, _}, _From, State = #{publication := Pending}) when Pending =/= none ->
    {reply, {error, publication_in_progress}, State};
%% Reserve fresh return routes for an authenticated peer, enforcing connection limits.
handle_call(
    {attach, Peer, Carrier},
    {Owner, _},
    State = #{
        connections := Connections,
        config := #{max_connections := Max} = Config,
        brokers := Brokers,
        actors := Actors
    }
) ->
    Live = maps:filter(fun(Pid, _) -> is_process_alive(Pid) end, Connections),
    case
        {
            awaiting_domain_down(Actors),
            map_size(Live) >= Max,
            lists:member(Peer, [N || #{peer := N} <- maps:values(Live)])
        }
    of
        {true, _, _} ->
            {reply, {error, domain_status_pending}, State};
        {false, true, _} ->
            {reply, {error, connection_limit}, State#{connections := Live}};
        {false, _, true} ->
            {reply, {error, already_connected}, State#{connections := Live}};
        _ ->
            case source(Brokers, maps:get(source_range, Config)) of
                exhausted ->
                    {reply, {error, source_endpoints_exhausted}, State};
                Source ->
                    %% Reserve with the actual connection owner before allowing
                    %% another attach. Even partial registrations stay retired.
                    Results = [
                        hls_fabric:register_route(
                            maps:get(Kind, Brokers),
                            {Endpoint, Source + offset(Kind)},
                            Owner
                        )
                     || {Kind, Endpoint} <- lists:usort([C || #{channel := C} <- Actors])
                    ],
                    case lists:usort(Results) of
                        Success when Success =:= []; Success =:= [ok] ->
                            Ref = monitor(process, Owner),
                            Entry = #{
                                peer => Peer, source => Source, monitor => Ref, carrier => Carrier
                            },
                            {reply, {ok, Brokers, Actors, Source, Config}, State#{
                                connections := Live#{Owner => Entry}
                            }};
                        Errors ->
                            {reply, {error, {routes, Errors}}, State}
                    end
            end
    end.
-doc "Ignores casts; node management uses synchronous requests.".
-spec handle_cast(term(), map()) -> {noreply, map()}.
handle_cast(_, State) -> {noreply, State}.
-doc "Removes dead connections and stops the node if a broker or EPMD connection fails.".
-spec handle_info(term(), map()) -> {noreply, map()} | {stop, term(), map()}.
%% Connections acknowledge only after their actual endpoint monitors have retired old identities.
handle_info(
    {domain_published, Ref, Connection}, State = #{publication := #{reference := Ref} = Pending}
) ->
    Waiting = maps:remove(Connection, maps:get(waiting, Pending)),
    {noreply, finish_publication(State#{publication := Pending#{waiting := Waiting}})};
%% Retain endpoint failure classification for peers which connect after the proxy has died.
handle_info({'DOWN', Ref, process, _Endpoint, Reason}, State = #{domain_monitors := Monitors}) when
    is_map_key(Ref, Monitors)
->
    {Pid, Kind} = maps:get(Ref, Monitors),
    Observed =
        case {Reason, Kind} of
            {noproc, reattach} -> noconnection;
            _ -> Reason
        end,
    {noreply, domain_down(Pid, Observed, State#{domain_monitors := maps:remove(Ref, Monitors)})};
%% A departed source connection ends the virtual incarnation; it must never reconnect to live hardware state.
handle_info(
    {'DOWN', Ref, process, Pid, Reason},
    State = #{sealed_source := true, connections := Connections}
) when
    is_map_key(Pid, Connections)
->
    #{monitor := Ref} = maps:get(Pid, Connections),
    {stop, {shutdown, {source_connection_down, Reason}}, State};
%% A failed broker or source owner ends this incarnation; legacy peers release only their connection entry.
handle_info(
    {'DOWN', Ref, process, Pid, Reason}, State = #{monitors := Monitors, connections := Connections}
) ->
    case lists:member(Ref, Monitors) of
        true -> {stop, {shutdown, {broker_down, Reason}}, State};
        false -> {noreply, departed(Pid, State#{connections := maps:remove(Pid, Connections)})}
    end;
%% Loss of the EPMD registration ends the advertised incarnation.
handle_info({tcp_closed, Epmd}, State = #{epmd := Epmd}) ->
    {stop, epmd_closed, State};
%% Report an EPMD transport failure to the supervisor.
handle_info({tcp_error, Epmd, Reason}, State = #{epmd := Epmd}) ->
    {stop, {epmd, Reason}, State};
%% Ignore unrelated messages.
handle_info(_, State) ->
    {noreply, State}.

%% Allocate a fresh application/debug return-route pair beyond all used broker endpoints.
-spec source(brokers(), {pos_integer(), pos_integer()}) -> pos_integer() | exhausted.
source(Brokers, _Range) when map_size(Brokers) =:= 0 -> 1;
source(Brokers, {First, Last}) ->
    Used = lists:append([
        begin
            #{routes := Routes} = hls_fabric:info(Broker),
            [Local || {_Peer, Local} <- maps:keys(Routes), Local >= First, Local =< Last]
        end
     || Broker <- maps:values(Brokers)
    ]),
    Next = lists:max([First - 1 | Used]) + 1,
    case Next + 1 =< Last of
        true -> Next;
        false -> exhausted
    end.

%% Keep application and debug return routes distinct within each allocated pair.
-spec offset(application | debug) -> 0 | 1.
offset(application) -> 0;
offset(debug) -> 1.

%% Reject ambiguous names, nonlocal brokers and overlapping physical endpoints before node startup.
-spec validate(node(), brokers(), [service()]) -> ok.
validate(Name, Brokers, Services) when
    is_atom(Name), is_map(Brokers), is_list(Services), Services =/= []
->
    ok = validate_brokers(Brokers, Services),
    [Short, Host] = binary:split(atom_to_binary(Name), <<"@">>),
    true = byte_size(Short) > 0 andalso byte_size(Host) > 0 andalso Name =/= node(),
    Names = [N || #{name := N} <- Services],
    true = length(Services) =:= length(lists:usort(Names)),
    true = lists:all(fun(N) -> is_atom(N) andalso N =/= net_kernel end, Names),
    true =
        (not lists:any(fun(S) -> maps:is_key(source, S) end, Services)) orelse
            length(Services) =:= 1,
    Channels = lists:append([service_channels(S) || S <- Services]),
    true = length(Channels) =:= length(lists:usort(Channels)),
    true = lists:all(
        fun({_Kind, E}) -> is_integer(E) andalso E >= 0 andalso E =< 65535 end, Channels
    ),
    ok.

%% Validate one service and enumerate the physical channels it reserves.
-spec service_channels(service()) -> [{application | debug, 0..((1 bsl 16) - 1)}].
service_channels(#{name := _, domain := #{owner := Owner, id := Domain} = Binding} = Service) when
    map_size(Service) =:= 2, map_size(Binding) =:= 2
->
    true = is_pid(Owner) andalso node(Owner) =:= node() andalso is_atom(Domain),
    [];
service_channels(
    #{name := _, source := Source = #{owner := Owner, senders := Senders, targets := Targets}} = S
) when
    map_size(S) =:= 2, map_size(Source) =:= 3
->
    true = is_pid(Owner) andalso node(Owner) =:= node(),
    true = is_list(Senders) andalso Senders =/= [],
    true = lists:all(fun(P) -> is_pid(P) andalso node(P) =:= node() end, Senders),
    true = length(Senders) =:= length(lists:usort(Senders)),
    true = is_map(Targets) andalso map_size(Targets) > 0 andalso map_size(Targets) =< 65535,
    true = map_size(Targets) =:= length(lists:usort(maps:values(Targets))),
    [];
service_channels(
    #{name := _, topology := Deployment = #{groups := Groups}, debug_endpoint := E} = S
) when
    map_size(S) =:= 3
->
    ok = hls_node_binding:validate(Deployment),
    [{debug, E} | [{application, Endpoint} || #{endpoint := Endpoint} <- Groups]];
service_channels(#{name := _, module := M, endpoint := E} = S) when map_size(S) =:= 3, is_atom(M) ->
    {ok, _Contract} = hls_service_schema:from_module(M),
    [{application, E}, {debug, E}].

%% Only managed domains bypass the physical application/debug brokers.
-spec validate_brokers(brokers(), [service()]) -> ok.
validate_brokers(Brokers, Services) when map_size(Brokers) =:= 0 ->
    true = lists:all(fun(S) -> maps:is_key(domain, S) end, Services),
    ok;
validate_brokers(#{application := App, debug := Debug} = Brokers, _Services) when
    is_pid(App),
    is_pid(Debug),
    App =/= Debug,
    node(App) =:= node(),
    node(Debug) =:= node(),
    map_size(Brokers) =:= 2
->
    ok.

%% Readiness never overrides live old endpoints; replacing them is the domain owner's responsibility.
-spec publish(atom(), gen_server:from(), map()) -> {reply, term(), map()} | {noreply, map()}.
publish(Name, From, State = #{domain_services := Declared, services := Handles, actors := Actors}) ->
    case maps:find(Name, Declared) of
        error ->
            {reply, {error, unknown_managed_domain}, State};
        {ok, Service} ->
            Old = [A || A = #{kind := domain, service := N} <- Actors, N =:= Name],
            Handle = maps:get(Name, Handles),
            case hls_node_domain:replacement(Service, Old, Handle) of
                unchanged -> {reply, {ok, Handle}, State};
                {error, Reason} -> {reply, {error, Reason}, State};
                {ok, Snapshot} -> begin_publication(Name, From, Old, Snapshot, State)
            end
    end.

%% Explicit reattachment permits only disconnected identities whose authoritative incarnation survived.
-spec reattach(atom(), gen_server:from(), map()) -> {reply, term(), map()} | {noreply, map()}.
reattach(Name, From, State = #{domain_services := Declared, services := Handles, actors := Actors}) ->
    case maps:find(Name, Declared) of
        error ->
            {reply, {error, unknown_managed_domain}, State};
        {ok, Service} ->
            Old = [A || A = #{kind := domain, service := N} <- Actors, N =:= Name],
            Handle = maps:get(Name, Handles),
            case hls_node_domain:reattachment(Service, Old, Handle) of
                unchanged -> {reply, {ok, Handle}, State};
                {error, Reason} -> {reply, {error, Reason}, State};
                {ok, Targets} -> publish_targets(reattach, Name, From, Old, Targets, Handle, State)
            end
    end.

%% A fresh monotonically allocated PID set is installed only after every connection acknowledges retirement.
-spec begin_publication(atom(), gen_server:from(), [map()], hls_domain:snapshot(), map()) ->
    {noreply, map()} | {reply, term(), map()}.
begin_publication(_Name, _From, _Old, #{actors := Actors}, State = #{next_id := Next}) when
    Next + map_size(Actors) > (1 bsl 32)
->
    {reply, {error, virtual_pids_exhausted}, State};
begin_publication(
    Name,
    From,
    Old,
    Snapshot,
    State = #{name := Node, creation := Creation, next_id := Next}
) ->
    {Targets, Handle, After} = hls_node_domain:allocate(Node, Creation, Name, Snapshot, Next),
    publish_targets(replacement, Name, From, Old, Targets, Handle, State#{next_id := After}).

%% Both publication modes await each peer's old DOWN signals before exposing any fresh endpoint.
-spec publish_targets(
    replacement | reattach, atom(), gen_server:from(), [map()], [map()], map(), map()
) -> {noreply, map()}.
publish_targets(
    Kind,
    Name,
    From,
    Old,
    Targets,
    Handle,
    State = #{connections := Connections, domain_monitors := Monitors}
) ->
    FreshMonitors = monitor_domains(Targets, Kind),
    Ref = make_ref(),
    Waiting = maps:map(fun(_, _) -> true end, Connections),
    maps:foreach(
        fun(Connection, _) ->
            gen_server:cast(
                Connection, {domain_publish, Ref, Kind, [P || #{pid := P} <- Old], Targets}
            )
        end,
        Waiting
    ),
    Pending = #{
        reference => Ref,
        from => From,
        service => Name,
        targets => Targets,
        handle => Handle,
        waiting => Waiting
    },
    {noreply,
        finish_publication(State#{
            publication := Pending,
            domain_monitors := maps:merge(Monitors, FreshMonitors)
        })}.

%% Losing a whole peer connection is independent of actor retirement; its ERTS observers see noconnection.
-spec departed(pid(), map()) -> map().
departed(Pid, State = #{publication := Pending = #{waiting := Waiting}}) ->
    finish_publication(State#{publication := Pending#{waiting := maps:remove(Pid, Waiting)}});
departed(_Pid, State) ->
    State.

%% Commit one complete publication and reply without exposing a partially replaced service inventory.
-spec finish_publication(map()) -> map().
finish_publication(
    State = #{
        publication := #{
            waiting := Waiting,
            from := From,
            service := Name,
            targets := Targets,
            handle := Handle
        },
        actors := Actors,
        services := Handles
    }
) when map_size(Waiting) =:= 0 ->
    Kept = [
        A
     || A <- Actors,
        case A of
            #{kind := domain, service := Name} -> false;
            _ -> true
        end
    ],
    gen_server:reply(From, {ok, Handle}),
    State#{actors := Kept ++ Targets, services := Handles#{Name := Handle}, publication := none};
finish_publication(State) ->
    State.

%% Local monitors classify proxy loss once for future peer connections and explicit reattachment.
-spec monitor_domains([map()]) -> #{reference() => {pid(), replacement | reattach}}.
monitor_domains(Targets) -> monitor_domains(Targets, replacement).

%% Reattachment candidates already gone before monitor setup represent a failed connection attempt, not actor death.
-spec monitor_domains([map()], replacement | reattach) ->
    #{reference() => {pid(), replacement | reattach}}.
monitor_domains(Targets, Kind) ->
    maps:from_list([
        {monitor(process, Endpoint), {Pid, Kind}}
     || #{kind := domain, endpoint := Endpoint, pid := Pid, endpoint_status := connected} <- Targets
    ]).

%% A new connection must not infer noproc from a proxy death whose authoritative reason is still queued.
-spec awaiting_domain_down([map()]) -> boolean().
awaiting_domain_down(Targets) ->
    lists:any(
        fun
            (#{kind := domain, endpoint := Endpoint, endpoint_status := connected}) ->
                not is_process_alive(Endpoint);
            (_) ->
                false
        end,
        Targets
    ).

%% Endpoint failure can arrive while peers still acknowledge publication; retain its classification in both inventories.
-spec domain_down(pid(), term(), map()) -> map().
domain_down(Pid, Reason, State = #{actors := Actors, publication := Publication}) ->
    Mark = fun(Target) ->
        case Target of
            #{pid := Pid} -> Target#{endpoint_status := {down, Reason}};
            _ -> Target
        end
    end,
    Pending =
        case Publication of
            none -> none;
            #{targets := Targets} -> Publication#{targets := lists:map(Mark, Targets)}
        end,
    State#{actors := lists:map(Mark, Actors), publication := Pending}.
