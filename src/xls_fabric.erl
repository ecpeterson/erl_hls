-module(xls_fabric).
-module_doc """
Owns one routed frame transport and dispatches replies to Erlang proxy
processes by their remote fabric endpoint. Application and debug paths use
separate instances so their queues and failure domains remain independent.
""".

-behavior(gen_server).

-export([start_link/2, stop/1]).
-export([register_peer/3, unregister_peer/2, send/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(RX_FRAME, '$xls_fabric_frame').

-record(peer, {
    pid :: pid(),
    monitor :: reference()
}).

-record(state, {
    fd :: file:io_device(),
    listener :: pid(),
    peers = #{} :: #{0..65535 => #peer{}}
}).

start_link(WritePath, ReadPath) ->
    gen_server:start_link(?MODULE, {WritePath, ReadPath}, []).

stop(Pid) ->
    gen_server:stop(Pid).

register_peer(Pid, Endpoint, Owner) ->
    gen_server:call(Pid, {register_peer, Endpoint, Owner}).

unregister_peer(Pid, Endpoint) ->
    gen_server:call(Pid, {unregister_peer, Endpoint, self()}).

send(Pid, Source, Destination, Frame) ->
    gen_server:call(Pid, {send, Source, Destination, Frame}).

init({WritePath, ReadPath}) ->
    {ok, FDWrite} = file:open(WritePath, [write, raw, binary]),
    Self = self(),
    Listener = spawn_link(fun() ->
        {ok, FDRead} = file:open(ReadPath, [read, raw, binary]),
        listener(FDRead, Self)
    end),
    {ok, #state{fd = FDWrite, listener = Listener}}.

handle_call(
    {register_peer, Endpoint, Owner},
    _From,
    State = #state{peers = Peers}
) when is_integer(Endpoint), Endpoint >= 0, Endpoint =< 16#ffff, is_pid(Owner) ->
    case maps:find(Endpoint, Peers) of
        error ->
            Monitor = monitor(process, Owner),
            Peer = #peer{pid = Owner, monitor = Monitor},
            {reply, ok, State#state{peers = Peers#{Endpoint => Peer}}};
        {ok, #peer{pid = Owner}} ->
            {reply, ok, State};
        {ok, #peer{pid = Existing}} ->
            {reply, {error, {endpoint_in_use, Endpoint, Existing}}, State}
    end;
handle_call(
    {unregister_peer, Endpoint, Owner},
    _From,
    State = #state{peers = Peers}
) ->
    case maps:find(Endpoint, Peers) of
        {ok, #peer{pid = Owner, monitor = Monitor}} ->
            demonitor(Monitor, [flush]),
            {reply, ok, State#state{peers = maps:remove(Endpoint, Peers)}};
        error ->
            {reply, ok, State};
        {ok, #peer{pid = Existing}} ->
            {reply, {error, {not_endpoint_owner, Endpoint, Existing}}, State}
    end;
handle_call(
    {send, Source, Destination, Frame},
    _From,
    State = #state{fd = FD}
) ->
    case validate_frame(Source, Destination, Frame) of
        ok ->
            Route = <<Destination:16/little, Source:16/little>>,
            {reply, file:write(FD, <<Route/binary, Frame/binary>>), State};
        {error, _Reason} = Error ->
            {reply, Error, State}
    end;
handle_call(Request, _From, State) ->
    {reply, {error, {invalid_request, Request}}, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info(
    {?RX_FRAME, Source, Destination, Header, Payload},
    State = #state{peers = Peers}
) ->
    case maps:find(Source, Peers) of
        {ok, #peer{pid = Owner}} ->
            gen_server:cast(Owner, {
                ?RX_FRAME, Source, Destination, Header, Payload
            });
        error ->
            ok
    end,
    {noreply, State};
handle_info(
    {'DOWN', Monitor, process, Owner, _Reason},
    State = #state{peers = Peers}
) ->
    NewPeers = maps:filter(
        fun(_Endpoint, #peer{pid = Pid, monitor = Ref}) ->
            Pid =/= Owner orelse Ref =/= Monitor
        end,
        Peers
    ),
    {noreply, State#state{peers = NewPeers}};
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

validate_frame(Source, Destination, <<PayloadWords:8, _/binary>> = Frame)
        when is_integer(Source), Source >= 0, Source =< 16#ffff,
             is_integer(Destination), Destination >= 0,
             Destination =< 16#ffff ->
    case byte_size(Frame) of
        Size when Size =:= 4 + PayloadWords * 4 -> ok;
        Size -> {error, {invalid_frame_size, 4 + PayloadWords * 4, Size}}
    end;
validate_frame(Source, Destination, Frame) ->
    {error, {invalid_frame, Source, Destination, Frame}}.

listener(FD, Parent) ->
    {ok, <<Destination:16/little, Source:16/little>>} = read_exact(FD, 4),
    {ok, <<PayloadLength:8, _/binary>> = Header} = read_exact(FD, 4),
    {ok, Payload} = read_exact(FD, 4 * PayloadLength),
    Parent ! {?RX_FRAME, Source, Destination, Header, Payload},
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
