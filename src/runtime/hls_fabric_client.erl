-module(hls_fabric_client).
-moduledoc false.

%% Shared ownership for the routed application and management clients. A slot
%% belongs to a sent request until its reply arrives, even if its caller dies
%% or stops waiting. The wire has no cancellation or generation field.
-export([new/4, request/5, cast/4, receive_frame/5, down/2, info/1]).
-export_type([state/0]).

-record(pending, {
    from :: gen_server:from() | none,
    monitor :: reference() | none,
    context :: term()
}).
-record(client, {
    broker :: pid(),
    monitor :: reference(),
    route :: {0..65535, 0..65535},
    capacity :: 1..256,
    next = 0 :: byte(),
    pending = #{} :: #{byte() => #pending{}},
    status = up :: up | {down, term()},
    ignored_replies = 0 :: non_neg_integer()
}).
-opaque state() :: #client{}.

-spec new(pid(), 0..65535, 0..65535, 1..256) ->
    {ok, state()} | {error, term()}.
new(Broker, Local, Peer, Capacity) ->
    Monitor = monitor(process, Broker),
    case hls_fabric:register_route(Broker, {Peer, Local}, self()) of
        ok ->
            {ok, #client{broker = Broker, monitor = Monitor,
                route = {Local, Peer}, capacity = Capacity}};
        {error, _} = Error ->
            demonitor(Monitor, [flush]),
            Error
    end.

-spec request(byte(), binary(), term(), gen_server:from(), state()) -> state().
request(_Tag, _Payload, _Context, From, Client = #client{status = {down, Reason}}) ->
    gen_server:reply(From, {error, {transport_down, Reason}}),
    Client;
request(_Tag, _Payload, _Context, From,
        Client = #client{capacity = Capacity, pending = Pending})
        when map_size(Pending) =:= Capacity ->
    gen_server:reply(From, {error, transaction_limit}),
    Client;
request(Tag, Payload, Context, From = {Owner, _},
        Client = #client{next = Next, capacity = Capacity, pending = Pending}) ->
    TxID = free_slot(Next, Capacity, Pending),
    Entry = #pending{from = From, monitor = monitor(process, Owner), context = Context},
    Reserved = Client#client{next = (TxID + 1) rem Capacity,
        pending = Pending#{TxID => Entry}},
    transmit(Tag, TxID, Payload, Reserved).

free_slot(TxID, Capacity, Pending) ->
    case is_map_key(TxID, Pending) of
        false -> TxID;
        true -> free_slot((TxID + 1) rem Capacity, Capacity, Pending)
    end.

-spec cast(byte(), byte(), binary(), state()) -> state().
cast(_Tag, _TxID, _Payload, Client = #client{status = {down, _}}) -> Client;
cast(Tag, TxID, Payload, Client) -> transmit(Tag, TxID, Payload, Client).

transmit(Tag, TxID, Payload, Client = #client{broker = Broker, route = Route}) ->
    %% A failed write or call can follow partial transmission. Close this
    %% client to new work; never retry or recycle its IDs in this session.
    try hls_fabric:send(Broker, Route, {Tag, TxID, 0}, Payload) of
        ok -> Client;
        {error, Reason} -> fail({send_failed, Reason}, Client)
    catch
        exit:Reason -> fail({send_failed, Reason}, Client)
    end.

-spec receive_frame(tuple(), tuple(), binary(), fun((byte(), binary(), term()) ->
    ignore | {reply, term()}), state()) -> state().
receive_frame({Peer, Local}, {Tag, TxID, 0}, Payload, Decode,
        Client = #client{route = {Local, Peer}, pending = Pending}) ->
    case Pending of
        #{TxID := #pending{context = Context} = Entry} ->
            case Decode(Tag, Payload, Context) of
                {reply, Reply} ->
                    finish(Entry, Reply),
                    Client#client{pending = maps:remove(TxID, Pending)};
                ignore -> ignored(Client)
            end;
        #{} -> ignored(Client)
    end;
receive_frame(_Route, _Header, _Payload, _Decode, Client) -> ignored(Client).

ignored(Client = #client{ignored_replies = Count}) ->
    Client#client{ignored_replies = Count + 1}.

-spec down(tuple(), state()) -> state().
down({'DOWN', Monitor, process, Broker, Reason},
        Client = #client{monitor = Monitor, broker = Broker}) ->
    fail(Reason, Client);
down({'DOWN', Monitor, process, _Owner, _Reason}, Client = #client{pending = Pending}) ->
    Abandoned = maps:map(fun
        (_TxID, Entry = #pending{monitor = Ref}) when Ref =:= Monitor ->
            Entry#pending{from = none, monitor = none};
        (_TxID, Entry) -> Entry
    end, Pending),
    Client#client{pending = Abandoned}.

fail(Reason, Client = #client{pending = Pending, monitor = Monitor}) ->
    maps:foreach(fun(_TxID, Entry) -> finish(Entry, {error, {transport_down, Reason}}) end,
        Pending),
    demonitor(Monitor, [flush]),
    Client#client{pending = #{}, status = {down, Reason}}.

finish(#pending{from = none}, _Reply) -> ok;
finish(#pending{from = From, monitor = Monitor}, Reply) ->
    demonitor(Monitor, [flush]),
    gen_server:reply(From, Reply).

-spec info(state()) -> map().
info(#client{route = Route, status = Status, capacity = Capacity,
        pending = Pending, ignored_replies = Ignored}) ->
    Abandoned = maps:fold(fun
        (_TxID, #pending{from = none}, Count) -> Count + 1;
        (_TxID, _Entry, Count) -> Count
    end, 0, Pending),
    #{route => Route, status => Status, capacity => Capacity,
        pending => map_size(Pending), abandoned => Abandoned,
        available => case Status of up -> Capacity - map_size(Pending); _ -> 0 end,
        ignored_replies => Ignored}.
