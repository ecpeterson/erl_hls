-module(router).
-moduledoc """
An owner-supervised root routes rectangle broadcasts and barriers. Native targets
use a quadtree. A managed bank accepts declared casts as one rectangle packet;
other messages reach its enrolled endpoints from the same root.
""".
-behavior(gen_server).

%% Logical selections.
-export([rectangle/4, leaf/1, meet/2]).
%% Multicast and barriers.
-export([broadcast/3, broadcast/4, submit/3, barrier/3]).
%% Router lifecycle.
-export([start_link/4, start_link/5, stop/1]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export_type([position/0, rectangle/0, selection/0, fabric_route/0]).

%%%
%%% Types
%%%

%% Inclusive corners in the caller's coordinate system.
-record(rectangle, {x0, y0, x1, y1}).
-doc "Inclusive rectangle of logical sites.".
-type rectangle() :: #rectangle{
    x0 :: integer(),
    y0 :: integer(),
    x1 :: integer(),
    y1 :: integer()
}.

-doc "All sites or those inside an inclusive rectangle.".
-type selection() :: all | rectangle().

%% An interior node forwards to children; a leaf resolves the endpoint at send time.
-type children() :: #{rectangle() => {pid, pid()} | endpoint}.
-doc "Coordinates used by target registries and enrolled endpoints.".
-type position() :: {integer(), integer()}.
%% Inclusive logical bounds for the managed ingress after clipping logical coordinates.
-type bounds() :: {MinX :: integer(), MinY :: integer(), MaxX :: integer(), MaxY :: integer()}.
-doc "One deployed bank's cast tags, inclusive extent and incarnation-bound sites. Request translates logical bounds and builds one incarnation-bound endpoint call.".
-type fabric_route() :: #{
    request := fun((bounds(), tuple(), admitted | consumed) -> router_barrier:call()),
    casts := [atom()],
    sites := [{Position :: position(), Endpoint :: pid()}],
    extent := bounds()
}.
%% A marker is an inert multicast consumed after earlier work at each selected site.
-type barrier() :: #{request := term(), reply := term(), marker => tuple()}.
%% Each node owns its downstream send order and its outstanding subtree calls.
-record(state, {
    children :: children(),
    fabric :: #{atom() => fabric_route()},
    pending = #{} :: router_barrier:pending()
}).
%% A router and the receipts it still owes its callers.
-type state() :: #state{}.

-doc "Build a rectangle from its endpoints.".
-spec rectangle(integer(), integer(), integer(), integer()) -> rectangle().
rectangle(X0, Y0, X1, Y1) ->
    #rectangle{x0 = X0, y0 = Y0, x1 = X1, y1 = Y1}.

-doc "Test whether a rectangle is a singleton.".
-spec leaf(rectangle()) -> boolean().
leaf(#rectangle{x0 = X0, x1 = X0, y0 = Y0, y1 = Y0}) -> true;
leaf(#rectangle{}) -> false.

-doc "Test whether two rectangles intersect.".
-spec meet(selection(), selection()) -> boolean().
meet(all, _) ->
    true;
meet(_, all) ->
    true;
meet(
    #rectangle{x0 = X0_0, x1 = X1_0, y0 = Y0_0, y1 = Y1_0},
    #rectangle{x0 = X0_1, x1 = X1_1, y0 = Y0_1, y1 = Y1_1}
) ->
    not (X1_1 < X0_0 orelse X1_0 < X0_1 orelse Y1_1 < Y0_0 orelse Y1_0 < Y0_1).

%%%
%%% Public functions
%%%

-doc "Broadcast Message to all instances of Target which lie within Rectangle.".
-spec broadcast(selection(), atom(), any()) -> ok.
broadcast(Rectangle, Target, Message) ->
    broadcast(router, Rectangle, Target, Message).

-doc "Broadcast through the specified router PID or registered name.".
-spec broadcast(pid() | atom(), selection(), atom(), any()) -> ok.
broadcast(PID, Rectangle, Target, Message) ->
    gen_server:cast(PID, {broadcast, Rectangle, Target, Message}).

-doc "Submit a typed cast. A managed port can reject it, for example when busy or stale. A native root returns ok after forwarding; its quadtree has no admission receipt. Use the application barrier to wait for processing.".
-spec submit(rectangle(), module(), tuple()) -> ok | {error, term()}.
submit(Rectangle, Target, Message) ->
    gen_server:call(router, {broadcast, Rectangle, Target, Message}).

-doc """
Wait for every enrolled site in the selection to answer the given request with the
expected reply. An empty selection succeeds. A managed bank may use a supplied
inert marker whose consumption fences earlier work at each site. A PID receives
the point request directly from the caller, preserving its sender order. Supply a
marker only for a side-effect-free fence whose reply is independent of site data. Rejection, endpoint failure or timeout fails
the barrier.
""".
-spec barrier(pid() | selection(), module(), barrier()) -> ok | {error, term()}.
barrier(Pid, _, #{request := Request, reply := Expected}) when is_pid(Pid) ->
    router_barrier:point(Pid, Request, Expected);
barrier(Rect, Target, Barrier) ->
    gen_server:call(router, {barrier, Rect, Target, Barrier}, infinity).

%%%
%%% Server management
%%%

-doc "Start a root node router.".
-spec start_link(integer(), integer(), integer(), integer()) -> gen_server:start_ret().
start_link(X0, Y0, X1, Y1) ->
    start_link(X0, Y0, X1, Y1, #{}).

-doc "Start the registered root with incarnation-bound fabric routes for the selected banks.".
-spec start_link(integer(), integer(), integer(), integer(), #{atom() => fabric_route()}) ->
    gen_server:start_ret().
start_link(X0, Y0, X1, Y1, Fabric) ->
    Rectangle = #rectangle{x0 = X0, y0 = Y0, x1 = X1, y1 = Y1},
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Rectangle, Fabric], []).

-doc "Start an interior node router.".
-spec start_subrouter(rectangle()) -> {ok, pid()}.
start_subrouter(Rectangle) ->
    gen_server:start_link(?MODULE, [Rectangle, #{}], []).

-doc "Stop a router.".
-spec stop(pid()) -> ok.
stop(PID) ->
    gen_server:stop(PID).

%%%
%%% gen_server callbacks
%%%

-doc "Build linked child routers for the quadrants inside this node.".
%%% Subdivide this rectangle, spawn subrouters for its quadrants, package into
%%% a routing table.
-spec init([rectangle() | map()]) -> {ok, state()}.
init([Base = #rectangle{x0 = X0, y0 = Y0, x1 = X1, y1 = Y1}, Fabric]) ->
    Width = (X1 - X0) div 2,
    Height = (Y1 - Y0) div 2,
    Subrectangles =
        if
            X1 == X0 andalso Y1 == Y0 ->
                [Base];
            X1 == X0 ->
                [
                    Base#rectangle{y1 = Y0 + Height},
                    Base#rectangle{y0 = 1 + Y0 + Height}
                ];
            Y1 == Y0 ->
                [
                    Base#rectangle{x1 = X0 + Width},
                    Base#rectangle{x0 = 1 + X0 + Width}
                ];
            true ->
                [
                    Base#rectangle{x1 = X0 + Width, y1 = Y0 + Height},
                    Base#rectangle{x1 = X0 + Width, y0 = 1 + Y0 + Height},
                    Base#rectangle{x0 = 1 + X0 + Width, y1 = Y0 + Height},
                    Base#rectangle{x0 = 1 + X0 + Width, y0 = 1 + Y0 + Height}
                ]
        end,
    Subrouters =
        #{
            Subrectangle =>
                case leaf(Subrectangle) of
                    true ->
                        endpoint;
                    false ->
                        {ok, PID} = start_subrouter(Subrectangle),
                        {pid, PID}
                end
         || Subrectangle <- Subrectangles
        },

    {ok, #state{children = Subrouters, fabric = Fabric}}.

-doc "The node owns no external resources that require cleanup.".
-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
    ok.

-doc "Retain this node's routes and outstanding barriers across code loading.".
-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

-doc "Handle checked rectangle submissions and barriers without blocking further sends.".
-spec handle_call(
    {broadcast, selection(), module(), tuple()}
    | {barrier, selection(), module(), barrier()},
    gen_server:from(),
    state()
) ->
    {reply, ok | {error, term()}, state()} | {noreply, state()}.
%% A managed port returns its admission result, including a schema rejection.
handle_call({broadcast, Rect, Target, Message}, From, State = #state{fabric = Fabric}) when
    is_map_key(Target, Fabric)
->
    await(From, rectangle_calls(Rect, Message, admitted, maps:get(Target, Fabric)), State);
%% The native root can confirm forwarding only.
handle_call({broadcast, Rect, Target, Message}, _, State) ->
    {reply, forward(Rect, Target, Message, State), State};
%% Issue child calls here so they follow broadcasts from this router. Gather replies asynchronously.
handle_call({barrier, Rect, Target, Barrier}, From, State) ->
    await(From, barrier_calls(Rect, Target, Barrier, State), State).

%% Issue requests as this router so subsequent signals retain downstream order.
-spec await(gen_server:from() | unobserved, [router_barrier:call()], state()) -> {noreply, state()}.
await(From, Calls, State = #state{pending = Pending}) ->
    {noreply, State#state{pending = router_barrier:start(From, Calls, Pending)}}.

-doc "Forward an unchecked broadcast, surfacing rejection at the sending router.".
%% Choose packet submission only for a declared managed cast.
-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({broadcast, Rect, Target, Message}, State) ->
    case State#state.fabric of
        #{Target := #{casts := Casts} = Route} when is_tuple(Message), tuple_size(Message) > 0 ->
            case lists:member(element(1, Message), Casts) of
                true ->
                    await(unobserved, rectangle_calls(Rect, Message, admitted, Route), State);
                false ->
                    ok = forward(Rect, Target, Message, State),
                    {noreply, State}
            end;
        _ ->
            ok = forward(Rect, Target, Message, State),
            {noreply, State}
    end.

-doc "Dispatch downstream replies, failures and timeouts to pending barriers.".
%% Subtree receipts arrive alongside ordinary router traffic.
-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(Message, State = #state{pending = Pending}) ->
    {noreply, State#state{pending = router_barrier:receive_reply(Message, Pending)}}.

%% All commands for a hardware bank pass through this sender in submission order.
-spec forward(selection(), module(), term(), state()) -> ok | {error, term()}.
forward(Rect, Target, Message, #state{fabric = Fabric}) when is_map_key(Target, Fabric) ->
    #{sites := Sites} = maps:get(Target, Fabric),
    lists:foreach(
        fun({Site, Pid}) -> deliver(Target, Site, Pid, Message) end, members(Rect, Sites)
    );
%% Native targets retain per-leaf sender order.
forward(Rect, Target, Message, #state{children = Children}) ->
    lists:foreach(
        fun
            ({branch, Pid}) -> broadcast(Pid, Rect, Target, Message);
            ({Site, Pid}) -> deliver(Target, Site, Pid, Message)
        end,
        destinations(Rect, Target, Children)
    ).

%% Child routers and occupied sites intersecting this broadcast or barrier.
-spec destinations(selection(), module(), children()) -> [{branch | position(), pid()}].
destinations(Rect, Target, Children) ->
    lists:filtermap(
        fun
            ({_, {pid, Pid}}) ->
                {true, {branch, Pid}};
            ({#rectangle{x0 = X, y0 = Y}, endpoint}) ->
                case Target:whereis({X, Y}) of
                    undefined -> false;
                    Pid -> {true, {{X, Y}, Pid}}
                end
        end,
        [{Box, Child} || Box := Child <- Children, meet(Rect, Box)]
    ).

%% Hardware consumes one marker per selected site. Native calls return one receipt per subtree.
-spec barrier_calls(selection(), module(), barrier(), state()) -> [router_barrier:call()].
barrier_calls(Rect, Target, #{marker := Marker}, #state{fabric = Fabric}) when
    is_map_key(Target, Fabric)
->
    Route = maps:get(Target, Fabric),
    case members(Rect, maps:get(sites, Route)) of
        [] -> [];
        _ -> rectangle_calls(Rect, Marker, consumed, Route)
    end;
barrier_calls(Rect, Target, #{request := Req, reply := Reply}, #state{fabric = Fabric}) when
    is_map_key(Target, Fabric)
->
    [{Pid, Req, Reply} || {_, Pid} <- members(Rect, maps:get(sites, maps:get(Target, Fabric)))];
barrier_calls(Rect, Target, #{request := Req, reply := Reply} = Barrier, #state{children = Children}) ->
    [
        case Site of
            branch -> {Pid, {barrier, Rect, Target, Barrier}, ok};
            _ -> {Pid, Req, Reply}
        end
     || {Site, Pid} <- destinations(Rect, Target, Children)
    ].

%% Preserve target-specific host delivery at a quadtree leaf.
-spec deliver(module(), position(), pid(), term()) -> ok.
deliver(Target, Site, Pid, Message) ->
    case erlang:function_exported(Target, deliver, 3) of
        true -> Target:deliver(Site, Pid, Message);
        false -> gen_server:cast(Pid, Message)
    end.

%% The router may cover holes in a sparse bank.
-spec members(selection(), [{position(), pid()}]) -> [{position(), pid()}].
members(Rect, Sites) ->
    [Site || {{X, Y}, _} = Site <- Sites, meet(Rect, rectangle(X, Y, X, Y))].

%% Clip in logical coordinates before the deployment translates to hardware coordinates.
-spec rectangle_calls(selection(), tuple(), admitted | consumed, fabric_route()) ->
    [router_barrier:call()].
rectangle_calls(all, Msg, Completion, #{request := Request, extent := Extent}) ->
    [Request(Extent, Msg, Completion)];
rectangle_calls(
    #rectangle{x0 = X0, y0 = Y0, x1 = X1, y1 = Y1},
    Msg,
    Completion,
    #{request := Request, extent := {MinX, MinY, MaxX, MaxY}}
) ->
    case {max(X0, MinX), max(Y0, MinY), min(X1, MaxX), min(Y1, MaxY)} of
        {A, B, C, D} = Bounds when A =< C, B =< D -> [Request(Bounds, Msg, Completion)];
        _ -> []
    end.
