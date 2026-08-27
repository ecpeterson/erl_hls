-module(xls_fabric).
-module_doc """
Owns one routed frame transport and dispatches replies to Erlang proxy
processes by their registered return route. Application and debug paths use
separate instances so their queues and failure domains remain independent.

The routing source is adapter metadata: it selects the host-side proxy and is
not delivered as a sender identity inside the process's ordinary message. A
future distribution adapter may map bounded fabric endpoints to Erlang process
identities at its boundary.
""".

-behavior(gen_server).

-export([start_link/2, stop/1]).
-export([register_route/3, send/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(RX_FRAME, '$xls_fabric_frame').

-type endpoint() :: 0..65535.
-type route() :: {
    Source :: endpoint(),
    Destination :: endpoint()
}.
-type header() :: {
    Tag :: byte(),
    TxID :: byte(),
    Flags :: byte()
}.

-record(route_owner, {
    pid :: pid(),
    monitor :: reference()
}).

-record(frame, {
    route :: route(),
    header :: header(),
    payload :: binary()
}).

-record(state, {
    fd :: file:io_device(),
    listener :: pid(),
    routes = #{} :: #{route() => #route_owner{}}
}).

start_link(WritePath, ReadPath) ->
    gen_server:start_link(?MODULE, {WritePath, ReadPath}, []).

stop(Pid) ->
    gen_server:stop(Pid).

-spec register_route(pid(), route(), pid()) -> ok | {error, term()}.
register_route(Pid, Route, Owner) ->
    gen_server:call(Pid, {register_route, Route, Owner}).

-spec send(pid(), route(), header(), binary()) -> ok | {error, term()}.
send(Pid, Route, Header, Payload) ->
    gen_server:call(Pid, {send, Route, Header, Payload}).

init({WritePath, ReadPath}) ->
    {ok, FDWrite} = file:open(WritePath, [write, raw, binary]),
    Self = self(),
    Listener = spawn_link(fun() ->
        {ok, FDRead} = file:open(ReadPath, [read, raw, binary]),
        listener(FDRead, Self)
    end),
    %% TODO: Define the supervision relationship among the two physical-path
    %% brokers and their proxy clients. In particular, choose how broker death,
    %% proxy restart, and endpoint re-registration propagate through the tree.
    {ok, #state{fd = FDWrite, listener = Listener}}.

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
                    Monitor = monitor(process, Owner),
                    RouteOwner = #route_owner{
                        pid = Owner,
                        monitor = Monitor
                    },
                    {reply, ok, State#state{
                        routes = Routes#{Route => RouteOwner}
                    }}
            end;
        {true, _} ->
            Monitor = monitor(process, Owner),
            RouteOwner = #route_owner{pid = Owner, monitor = Monitor},
            {reply, ok, State#state{
                routes = Routes#{Route => RouteOwner}
            }};
        {false, _} ->
            {reply, {error, {invalid_route, Route}}, State}
    end;
handle_call(
    {send, Route, Header, Payload},
    _From,
    State = #state{fd = FD}
) ->
    Frame = #frame{route = Route, header = Header, payload = Payload},
    case encode_frame(Frame) of
        {ok, EncodedFrame} ->
            {reply, file:write(FD, EncodedFrame), State};
        {error, _Reason} = Error ->
            {reply, Error, State}
    end;
handle_call(Request, _From, State) ->
    {reply, {error, {invalid_request, Request}}, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info(
    #frame{route = Route, header = Header, payload = Payload},
    State = #state{routes = Routes}
) ->
    case Routes of
        #{Route := #route_owner{pid = Owner}} ->
            gen_server:cast(Owner, {?RX_FRAME, Header, Payload});
        _ ->
            ok
    end,
    {noreply, State};
handle_info(
    {'DOWN', Monitor, process, Owner, _Reason},
    State = #state{routes = Routes}
) ->
    NewRoutes = maps:filter(
        fun(_Route, #route_owner{pid = Pid, monitor = Ref}) ->
            Pid =/= Owner orelse Ref =/= Monitor
        end,
        Routes
    ),
    {noreply, State#state{routes = NewRoutes}};
handle_info(_Message, State) ->
    {noreply, State}.

terminate(_Reason, #state{fd = FD, listener = Listener}) ->
    try
        unlink(Listener),
        exit(Listener, shutdown)
    after
        file:close(FD)
    end,
    ok.

-spec encode_frame(#frame{}) -> {ok, binary()} | {error, term()}.
encode_frame(#frame{
    route = {Source, Destination},
    header = {Tag, TxID, Flags},
    payload = Payload
})
        when is_integer(Source), Source >= 0, Source =< 16#ffff,
             is_integer(Destination), Destination >= 0,
             Destination =< 16#ffff,
             is_integer(Tag), Tag >= 0, Tag =< 16#ff,
             is_integer(TxID), TxID >= 0, TxID =< 16#ff,
             is_integer(Flags), Flags >= 0, Flags =< 16#ff,
             is_binary(Payload) ->
    case byte_size(Payload) of
        Size when Size rem 4 =/= 0 ->
            {error, {unaligned_payload, Size}};
        Size when Size > 16#ff * 4 ->
            {error, {payload_too_large, Size}};
        Size ->
            PayloadWords = Size div 4,
            Route = <<Destination:16/little, Source:16/little>>,
            Header = <<PayloadWords:8, TxID:8, Flags:8, Tag:8>>,
            {ok, <<Route/binary, Header/binary, Payload/binary>>}
    end;
encode_frame(Frame) ->
    {error, {invalid_frame, Frame}}.

valid_route({Source, Destination}) ->
    is_integer(Source) andalso Source >= 0 andalso Source =< 16#ffff andalso
        is_integer(Destination) andalso Destination >= 0 andalso
        Destination =< 16#ffff;
valid_route(_Route) ->
    false.

listener(FD, Parent) ->
    {ok, <<Destination:16/little, Source:16/little>>} = read_exact(FD, 4),
    {ok, <<PayloadLength:8, TxID:8, Flags:8, Tag:8>>} = read_exact(FD, 4),
    {ok, Payload} = read_exact(FD, 4 * PayloadLength),
    Parent ! #frame{
        route = {Source, Destination},
        header = {Tag, TxID, Flags},
        payload = Payload
    },
    listener(FD, Parent).

read_exact(_FD, 0) ->
    {ok, <<>>};
read_exact(FD, Length) ->
    read_exact(FD, Length, <<>>).

read_exact(_FD, Length, Acc) when byte_size(Acc) =:= Length ->
    {ok, Acc};
read_exact(FD, Length, Acc) ->
    case file:read(FD, Length - byte_size(Acc)) of
        {ok, Bytes} -> read_exact(FD, Length, <<Acc/binary, Bytes/binary>>);
        eof -> {error, unexpected_eof};
        {error, Reason} -> {error, Reason}
    end.
