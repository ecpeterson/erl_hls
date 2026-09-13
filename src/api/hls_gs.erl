-module(hls_gs).
-moduledoc """
A CPU adapter and callback contract for simple hardware-backed servers.

Callback modules use `init/1`, `handle_call/2`, and `handle_cast/2` with the
fixed result shapes declared below. When a module is translated, clauses for
the same input record are tried in source order. The body of the first clause
whose supported head and guard sequence match is selected. An input record tag
handled by the server must belong exclusively to either `handle_call/2` or
`handle_cast/2`, because the generated request header does not otherwise
encode which callback family should receive it.

Hardware translation requires one unguarded `init([])` clause returning the
state record. Its supported pure expressions are evaluated and checked by XLS
at compile time; a match failure rejects conversion. Cold start and hardware
reset use that value. A fabric proxy accepts only `[]` as its initializer
argument and does not reset the device when it starts. CPU adapters still pass
their argument to the callback. See `docs/initialization.md` for the shared
initialization and reset contract.

Fabric calls have 255 transaction slots; casts use a reserved ID. Timeouts do
not cancel device work. See `docs/host-transactions.md` for ownership, failure,
inspection, and session recovery.
""".

-export([start_link/2, start_link/3, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
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
    fabric = none :: none | hls_fabric_client:state(),
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

-define(FABRIC_RX, '$hls_fabric_frame').
-define(ERROR_FUNCTION_CLAUSE, 1).
-define(ERROR_MATCH_FAILURE, 2).
-define(ERROR_REQUEST_LENGTH, 3).
-define(ERROR_CASE_CLAUSE, 4).
-define(ERROR_IF_CLAUSE, 5).
-define(ERROR_BADARITH, 13).

%% Failed casts can emit ERROR replies. Never lend their ID to a call.
-define(CAST_TX_ID, 255).

init({Module, Arg, Options}) ->
    case {transport(Options), Arg} of
        {cpu, _} ->
            {ok, #state{state = Module:init(Arg), module = Module}};
        {{fabric, Broker, LocalEndpoint, PeerEndpoint}, []} ->
            case hls_fabric_client:new(Broker, LocalEndpoint, PeerEndpoint, ?CAST_TX_ID) of
                {ok, Client} -> {ok, #state{module = Module, fabric = Client}};
                {error, Reason} -> {stop, Reason}
            end;
        {{fabric, _Broker, _LocalEndpoint, _PeerEndpoint}, _} ->
            {stop, {unsupported_hls_init_argument, Arg}}
    end.

handle_call('$hls_fabric_info', _From, GS = #state{fabric = none}) ->
    {reply, none, GS};
handle_call('$hls_fabric_info', _From, GS = #state{fabric = Client}) ->
    {reply, hls_fabric_client:info(Client), GS};
handle_call(
    Message,
    _From,
    GS = #state{module = Module, state = State, fabric = none}
) ->
    {reply, Reply, NewState} = Module:handle_call(Message, State),
    {reply, Reply, GS#state{state = NewState}};
handle_call(Message, From, GS = #state{module = Module, fabric = Client}) ->
    Tag = Module:pack_tag(element(1, Message)),
    Payload = Module:pack(Message),
    Next = hls_fabric_client:request(Tag, Payload, Module, From, Client),
    {noreply, GS#state{fabric = Next}}.

handle_cast(
    Message,
    GS = #state{module = Module, state = State, fabric = none}
) ->
    {noreply, NewState} = Module:handle_cast(Message, State),
    {noreply, GS#state{state = NewState}};
handle_cast(
    {?FABRIC_RX, Route, Header, Payload},
    GS = #state{fabric = Client}
) ->
    Next = hls_fabric_client:receive_frame(Route, Header, Payload, fun decode_reply/3, Client),
    {noreply, GS#state{fabric = Next}};
handle_cast(Message, GS = #state{module = Module, fabric = Client}) ->
    Tag = Module:pack_tag(element(1, Message)),
    Payload = Module:pack(Message),
    Next = hls_fabric_client:cast(Tag, ?CAST_TX_ID, Payload, Client),
    {noreply, GS#state{fabric = Next}}.

handle_info({'DOWN', _, process, _, _} = Down, GS = #state{fabric = Client})
        when Client =/= none ->
    {noreply, GS#state{fabric = hls_fabric_client:down(Down, Client)}};
handle_info(_Message, GS) -> {noreply, GS}.

decode_reply(TagID, Payload, Module) ->
    %% hls_gs permits any declared record; there is no per-request reply
    %% schema. Unknown tags and invalid payloads cannot retire a transaction.
    try
        Tag = Module:unpack_tag(TagID),
        {Reply, <<>>} = unpack_reply(Module, Tag, Payload),
        {reply, Reply}
    catch
        error:_ -> ignore
    end.

terminate(_Reason, _State) ->
    %% hls_fabric retires the return route even for exits bypassing terminate/2.
    ok.

code_change(_OldVsn, GS, _Extra) ->
    {ok, GS}.

%%%
%%% Helper
%%%

transport(Options) ->
    case lists:keyfind(fabric, 1, Options) of
        {fabric, Broker, PeerEndpoint} ->
            {fabric, Broker, 0, PeerEndpoint};
        false ->
            case Options of
                [] -> cpu;
                _ -> error({invalid_hls_gs_options, Options})
            end
    end.

unpack_reply(_Module, error, <<ErrorCode:32/little-unsigned-integer, Rest/binary>>) ->
    {{error, {remote_error, error_reason(ErrorCode)}}, Rest};
unpack_reply(_Module, error, Payload) ->
    {{error, {remote_error, {malformed_error, Payload}}}, <<>>};
unpack_reply(Module, Tag, Payload) ->
    Module:unpack(Tag, Payload).

error_reason(?ERROR_FUNCTION_CLAUSE) -> function_clause;
error_reason(?ERROR_MATCH_FAILURE) -> match_failure;
error_reason(?ERROR_REQUEST_LENGTH) -> request_length;
error_reason(?ERROR_CASE_CLAUSE) -> case_clause;
error_reason(?ERROR_IF_CLAUSE) -> if_clause;
error_reason(?ERROR_BADARITH) -> badarith;
error_reason(ErrorCode) -> {unknown_error, ErrorCode}.

%%%
%%% Utilities for un/pack
%%%

generic_unpack(Descriptors, Binary) ->
    {ReversedUnpacked, Rest} = lists:foldl(
        fun(Descriptor, {Values, Bin}) ->
            {Value, Rest} = hls_type:unpack(Bin, Descriptor),
            {[Value | Values], Rest}
        end,
        {[], Binary},
        Descriptors
    ),
    {lists:reverse(ReversedUnpacked), Rest}.
