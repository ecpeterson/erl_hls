-module(hls_debug).
-moduledoc """
Scoped inspection and the routed hardware debug client.

`info/2,3` reads process-style items from explicit actor, resource, or boundary
handles (see `docs/debug-targets.md`). `inspect_waits/2` explores current waits;
`get_trace/1,2` drains recorded events at an explicitly selected boundary.

The low-level PID forms of `get_counters`, `get_trace`, and `query` address a
client started by this module, not an application PID. In `info`, a bare PID
always means native BEAM process information, including a proxy's own queue.

A client owns 256 transaction slots. Timeouts do not cancel device work; see
`docs/host-transactions.md` for admission, failure, and session recovery.
""".

-behavior(gen_server).

-export([start_link/2, stop/1, query/4]).
-export([info/2, info/3, inspect_waits/2]).
-export([get_counters/1, get_counters/2, get_trace/1, get_trace/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% Host-to-FPGA requests occupy the low half of the tag space.
-define(DEBUG_GET_COUNTERS, 16#01).
%% 16#02 is reserved for a future request.
-define(DEBUG_GET_TRACE, 16#03).

%% FPGA-to-host replies occupy the high half of the tag space.
-define(DEBUG_COUNTERS, 16#81).
%% 16#82 is reserved for a future reply.
-define(DEBUG_TRACE, 16#83).
-define(DEBUG_ERROR, 16#ff).
-define(FABRIC_RX, '$hls_fabric_frame').

-define(TRACE_VERSION, 2).
-define(TRACE_RECORD_WORDS, 3).
-define(TRACE_APPLICATION_RX, 1).
-define(TRACE_APPLICATION_TX, 2).

-record(state, {
    module = undefined :: module() | undefined,
    fabric :: hls_fabric_client:state()
}).

start_link(Module, {fabric, Broker, PeerEndpoint}) ->
    gen_server:start_link(
        ?MODULE,
        {Module, {fabric, Broker, 0, PeerEndpoint}},
        []
    ).

stop(Pid) ->
    gen_server:stop(Pid).

-doc "Inspects a scoped target using process_info-style items and result tuples.".
-spec info(hls_debug_target:target(), atom() | [atom()]) -> term().
info(Target, Items) -> info(Target, Items, 5000).

-spec info(hls_debug_target:target(), atom() | [atom()], timeout()) -> term().
info(Target, Items, Timeout) -> hls_debug_target:info(Target, Items, Timeout).

-doc "Explores and rechecks a topology resource's candidate wait dependencies.".
inspect_waits(Target, Options) -> hls_debug_target:inspect_waits(Target, Options).

get_counters(Target) -> get_counters(Target, 5000).
get_counters(Pid, Timeout) when is_pid(Pid) ->
    gen_server:call(Pid, get_counters, Timeout);
get_counters(Target, Timeout) ->
    hls_debug_target:collect(Target, get_counters, Timeout).

get_trace(Target) -> get_trace(Target, 5000).
get_trace(Pid, Timeout) when is_pid(Pid) ->
    gen_server:call(Pid, get_trace, Timeout);
get_trace(Target, Timeout) ->
    hls_debug_target:collect(Target, get_trace, Timeout).

-doc "Sends a word-aligned management request and returns its raw reply payload.".
-spec query(pid(), 1..127, binary(), timeout()) ->
    {ok, binary()} | {error, term()}.
query(Pid, Tag, Payload, Timeout)
        when Tag > 0, Tag < 128, byte_size(Payload) rem 4 =:= 0,
             byte_size(Payload) =< 1020 ->
    gen_server:call(Pid, {query, Tag, Payload}, Timeout).

init({Module, {fabric, Broker, LocalEndpoint, PeerEndpoint}}) ->
    case hls_fabric_client:new(Broker, LocalEndpoint, PeerEndpoint, 256) of
        {ok, Client} -> {ok, #state{module = Module, fabric = Client}};
        {error, Reason} -> {stop, Reason}
    end.

handle_call('$hls_fabric_info', _From, State = #state{fabric = Client}) ->
    {reply, hls_fabric_client:info(Client), State};

handle_call(get_counters, From, State) ->
    request(?DEBUG_GET_COUNTERS, <<>>, decoded, From, State);
handle_call(get_trace, From, State) ->
    request(?DEBUG_GET_TRACE, <<>>, decoded, From, State);
handle_call({query, Tag, Payload}, From, State) ->
    request(Tag, Payload, raw, From, State).

request(Tag, Payload, Decode, From, State = #state{fabric = Client, module = Module}) ->
    Context = {Tag bor 16#80, Decode, Module},
    Next = hls_fabric_client:request(Tag, Payload, Context, From, Client),
    {noreply, State#state{fabric = Next}}.

handle_cast({?FABRIC_RX, Route, Header, Payload}, State = #state{fabric = Client}) ->
    Next = hls_fabric_client:receive_frame(Route, Header, Payload, fun response/3, Client),
    {noreply, State#state{fabric = Next}}.

response(?DEBUG_ERROR, Payload, {_Expected, _Decode, Module}) ->
    {reply, decode_reply(?DEBUG_ERROR, Payload, Module)};
response(Expected, Payload, {Expected, raw, _Module}) -> {reply, {ok, Payload}};
response(Expected, Payload, {Expected, decoded, Module}) ->
    {reply, decode_reply(Expected, Payload, Module)};
response(_Tag, _Payload, _Context) -> ignore.

handle_info({'DOWN', _, process, _, _} = Down, State = #state{fabric = Client}) ->
    {noreply, State#state{fabric = hls_fabric_client:down(Down, Client)}};
handle_info(_Message, State) -> {noreply, State}.

terminate(_Reason, _State) ->
    %% hls_fabric retires the return route even for exits bypassing terminate/2.
    ok.

decode_reply(?DEBUG_COUNTERS, <<
    5:32/little-unsigned-integer,
    Cycles:32/little-unsigned-integer,
    AppRxBeats:32/little-unsigned-integer,
    AppRxFrames:32/little-unsigned-integer,
    AppRxStalls:32/little-unsigned-integer,
    AppTxBeats:32/little-unsigned-integer,
    AppTxFrames:32/little-unsigned-integer,
    AppTxStalls:32/little-unsigned-integer,
    ObservationDrops:32/little-unsigned-integer,
    Framing:32/little-unsigned-integer
>>, _Module) when Framing < 64 ->
    {ok, #{
        version => 5,
        observation_drops => ObservationDrops,
        framing => decode_framing(Framing),
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
    Framing:32/little-unsigned-integer,
    Records/binary
>> = Payload) when Framing < 64 ->
    Trace = #{
        version => Version,
        record_words => RecordWords,
        count => Count,
        dropped => Dropped,
        observation_drops => ObservationDrops,
        framing => decode_framing(Framing),
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
    Destination:16/little, Source:16/little,
    Op:8,
    TxID:8,
    Flags:8,
    KindCode:8,
    Rest/binary
>>, Acc) ->
    Event = #{
        cycle => Cycle,
        route => case Flags band 2 of 0 -> none; 2 -> {Source, Destination} end,
        observation_gap => Flags band 4 =/= 0,
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

%% These states describe header recognition, not application execution.
decode_framing(Word) ->
    #{rx => frame_phase(Word band 3), tx => frame_phase((Word bsr 2) band 3),
        rx_gap_pending => Word band 16 =/= 0, tx_gap_pending => Word band 32 =/= 0}.

frame_phase(0) -> boundary;
frame_phase(1) -> header;
frame_phase(2) -> payload;
frame_phase(3) -> unsynchronized.
