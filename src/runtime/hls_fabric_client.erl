-module(hls_fabric_client).
-moduledoc false.

%% A slot belongs to a submitted request until its reply arrives or the broker
%% proves it was not sent. Caller timeout/death cannot retire device work.
-export([new/4, request/5, cast/4, receive_frame/6, handle_info/2, info/1]).
-export_type([state/0]).

-define(TX_LIMIT, 1024).

-record(pending, {
    id :: reference(),
    from :: gen_server:from() | none,
    monitor :: reference() | none,
    context :: term()
}).
-record(client, {
    broker :: pid(),
    monitor :: reference(),
    route :: hls_fabric:route(),
    capacity :: 1..256,
    next = 0 :: byte(),
    pending = #{} :: #{byte() => #pending{}},
    sends = #{} :: gen_server:request_id_collection(),
    status = up :: up | {down, term()},
    rejected_requests = 0 :: non_neg_integer(),
    ignored_replies = 0 :: non_neg_integer()
}).
-opaque state() :: #client{}.

-spec new(pid(), 0..65535, 0..65535, 1..256) -> {ok, state()} | {error, term()}.
new(Broker, Local, Peer, Capacity) ->
    Monitor = monitor(process, Broker),
    case hls_fabric:register_route(Broker, {Peer, Local}, self()) of
        ok ->
            {ok, #client{broker = Broker, monitor = Monitor,
                route = {Local, Peer}, capacity = Capacity}};
        {error, _} = Error -> demonitor(Monitor, [flush]), Error
    end.

-spec request(byte(), binary(), term(), gen_server:from(), state()) -> state().
request(_Tag, _Payload, _Context, From, Client = #client{status = {down, Reason}}) ->
    gen_server:reply(From, {error, {transport_down, Reason}}), Client;
request(_Tag, _Payload, _Context, From, Client = #client{capacity = Capacity, pending = Pending})
        when map_size(Pending) =:= Capacity ->
    gen_server:reply(From, {error, transaction_limit}), Client;
request(Tag, Payload, Context, From = {Owner, _},
        Client = #client{next = Next, capacity = Capacity, pending = Pending, sends = Sends}) ->
    case gen_server:reqids_size(Sends) < ?TX_LIMIT of
        false ->
            gen_server:reply(From, {error, {not_sent, tx_limit}}),
            rejected(Client);
        true ->
            TxID = free_slot(Next, Capacity, Pending),
            ID = make_ref(),
            Entry = #pending{id = ID, from = From, monitor = monitor(process, Owner), context = Context},
            Reserved = Client#client{next = (TxID + 1) rem Capacity, pending = Pending#{TxID => Entry}},
            transmit(Tag, TxID, Payload, {request, TxID, ID}, Reserved)
    end.

free_slot(TxID, Capacity, Pending) ->
    case is_map_key(TxID, Pending) of
        false -> TxID;
        true -> free_slot((TxID + 1) rem Capacity, Capacity, Pending)
    end.

-spec cast(byte(), byte(), binary(), state()) -> state().
cast(_Tag, _TxID, _Payload, Client = #client{status = {down, _}}) -> Client;
cast(Tag, TxID, Payload, Client = #client{sends = Sends}) ->
    case gen_server:reqids_size(Sends) < ?TX_LIMIT of
        true -> transmit(Tag, TxID, Payload, cast, Client);
        %% Cast has no reply handle. Make rejection observable by closing this
        %% client, rather than silently dropping a command and continuing.
        false -> fail({cast_not_sent, tx_limit}, Client)
    end.

transmit(Tag, TxID, Payload, Label, Client = #client{broker = Broker, route = Route, sends = Sends}) ->
    Request = hls_fabric:send_request(Broker, Route, {Tag, TxID, 0}, Payload, 5000),
    Client#client{sends = gen_server:reqids_add(Request, Label, Sends)}.

-spec receive_frame(reference(), tuple(), tuple(), binary(), fun((byte(), binary(), term()) ->
    ignore | {reply, term()}), state()) -> state().
receive_frame(Receipt, Route, Header, Payload, Decode, Client = #client{broker = Broker}) ->
    Next = receive_reply(Route, Header, Payload, Decode, Client),
    hls_fabric:ack(Broker, Receipt),
    Next.

receive_reply({Peer, Local}, {Tag, TxID, 0}, Payload, Decode,
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
receive_reply(_Route, _Header, _Payload, _Decode, Client) -> ignored(Client).

ignored(Client = #client{ignored_replies = Count}) -> Client#client{ignored_replies = Count + 1}.
rejected(Client = #client{rejected_requests = Count}) -> Client#client{rejected_requests = Count + 1}.

-spec handle_info(term(), state()) -> state().
handle_info({'DOWN', Monitor, process, Broker, Reason}, Client = #client{monitor = Monitor, broker = Broker}) ->
    fail(Reason, Client);
handle_info(Message, Client = #client{sends = Sends}) ->
    case gen_server:check_response(Message, Sends, true) of
        {{reply, Result}, Label, Remaining} -> sent(Label, Result, Client#client{sends = Remaining});
        {{error, {Reason, _Broker}}, _Label, Remaining} -> fail(Reason, Client#client{sends = Remaining});
        _ -> caller_info(Message, Client)
    end.

sent(_Label, ok, Client) -> Client;
sent({request, TxID, ID}, {error, {not_sent, Reason}}, Client = #client{pending = Pending}) ->
    %% A response can precede its write completion. Correlate completion with
    %% the internal submission too, since the wire ID might already be reused.
    case Pending of
        #{TxID := #pending{id = ID} = Entry} ->
            finish(Entry, {error, {not_sent, Reason}}),
            rejected(Client#client{pending = maps:remove(TxID, Pending)});
        _ -> Client
    end;
sent(cast, {error, {not_sent, Reason}}, Client) -> fail({cast_not_sent, Reason}, Client);
sent(_Label, {error, Reason}, Client) -> fail({send_failed, Reason}, Client).

caller_info({'DOWN', Monitor, process, _Owner, _Reason}, Client = #client{pending = Pending}) ->
    Abandoned = maps:map(fun
        (_TxID, Entry = #pending{monitor = Ref}) when Ref =:= Monitor -> Entry#pending{from = none, monitor = none};
        (_TxID, Entry) -> Entry
    end, Pending),
    Client#client{pending = Abandoned};
caller_info(_Message, Client) -> Client.

fail(_Reason, Client = #client{status = {down, _}}) -> Client;
fail(Reason, Client = #client{pending = Pending, monitor = Monitor, sends = Sends}) ->
    maps:foreach(fun(_TxID, Entry) -> finish(Entry, {error, {transport_down, Reason}}) end, Pending),
    [gen_server:receive_response(Request, 0) || {Request, _} <- gen_server:reqids_to_list(Sends)],
    demonitor(Monitor, [flush]),
    Client#client{pending = #{}, sends = gen_server:reqids_new(), status = {down, Reason}}.

finish(#pending{from = none}, _Reply) -> ok;
finish(#pending{from = From, monitor = Monitor}, Reply) ->
    demonitor(Monitor, [flush]),
    gen_server:reply(From, Reply).

-spec info(state()) -> map().
info(#client{route = Route, status = Status, capacity = Capacity, sends = Sends,
        pending = Pending, ignored_replies = Ignored, rejected_requests = Rejected}) ->
    Abandoned = maps:fold(fun
        (_TxID, #pending{from = none}, Count) -> Count + 1;
        (_TxID, _Entry, Count) -> Count
    end, 0, Pending),
    #{route => Route, status => Status, capacity => Capacity,
        pending => map_size(Pending), abandoned => Abandoned,
        available => case Status of up -> Capacity - map_size(Pending); _ -> 0 end,
        transmitting => gen_server:reqids_size(Sends), transmit_capacity => ?TX_LIMIT,
        rejected_requests => Rejected, ignored_replies => Ignored}.
