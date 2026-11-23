%%%% phi_memory_cpu_fabric
%%%%
%%%% Functional CPU realization of the phi memory topology and fabric API.

-module(phi_memory_cpu_fabric).
-moduledoc """
Runs the compact phi/noise topology as ordinary `hls_statem` processes while
presenting the `register_route` and `send` calls used by `hls_fabric`.

The normalized topology remains authoritative: this module instantiates every
family member, resolves wrapped route relations, queues normalized startup
messages while all actors are disconnected, and interprets the normalized
rectangle embeddings for host commands. The first noise-cutoff command is
delivered before activation; data and syndrome actors are then connected
before the phi actors, whose initial phase starts the decoder.

This is an example-local functional realization, not a CPU implementation of
the bounded physical fabric. Forwarders use ordinary Erlang mailboxes and
casts, so they provide neither bounded network backpressure nor the generated
fanout completion points. Ports from one actor with equal recipient sets share
one forwarding process, preserving that actor's output order across aliases.
An actor failure takes down this linked example-local process; this is not a
supervised deployment.

phi_memory_demo starts this CPU transport substitute; phi_memory_runner drives it through the same host call protocol as a device broker.
""".

-behavior(gen_server).

-include("../include/phi_protocol.hrl").

%% CPU transport lifecycle and debug targets.
-export([start_link/2, stop/1, debug_targets/1]).

%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(FABRIC_RX, '$hls_fabric_frame').

%% Logical instance identity used by this two-dimensional family realization.
-type actor_id() :: {atom(), non_neg_integer(), non_neg_integer()}.
%% An instantiated actor receives its output map before activation.
-type actor() :: #{
    id := actor_id(),
    family := atom(),
    coordinates := [non_neg_integer()],
    module := module(),
    pid := pid(),
    outputs => #{atom() => pid()}
}.
%% Instance lookup used while resolving routes, startup messages and rectangles.
-type actors() :: #{actor_id() => actor()}.
%% Normalization adds interface metadata beyond the fields used to start this example.
-type family() :: #{id := atom(), module := module(), shape := [pos_integer()], atom() => term()}.
%% A forwarding destination is either a local actor mailbox or an external event stream.
-type target() :: {actor, pid()} | {external, phi_memory_experiment:stream()}.
%% Normalized exact routes retain source identity and destination actor/stream identities.
-type route() :: #{
    source := {actor_id(), atom()},
    recipients := [{actor, actor_id()} | {external, phi_memory_experiment:stream()}],
    atom() => term()
}.
%% Inclusive physical coordinates selected by one routed host command.
-type rectangle() :: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}.
%% Normalized scale/offset maps a family member into the ingress coordinate space.
-type embedding() :: #{
    family := atom(), scale := [integer()], offset := [integer()], atom() => term()
}.
%% Broker-compatible call replies, including the scoped CPU debug catalog.
-type reply() :: ok | #{actors := map(), boundaries := []} | {error, term()}.

-record(route_owner, {
    pid :: pid(),
    monitor :: reference()
}).

-record(state, {
    plan :: hls_topology:plan(),
    boundary :: map(),
    actors :: map(),
    forwarders = [] :: [pid()],
    routes = #{} :: #{phi_memory_wire:route() => #route_owner{}},
    active = false :: boolean()
}).

-doc "Starts a disconnected CPU realization at one distance and noise rate.".
-spec start_link(pos_integer(), hls_nums:u32()) -> gen_server:start_ret().
start_link(Distance, NoiseRate) ->
    gen_server:start_link(?MODULE, {Distance, NoiseRate}, []).

-doc "Stops the fabric and all actor and forwarding processes it owns.".
-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:stop(Pid).

-doc "Returns scoped CPU debug targets indexed by logical topology identity.".
-spec debug_targets(pid()) -> #{actors := map(), boundaries := []}.
debug_targets(Pid) -> gen_server:call(Pid, debug_targets).

-doc "Normalizes the selected topology, starts linked actors and forwarding processes, and queues startup while every actor remains disconnected.".
-spec init({pos_integer(), hls_nums:u32()}) -> {ok, #state{}}.
init({Distance, NoiseRate}) ->
    Plan = hls_topology:normalize(
        phi_noise_topology:topology(Distance, NoiseRate)
    ),
    Boundary = phi_memory_boundary:contract(Distance),
    Actors = start_actors(maps:get(families, Plan)),
    {ConnectedActors, Forwarders} = prepare_outputs(Plan, Actors),
    queue_startup(maps:get(startup, Plan), ConnectedActors),
    {ok, #state{
        plan = Plan,
        boundary = Boundary,
        actors = ConnectedActors,
        forwarders = Forwarders
    }}.

-doc "Serves CPU debug bindings, monitored route ownership and deadline-checked host writes; rejects unknown requests.".
-spec handle_call(term(), gen_server:from(), #state{}) -> {reply, reply(), #state{}}.
%% Bind logical family identities to the currently instantiated CPU actors.
handle_call(debug_targets, _From, State = #state{plan = Plan, actors = Actors}) ->
    Processes = maps:from_list([
        {{family, Family, Coordinates}, Pid}
     || #{family := Family, coordinates := Coordinates, pid := Pid} <- maps:values(Actors)
    ]),
    {reply, hls_debug_catalog:cpu(Plan, Processes), State};
%% Keep one monitored live owner per route; an exited owner may be replaced.
handle_call(
    {register_route, Route, Owner},
    _From,
    State = #state{routes = Routes}
) when is_pid(Owner) ->
    case {valid_route(Route), Routes} of
        {true, #{Route := #route_owner{pid = Owner}}} ->
            {reply, ok, State};
        {true, #{
            Route := #route_owner{
                pid = Existing,
                monitor = OldMonitor
            }
        }} ->
            case is_process_alive(Existing) of
                true ->
                    {reply, {error, {route_in_use, Route, Existing}}, State};
                false ->
                    demonitor(OldMonitor, [flush]),
                    RouteOwner = monitor_owner(Owner),
                    {reply, ok, State#state{
                        routes = Routes#{Route => RouteOwner}
                    }}
            end;
        {true, _} ->
            RouteOwner = monitor_owner(Owner),
            {reply, ok, State#state{
                routes = Routes#{Route => RouteOwner}
            }};
        {false, _} ->
            {reply, {error, {invalid_route, Route}}, State}
    end;
%% Reject expired requests before decoding or delivering their commands.
handle_call({send, Route, Header, Payload, Deadline}, _From, State) ->
    case Deadline =/= infinity andalso Deadline =< erlang:monotonic_time(millisecond) of
        true -> {reply, {error, {not_sent, timeout}}, State};
        false -> send_command(Route, Header, Payload, State)
    end;
%% Preserve the broker-style error response for unsupported calls.
handle_call(Request, _From, State) ->
    {reply, {error, {invalid_request, Request}}, State}.

%% Validate the routed command before delivery; rejected decoding or inactive dispatch is reported as definitely not sent.
-spec send_command(phi_memory_wire:route(), phi_memory_wire:header(), binary(), #state{}) ->
    {reply, ok | {error, {not_sent, atom()}}, #state{}}.
send_command(Route, Header, Payload, State = #state{boundary = Boundary}) ->
    case phi_memory_wire:decode_command(Route, Header, Payload, Boundary) of
        {ok, Command} ->
            case dispatch_command(Command, State) of
                {ok, NextState} -> {reply, ok, NextState};
                {error, Reason} -> {reply, {error, {not_sent, Reason}}, State}
            end;
        {error, Reason} ->
            {reply, {error, {not_sent, Reason}}, State}
    end.

-doc "Ignores casts, including broker receipt acknowledgments: this functional CPU fabric has no bounded receive window.".
-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast(_Message, State) ->
    {noreply, State}.

-doc "Encodes external actor events for registered owners and removes routes when those owners exit; invalid actor events fail the fabric.".
-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
%% Deliver a validated routed frame only when its destination has a registered owner.
handle_info(
    {external_event, Stream, Event},
    State = #state{boundary = Boundary, routes = Routes}
) ->
    case phi_memory_wire:encode_event(Stream, Event, Boundary) of
        {ok, Route, Header, Payload} ->
            case Routes of
                #{Route := #route_owner{pid = Owner}} ->
                    gen_server:cast(
                        Owner,
                        {?FABRIC_RX, make_ref(), Route, Header, Payload}
                    );
                _ ->
                    ok
            end,
            {noreply, State};
        {error, Reason} ->
            error({event, Stream, Reason})
    end;
%% Remove only registrations owned by this exact process and monitor generation.
handle_info(
    {'DOWN', Monitor, process, Owner, _Reason},
    State = #state{routes = Routes}
) ->
    Remaining = maps:filter(
        fun(_Route, #route_owner{pid = Pid, monitor = Ref}) ->
            Pid =/= Owner orelse Ref =/= Monitor
        end,
        Routes
    ),
    {noreply, State#state{routes = Remaining}};
%% Unrelated mailbox traffic has no effect on the functional fabric.
handle_info(_Message, State) ->
    {noreply, State}.

-doc "Unlinks and shuts down every actor and forwarder owned by this CPU realization.".
-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, #state{actors = Actors, forwarders = Forwarders}) ->
    lists:foreach(
        fun(#{pid := Pid}) -> stop_owned(Pid) end,
        maps:values(Actors)
    ),
    lists:foreach(fun stop_owned/1, Forwarders),
    ok.

%%%
%%% Actor graph construction
%%%

%% Instantiate all normalized families into one logical-instance lookup.
-spec start_actors([family()]) -> actors().
start_actors(Families) ->
    lists:foldl(
        fun(Family, Acc0) ->
            start_family(Family, Acc0)
        end,
        #{},
        Families
    ).

%% Start one disconnected actor per two-dimensional family coordinate; reject other family dimensions.
-spec start_family(family(), actors()) -> actors().
start_family(
    #{id := FamilyId, module := Module, shape := [Width, Height]},
    Actors0
) ->
    lists:foldl(
        fun({X, Y}, Actors) ->
            Id = {FamilyId, X, Y},
            {ok, Pid} = Module:start_link(),
            Actors#{
                Id => #{
                    id => Id,
                    family => FamilyId,
                    coordinates => [X, Y],
                    module => Module,
                    pid => Pid
                }
            }
        end,
        Actors0,
        [
            {X, Y}
         || X <- lists:seq(0, Width - 1),
            Y <- lists:seq(0, Height - 1)
        ]
    );
start_family(#{id := Id, shape := Shape}, _Actors) ->
    error({family, Id, Shape}).

%% Resolve each instance's normalized routes into its connect map while retaining all created forwarders.
-spec prepare_outputs(hls_topology:plan(), actors()) -> {actors(), [pid()]}.
prepare_outputs(Plan, Actors) ->
    lists:foldl(
        fun({Id, Actor}, {ActorAcc, ForwarderAcc}) ->
            Routes = hls_topology:routes_for_instance(
                Plan,
                maps:get(family, Actor),
                maps:get(coordinates, Actor)
            ),
            {Outputs, Forwarders} = actor_outputs(
                Routes, Actors, ForwarderAcc
            ),
            {ActorAcc#{Id => Actor#{outputs => Outputs}}, Forwarders}
        end,
        {#{}, []},
        lists:sort(maps:to_list(Actors))
    ).

%% Use direct PIDs for singleton actor targets; share one ordered forwarder across ports with equal recipient sets.
-spec actor_outputs([route()], actors(), [pid()]) -> {#{atom() => pid()}, [pid()]}.
actor_outputs(Routes, Actors, Forwarders0) ->
    {Outputs, _Cache, Forwarders} = lists:foldl(
        fun(
            #{source := {_SourceId, Port}, recipients := Recipients},
            {OutputAcc, Cache0, ForwarderAcc}
        ) ->
            Targets = [
                resolve_target(Recipient, Actors)
             || Recipient <- Recipients
            ],
            case Targets of
                [{actor, Pid}] ->
                    {OutputAcc#{Port => Pid}, Cache0, ForwarderAcc};
                [_ | _] ->
                    Key = lists:sort(Targets),
                    case Cache0 of
                        #{Key := Pid} ->
                            {OutputAcc#{Port => Pid}, Cache0, ForwarderAcc};
                        _ ->
                            Owner = self(),
                            Pid = spawn_link(fun() ->
                                forwarder(Owner, Targets)
                            end),
                            {
                                OutputAcc#{Port => Pid},
                                Cache0#{Key => Pid},
                                [Pid | ForwarderAcc]
                            }
                    end
            end
        end,
        {#{}, #{}, Forwarders0},
        Routes
    ),
    {Outputs, Forwarders}.

%% Resolve a local actor identity to its PID while keeping external stream identities explicit.
-spec resolve_target({actor, actor_id()} | {external, phi_memory_experiment:stream()}, actors()) ->
    target().
resolve_target({actor, Id}, Actors) ->
    #{pid := Pid} = maps:get(Id, Actors),
    {actor, Pid};
resolve_target({external, Stream}, _Actors) ->
    {external, Stream}.

%% Queue all normalized startup casts before any actor is connected and can begin emitting.
-spec queue_startup(
    [#{target := actor_id(), delivery := cast, messages := [tuple()], atom() => term()}], actors()
) -> ok.
queue_startup(Startup, Actors) ->
    lists:foreach(
        fun(#{target := Target, delivery := cast, messages := Messages}) ->
            #{pid := Pid} = maps:get(Target, Actors),
            lists:foreach(
                fun(Message) -> hls_statem:cast(Pid, Message) end,
                Messages
            )
        end,
        Startup
    ).

%% Connect data and syndrome actors before phi actors start their initial decoder phase.
-spec activate(actors()) -> ok.
activate(Actors) ->
    {Phi, DataAndSyndrome} = lists:partition(
        fun({_Id, #{module := Module}}) -> Module =:= phi_halo_cell end,
        lists:sort(maps:to_list(Actors))
    ),
    lists:foreach(fun connect_actor/1, DataAndSyndrome),
    lists:foreach(fun connect_actor/1, Phi).

%% Require the actor's one-time connect operation to accept its resolved output map.
-spec connect_actor({actor_id(), actor()}) -> ok.
connect_actor({_Id, #{module := Module, pid := Pid, outputs := Outputs}}) ->
    ok = Module:connect(Pid, Outputs).

%%%
%%% Fabric ingress and egress
%%%

%% Queue the first cutoff before activation; other commands require an already active decoder.
-spec dispatch_command(phi_memory_experiment:command(), #state{}) ->
    {ok, #state{}} | {error, inactive}.
dispatch_command(
    Command = {_IngressId, _TargetId, _Rectangle, #noise_cutoff{}},
    State = #state{actors = Actors, active = false}
) ->
    Active = State#state{active = true},
    Delivered = deliver_command(Command, Active),
    activate(Actors),
    {ok, Delivered};
dispatch_command(_Command, #state{active = false}) ->
    %% The cutoff must be queued before the decoder emits its first request.
    {error, inactive};
dispatch_command(Command, State) ->
    {ok, deliver_command(Command, State)}.

%% Resolve the selected ingress target and cast the message to every embedded actor inside the rectangle.
-spec deliver_command(phi_memory_experiment:command(), #state{}) -> #state{}.
deliver_command(
    {IngressId, TargetId, Rectangle, Message},
    State = #state{plan = Plan, actors = Actors}
) ->
    [Ingress] = [
        Candidate
     || Candidate = #{id := Id} <- maps:get(ingresses, Plan),
        Id =:= IngressId
    ],
    [Target] = [
        Candidate
     || Candidate = #{id := Id} <- maps:get(targets, Ingress),
        Id =:= TargetId
    ],
    lists:foreach(
        fun(Pid) -> hls_statem:cast(Pid, Message) end,
        rectangle_recipients(Rectangle, Target, Actors)
    ),
    State.

%% Select actor PIDs by normalized embeddings and inclusive physical bounds in stable logical-instance order.
-spec rectangle_recipients(rectangle(), #{recipients := [embedding()], atom() => term()}, actors()) ->
    [pid()].
rectangle_recipients(Rectangle, #{recipients := Embeddings}, Actors) ->
    [
        Pid
     || {_Id, #{
            family := Family,
            coordinates := [X, Y],
            pid := Pid
        }} <- lists:sort(maps:to_list(Actors)),
        Embedding <- Embeddings,
        embedded(Family, X, Y, Embedding, Rectangle)
    ].

%% Apply a matching family's affine coordinate embedding and check membership in the requested rectangle.
-spec embedded(atom(), non_neg_integer(), non_neg_integer(), embedding(), rectangle()) -> boolean().
embedded(
    Family,
    X,
    Y,
    #{family := Family, scale := [ScaleX, ScaleY], offset := [DX, DY]},
    {X0, Y0, X1, Y1}
) ->
    EmbeddedX = ScaleX * X + DX,
    EmbeddedY = ScaleY * Y + DY,
    EmbeddedX >= X0 andalso EmbeddedX =< X1 andalso
        EmbeddedY >= Y0 andalso EmbeddedY =< Y1;
embedded(_Family, _X, _Y, _Embedding, _Rectangle) ->
    false.

%% Preserve mailbox order while copying each cast to local actors and reporting external events to the owner; never returns normally.
-spec forwarder(pid(), [target()]) -> no_return().
forwarder(Owner, Targets) ->
    receive
        {'$gen_cast', Message} ->
            lists:foreach(
                fun
                    ({actor, Pid}) -> hls_statem:cast(Pid, Message);
                    ({external, Stream}) -> Owner ! {external_event, Stream, Message}
                end,
                Targets
            ),
            forwarder(Owner, Targets)
    end.

%% Pair a route owner with the exact monitor reference used to remove stale registrations.
-spec monitor_owner(pid()) -> #route_owner{}.
monitor_owner(Owner) ->
    #route_owner{pid = Owner, monitor = monitor(process, Owner)}.

%% Accept exactly two unsigned 16-bit endpoint addresses at the untyped broker request boundary.
-spec valid_route(term()) -> boolean().
valid_route({Source, Destination}) ->
    is_integer(Source) andalso Source >= 0 andalso Source =< 16#ffff andalso
        is_integer(Destination) andalso Destination >= 0 andalso
        Destination =< 16#ffff;
valid_route(_Route) ->
    false.

%% Unlink before sending shutdown so cleanup cannot propagate the child's exit back into this server.
-spec stop_owned(pid()) -> true.
stop_owned(Pid) ->
    unlink(Pid),
    exit(Pid, shutdown).
