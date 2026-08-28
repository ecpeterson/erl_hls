-module(xls_debug).

-behavior(gen_server).

-export([start_link/2, stop/1]).
-export([get_counters/1, get_trace/1]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2]).

%% Host-to-FPGA requests occupy the low half of the tag space.
-define(DEBUG_GET_COUNTERS, 16#01).
%% 16#02 is reserved for a future request.
-define(DEBUG_GET_TRACE, 16#03).

%% FPGA-to-host replies occupy the high half of the tag space.
-define(DEBUG_COUNTERS, 16#81).
%% 16#82 is reserved for a future reply.
-define(DEBUG_TRACE, 16#83).
-define(DEBUG_ERROR, 16#ff).
-define(FABRIC_RX, '$xls_fabric_frame').

-define(TRACE_VERSION, 1).
-define(TRACE_RECORD_WORDS, 2).
-define(TRACE_APPLICATION_RX, 1).
-define(TRACE_APPLICATION_TX, 2).

-record(state, {
    module = undefined :: module() | undefined,
    fabric :: {
        Broker :: pid(),
        LocalEndpoint :: 0..65535,
        PeerEndpoint :: 0..65535
    },
    pending = #{} :: #{0..255 => gen_server:from()},
    tx_id = 0 :: 0..255
}).

start_link(Module, {fabric, Broker, PeerEndpoint}) ->
    gen_server:start_link(
        ?MODULE,
        {Module, {fabric, Broker, 0, PeerEndpoint}},
        []
    ).

stop(Pid) ->
    gen_server:stop(Pid).

get_counters(Pid) ->
    gen_server:call(Pid, get_counters).

get_trace(Pid) ->
    gen_server:call(Pid, get_trace).

init({Module, {fabric, Broker, LocalEndpoint, PeerEndpoint}}) ->
    ok = xls_fabric:register_route(
        Broker,
        {PeerEndpoint, LocalEndpoint},
        self()
    ),
    {ok, #state{
        module = Module,
        fabric = {Broker, LocalEndpoint, PeerEndpoint}
    }}.

handle_call(get_counters, From, State) ->
    request(?DEBUG_GET_COUNTERS, From, State);
handle_call(get_trace, From, State) ->
    request(?DEBUG_GET_TRACE, From, State).

request(Tag, From, State = #state{tx_id = TxID, pending = Pending}) ->
    ok = write_frame(State, Tag, TxID, <<>>),
    {noreply, State#state{
        pending = Pending#{TxID => From},
        tx_id = (TxID + 1) rem 256
    }}.

handle_cast(
    {?FABRIC_RX, {Tag, TxID, _Flags}, Payload},
    State = #state{module = Module, pending = Pending}
) ->
    {From, NewPending} = maps:take(TxID, Pending),
    gen_server:reply(From, decode_reply(Tag, Payload, Module)),
    {noreply, State#state{pending = NewPending}}.

terminate(_Reason, _State) ->
    %% Route ownership is monitored by xls_fabric, so cleanup also occurs for
    %% exits which bypass terminate/2 or coincide with broker failure.
    ok.

write_frame(
    #state{fabric = {Broker, LocalEndpoint, PeerEndpoint}},
    Tag,
    TxID,
    Payload
) ->
    xls_fabric:send(
        Broker,
        {LocalEndpoint, PeerEndpoint},
        {Tag, TxID, 0},
        Payload
    ).

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
decode_reply(?DEBUG_TRACE, Payload, _Module) ->
    decode_trace_reply(Payload);
decode_reply(?DEBUG_ERROR, <<ErrorCode:32/little-unsigned-integer>> = Payload, _Module) ->
    {error, #{reason => {debug_error, ErrorCode}, raw => Payload}};
decode_reply(?DEBUG_ERROR, Payload, _Module) ->
    {error, #{reason => malformed_debug_error, raw => Payload}};
decode_reply(Tag, Payload, _Module) ->
    {error, {unexpected_reply, Tag, Payload}}.

decode_trace_reply(<<
    Version:32/little-unsigned-integer,
    RecordWords:32/little-unsigned-integer,
    Count:32/little-unsigned-integer,
    Dropped:32/little-unsigned-integer,
    ObservationDrops:32/little-unsigned-integer,
    Records/binary
>> = Payload) ->
    Trace = #{
        version => Version,
        record_words => RecordWords,
        count => Count,
        dropped => Dropped,
        observation_drops => ObservationDrops,
        raw => Payload
    },
    ExpectedBytes = Count * ?TRACE_RECORD_WORDS * 4,
    case {Version, RecordWords, byte_size(Records)} of
        {?TRACE_VERSION, ?TRACE_RECORD_WORDS, ExpectedBytes} ->
            {ok, Trace#{events => decode_trace_events(Records, [])}};
        {?TRACE_VERSION, ?TRACE_RECORD_WORDS, Bytes} ->
            {error, Trace#{reason => {
                malformed_trace_records,
                ExpectedBytes,
                Bytes
            }}};
        _ ->
            {error, Trace#{reason => {
                unsupported_trace_schema,
                Version,
                RecordWords
            }}}
    end;
decode_trace_reply(Payload) ->
    {error, #{reason => malformed_trace_reply, raw => Payload}}.

decode_trace_events(<<>>, Acc) ->
    lists:reverse(Acc);
decode_trace_events(<<
    Cycle:32/little-unsigned-integer,
    Op:8,
    TxID:8,
    Flags:8,
    KindCode:8,
    Rest/binary
>>, Acc) ->
    Event = #{
        cycle => Cycle,
        kind => trace_kind(KindCode),
        kind_code => KindCode,
        flags => Flags,
        tx_id => TxID,
        op => Op
    },
    decode_trace_events(Rest, [Event | Acc]).

trace_kind(?TRACE_APPLICATION_RX) -> application_rx;
trace_kind(?TRACE_APPLICATION_TX) -> application_tx;
trace_kind(Code) -> {unknown, Code}.
