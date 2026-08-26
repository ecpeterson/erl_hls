-module(xls_debug).

-behavior(gen_server).

-export([start_link/2, start_link/3, stop/1, get_counters/1, get_state/1]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2]).

%% Host-to-FPGA requests occupy the low half of the tag space.
-define(DEBUG_GET_COUNTERS, 16#01).
-define(DEBUG_GET_STATE, 16#02).

%% FPGA-to-host replies occupy the high half of the tag space.
-define(DEBUG_COUNTERS, 16#81).
-define(DEBUG_STATE, 16#82).
-define(DEBUG_ERROR, 16#ff).
-define(RX_FRAME, '$debug_frame').

%% TODO: Factor descriptor ownership, frame I/O, and exact reads shared with
%% xls_gs into a transport process. Keep the application and debug protocol
%% clients separate so they can retain independent queues and failure modes.

-record(state, {
    module = undefined :: module() | undefined,
    fd :: file:io_device(),
    listener :: pid(),
    pending = #{} :: #{0..255 => gen_server:from()},
    tx_id = 0 :: 0..255
}).

start_link(WritePath, ReadPath) ->
    start_link(undefined, WritePath, ReadPath).

start_link(Module, WritePath, ReadPath) ->
    gen_server:start_link(?MODULE, {Module, WritePath, ReadPath}, []).

stop(Pid) ->
    gen_server:stop(Pid).

get_counters(Pid) ->
    gen_server:call(Pid, get_counters).

get_state(Pid) ->
    gen_server:call(Pid, get_state).

init({Module, WritePath, ReadPath}) ->
    {ok, FDWrite} = file:open(WritePath, [write, raw, binary]),
    Self = self(),
    Listener = spawn_link(fun() ->
        {ok, FDRead} = file:open(ReadPath, [read, raw, binary]),
        listener(FDRead, Self)
    end),
    {ok, #state{module = Module, fd = FDWrite, listener = Listener}}.

handle_call(get_counters, From, State = #state{fd = FD, tx_id = TxID, pending = Pending}) ->
    ok = write_frame(FD, ?DEBUG_GET_COUNTERS, TxID, <<>>),
    {noreply, State#state{
        pending = Pending#{TxID => From},
        tx_id = (TxID + 1) rem 256
    }};
handle_call(get_state, From, State = #state{fd = FD, tx_id = TxID, pending = Pending}) ->
    ok = write_frame(FD, ?DEBUG_GET_STATE, TxID, <<>>),
    {noreply, State#state{
        pending = Pending#{TxID => From},
        tx_id = (TxID + 1) rem 256
    }}.

handle_cast(
    {?RX_FRAME, Tag, TxID, Payload},
    State = #state{module = Module, pending = Pending}
) ->
    {From, NewPending} = maps:take(TxID, Pending),
    gen_server:reply(From, decode_reply(Tag, Payload, Module)),
    {noreply, State#state{pending = NewPending}}.

terminate(_Reason, #state{fd = FD, listener = Listener}) ->
    try
        unlink(Listener),
        exit(Listener, shutdown)
    after
        file:close(FD)
    end,
    ok.

write_frame(FD, Tag, TxID, Payload) ->
    Header = <<
        (byte_size(Payload) div 4):8,
        TxID:8,
        0:8,
        Tag:8
    >>,
    file:write(FD, <<Header/binary, Payload/binary>>).

decode_reply(?DEBUG_COUNTERS, <<
    Version:32/little-unsigned-integer,
    Cycles:32/little-unsigned-integer,
    AppRxBeats:32/little-unsigned-integer,
    AppRxFrames:32/little-unsigned-integer,
    AppRxStalls:32/little-unsigned-integer,
    AppTxBeats:32/little-unsigned-integer,
    AppTxFrames:32/little-unsigned-integer,
    AppTxStalls:32/little-unsigned-integer
>>, _Module) ->
    {ok, #{
        version => Version,
        cycles => Cycles,
        app_rx_beats => AppRxBeats,
        app_rx_frames => AppRxFrames,
        app_rx_stall_cycles => AppRxStalls,
        app_tx_beats => AppTxBeats,
        app_tx_frames => AppTxFrames,
        app_tx_stall_cycles => AppTxStalls
    }};
decode_reply(?DEBUG_STATE, Payload, Module) ->
    decode_state_reply(Payload, Module);
decode_reply(?DEBUG_ERROR, <<ErrorCode:32/little-unsigned-integer>> = Payload, _Module) ->
    {error, #{reason => {debug_error, ErrorCode}, raw => Payload}};
decode_reply(?DEBUG_ERROR, Payload, _Module) ->
    {error, #{reason => malformed_debug_error, raw => Payload}};
decode_reply(Tag, Payload, _Module) ->
    {error, {unexpected_reply, Tag, Payload}}.

decode_state_reply(<<Version:32/little-unsigned-integer, StateBits/binary>>, Module) ->
    Snapshot = #{version => Version, raw => StateBits},
    case {Version, Module} of
        {1, undefined} ->
            {ok, Snapshot#{state => undefined}};
        {1, _} ->
            decode_state_bits(Module, StateBits, Snapshot);
        {_, _} ->
            {error, Snapshot#{reason => {unsupported_state_version, Version}}}
    end;
decode_state_reply(Payload, _Module) ->
    {error, #{reason => malformed_state_reply, raw => Payload}}.

decode_state_bits(Module, StateBits, Snapshot) ->
    try Module:unpack(state, StateBits) of
        {DecodedState, <<>>} ->
            {ok, Snapshot#{state => DecodedState}};
        {DecodedState, Rest} ->
            {error, Snapshot#{
                reason => {trailing_state_data, Rest},
                state => DecodedState
            }}
    catch
        Class:Reason:Stacktrace ->
            {error, Snapshot#{
                reason => {state_decode_failed, Class, Reason},
                stacktrace => Stacktrace
            }}
    end.

listener(FD, Parent) ->
    {ok, <<PayloadLength:8, TxID:8, _Flags:8, Tag:8>>} = read_exact(FD, 4),
    {ok, Payload} = read_exact(FD, 4 * PayloadLength),
    gen_server:cast(Parent, {?RX_FRAME, Tag, TxID, Payload}),
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
