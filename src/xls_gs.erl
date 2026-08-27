-module(xls_gs).
-export([start_link/2, start_link/3, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3]).
-export([generic_unpack/2]).
-behavior(gen_server).

%%%
%%% behavior definition
%%%

-type init_arg() :: any().
-type in_record() :: any().
-type out_record() :: any().
-type state() :: any().

-callback init(init_arg()) -> state().
%% TODO: we would like to support the whole breadth of gen_server results across
%%       both handlers!
-callback handle_call(in_record(), state()) -> {reply, out_record(), state()}.
-callback handle_cast(in_record(), state()) -> {noreply, state()}.

-record(state, {
    module :: module(),
    fd = none :: none | file:io_device(),
    listener = none :: none | pid(),
    fabric = none :: none | {pid(), 0..65535, 0..65535},
    pending = #{} :: #{0..255 => gen_server:from()},
    tx_id = 0 :: 0..255,
    state :: state()
}).

%%%
%%% server management
%%%

start_link(Module, Arg) ->
    start_link(Module, Arg, []).
start_link(Module, Arg, Options) ->
    gen_server:start_link(?MODULE, {Module, Arg, Options}, []).

stop(PID) ->
    gen_server:stop(PID).

%%%
%%% gen_server implementation
%%%

-define(DEVICE_NODE, "/dev/axismsg0").
-define(RX_SIGIL, '$pl_message').
-define(FABRIC_RX, '$xls_fabric_frame').
-define(ERROR_FUNCTION_CLAUSE, 1).
-define(ERROR_MATCH_FAILURE, 2).

-record(header, {
    tag :: 0..255,
    tx_id :: 0..255,
    flags = 0 :: 0..255
    % implicit payload length
}).

init({Module, Arg, Options}) ->
    GS = case transport(Options) of
        cpu ->
            #state{state = Module:init(Arg), module = Module};
        {fabric, Broker, LocalEndpoint, PeerEndpoint} ->
            ok = xls_fabric:register_peer(Broker, PeerEndpoint, self()),
            #state{
                module = Module,
                fabric = {Broker, LocalEndpoint, PeerEndpoint}
            };
        {WritePath, ReadPath} ->
            {ok, FDWrite} = file:open(WritePath, [write, raw, binary]),
            Self = self(),
            Listener = spawn_link(fun () ->
                {ok, FDRead} = file:open(ReadPath, [read, raw, binary]),
                listener(FDRead, Self)
            end),
            #state{module = Module, fd = FDWrite, listener = Listener}
    end,
    {ok, GS}.

handle_call(
    Message,
    _From,
    GS = #state{module = Module, state = State, fd = none, fabric = none}
) ->
    {reply, Reply, NewState} = Module:handle_call(Message, State),
    {reply, Reply, GS#state{state = NewState}};
handle_call(Message, From, GS = #state{module = Module}) ->
    Tag = element(1, Message),
    Header = #header{tag = Module:pack_tag(Tag), tx_id = GS#state.tx_id},
    Payload = Module:pack(Message),
    ok = transmit(GS, Header, Payload),
    {noreply, GS#state{
        tx_id = (GS#state.tx_id + 1) rem 256,
        pending = (GS#state.pending)#{GS#state.tx_id => From}
    }}.

handle_cast(
    Message,
    GS = #state{module = Module, state = State, fd = none, fabric = none}
) ->
    {noreply, NewState} = Module:handle_cast(Message, State),
    {noreply, GS#state{state = NewState}};
handle_cast({?RX_SIGIL, Header, Payload}, GS = #state{module = Module}) ->
    handle_reply(Header, Payload, Module, GS);
handle_cast(
    {?FABRIC_RX, PeerEndpoint, LocalEndpoint, PackedHeader, Payload},
    GS = #state{
        module = Module,
        fabric = {_Broker, LocalEndpoint, PeerEndpoint}
    }
) ->
    <<_PayloadLength:8, TxID:8, Flags:8, Tag:8>> = PackedHeader,
    Header = #header{tag = Tag, tx_id = TxID, flags = Flags},
    handle_reply(Header, Payload, Module, GS);
handle_cast({?FABRIC_RX, _Source, _Destination, _Header, _Payload}, GS) ->
    {noreply, GS};
handle_cast(Message, GS = #state{module = Module}) ->
    Tag = element(1, Message),
    Header = #header{tag = Module:pack_tag(Tag), tx_id = GS#state.tx_id},
    Payload = Module:pack(Message),
    ok = transmit(GS, Header, Payload),
    {noreply, GS#state{
        tx_id = (GS#state.tx_id + 1) rem 256
    }}.

handle_reply(Header, Payload, Module, GS) ->
    {From, NewPending} = maps:take(Header#header.tx_id, GS#state.pending),
    Tag = Module:unpack_tag(Header#header.tag),
    {Reply, << >>} = unpack_reply(Module, Tag, Payload),
    gen_server:reply(From, Reply),
    {noreply, GS#state{pending = NewPending}}.

terminate(_Reason, #state{fd = FD, listener = Listener, fabric = Fabric}) ->
    try
        case Listener of
            none -> ok;
            _ ->
                unlink(Listener),
                exit(Listener, shutdown)
        end
    after
        case FD of
            none -> ok;
            _ -> file:close(FD)
        end
    end,
    case Fabric of
        none -> ok;
        {Broker, _LocalEndpoint, PeerEndpoint} ->
            xls_fabric:unregister_peer(Broker, PeerEndpoint)
    end,
    ok.

code_change(_OldVsn, GS, _Extra) ->
    {ok, GS}.

%%%
%%% Helper
%%%

transmit(#state{fd = FH, fabric = none}, Header, Payload) ->
    PackedHeader = <<
        (size(Payload) div 4):8/integer,
        (Header#header.tx_id):8/integer,
        (Header#header.flags):8/integer,
        (Header#header.tag):8/integer
    >>,
    file:write(FH, <<PackedHeader/binary, Payload/binary>>);
transmit(
    #state{fabric = {Broker, LocalEndpoint, PeerEndpoint}},
    Header,
    Payload
) ->
    PackedHeader = <<
        (size(Payload) div 4):8/integer,
        (Header#header.tx_id):8/integer,
        (Header#header.flags):8/integer,
        (Header#header.tag):8/integer
    >>,
    xls_fabric:send(
        Broker,
        LocalEndpoint,
        PeerEndpoint,
        <<PackedHeader/binary, Payload/binary>>
    ).

transport(Options) ->
    case lists:keyfind(fabric, 1, Options) of
        {fabric, Broker, PeerEndpoint} ->
            {fabric, Broker, 0, PeerEndpoint};
        false ->
            file_transport(Options)
    end.

file_transport(Options) ->
    case lists:keyfind(transport, 1, Options) of
        {transport, WritePath, ReadPath} ->
            {WritePath, ReadPath};
        false ->
            case lists:member(pl, Options) of
                true -> {?DEVICE_NODE, ?DEVICE_NODE};
                false -> cpu
            end
    end.

%%%
%%% Subordinate process which listens on the character device
%%%

listener(FH, Parent) ->
    {ok, Header} = read_exact(FH, 4),
    <<
        PayloadLength:8/integer,
        TxID:8/integer,
        Flags:8/integer,
        Tag:8/integer
    >> = Header,
    UnpackedHeader = #header{tag = Tag, tx_id = TxID, flags = Flags},
    {ok, Payload} = read_exact(FH, 4*PayloadLength),
    gen_server:cast(Parent, {?RX_SIGIL, UnpackedHeader, Payload}),
    listener(FH, Parent).

read_exact(_FH, 0) ->
    {ok, <<>>};
read_exact(FH, Length) ->
    read_exact(FH, Length, <<>>).

read_exact(_FH, Length, Acc) when byte_size(Acc) =:= Length ->
    {ok, Acc};
read_exact(FH, Length, Acc) ->
    case file:read(FH, Length - byte_size(Acc)) of
        {ok, Bytes} -> read_exact(FH, Length, <<Acc/binary, Bytes/binary>>);
        eof -> {error, unexpected_eof};
        {error, Reason} -> {error, Reason}
    end.

unpack_reply(_Module, error, <<ErrorCode:32/little-unsigned-integer, Rest/binary>>) ->
    {{error, {remote_error, error_reason(ErrorCode)}}, Rest};
unpack_reply(_Module, error, Payload) ->
    {{error, {remote_error, {malformed_error, Payload}}}, <<>>};
unpack_reply(Module, Tag, Payload) ->
    Module:unpack(Tag, Payload).

error_reason(?ERROR_FUNCTION_CLAUSE) -> function_clause;
error_reason(?ERROR_MATCH_FAILURE) -> match_failure;
error_reason(ErrorCode) -> {unknown_error, ErrorCode}.

%%%
%%% Utilities for un/pack
%%%

generic_unpack(Descriptors, Binary) ->
    {ReversedUnpacked, Rest} = lists:foldl(
        fun(Descriptor, {Values, Bin}) ->
            {Value, Rest} = xls_type:unpack(Bin, Descriptor),
            {[Value | Values], Rest}
        end,
        {[], Binary},
        Descriptors
    ),
    {lists:reverse(ReversedUnpacked), Rest}.
