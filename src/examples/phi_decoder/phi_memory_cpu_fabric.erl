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
""".

-behavior(gen_server).

-include("phi_protocol.hrl").

-export([start_link/2, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(FABRIC_RX, '$hls_fabric_frame').

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

handle_call(
    {register_route, Route, Owner},
    _From,
    State = #state{routes = Routes}
) when is_pid(Owner) ->
    case {valid_route(Route), Routes} of
        {true, #{Route := #route_owner{pid = Owner}}} ->
            {reply, ok, State};
        {true, #{Route := #route_owner{
            pid = Existing,
            monitor = OldMonitor
        }}} ->
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
handle_call(
    {send, Route, Header, Payload},
    _From,
    State = #state{boundary = Boundary}
) ->
    case phi_memory_wire:decode_command(Route, Header, Payload, Boundary) of
        {ok, Command} ->
            case dispatch_command(Command, State) of
                {ok, NextState} -> {reply, ok, NextState};
                {error, Reason} -> {reply, {error, Reason}, State}
            end;
        {error, _Reason} = Error ->
            {reply, Error, State}
    end;
handle_call(Request, _From, State) ->
    {reply, {error, {invalid_request, Request}}, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

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
                        {?FABRIC_RX, Route, Header, Payload}
                    );
                _ ->
                    ok
            end,
            {noreply, State};
        {error, Reason} ->
            error({event, Stream, Reason})
    end;
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
handle_info(_Message, State) ->
    {noreply, State}.

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

start_actors(Families) ->
    lists:foldl(
        fun(Family, Acc0) ->
            start_family(Family, Acc0)
        end,
        #{},
        Families
    ).

start_family(
    #{id := FamilyId, module := Module, shape := [Width, Height]},
    Actors0
) ->
    lists:foldl(
        fun({X, Y}, Actors) ->
            Id = {FamilyId, X, Y},
            {ok, Pid} = Module:start_link(),
            Actors#{Id => #{
                id => Id,
                family => FamilyId,
                coordinates => [X, Y],
                module => Module,
                pid => Pid
            }}
        end,
        Actors0,
        [{X, Y} || X <- lists:seq(0, Width - 1),
                   Y <- lists:seq(0, Height - 1)]
    );
start_family(#{id := Id, shape := Shape}, _Actors) ->
    error({family, Id, Shape}).

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

actor_outputs(Routes, Actors, Forwarders0) ->
    {Outputs, _Cache, Forwarders} = lists:foldl(
        fun(
            #{source := {_SourceId, Port}, recipients := Recipients},
            {OutputAcc, Cache0, ForwarderAcc}
        ) ->
            Targets = [resolve_target(Recipient, Actors)
                || Recipient <- Recipients],
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

resolve_target({actor, Id}, Actors) ->
    #{pid := Pid} = maps:get(Id, Actors),
    {actor, Pid};
resolve_target({external, Stream}, _Actors) ->
    {external, Stream}.

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

activate(Actors) ->
    {Phi, DataAndSyndrome} = lists:partition(
        fun({_Id, #{module := Module}}) -> Module =:= phi_halo_cell end,
        lists:sort(maps:to_list(Actors))
    ),
    lists:foreach(fun connect_actor/1, DataAndSyndrome),
    lists:foreach(fun connect_actor/1, Phi).

connect_actor({_Id, #{module := Module, pid := Pid, outputs := Outputs}}) ->
    ok = Module:connect(Pid, Outputs).

%%%
%%% Fabric ingress and egress
%%%

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

forwarder(Owner, Targets) ->
    receive
        {'$gen_cast', Message} ->
            lists:foreach(
                fun
                    ({actor, Pid}) -> hls_statem:cast(Pid, Message);
                    ({external, Stream}) ->
                        Owner ! {external_event, Stream, Message}
                end,
                Targets
            ),
            forwarder(Owner, Targets)
    end.

monitor_owner(Owner) ->
    #route_owner{pid = Owner, monitor = monitor(process, Owner)}.

valid_route({Source, Destination}) ->
    is_integer(Source) andalso Source >= 0 andalso Source =< 16#ffff andalso
        is_integer(Destination) andalso Destination >= 0 andalso
        Destination =< 16#ffff;
valid_route(_Route) ->
    false.

stop_owned(Pid) ->
    unlink(Pid),
    exit(Pid, shutdown).
