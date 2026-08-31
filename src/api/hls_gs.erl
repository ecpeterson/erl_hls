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
""".

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
    fabric = none :: none | {
        Broker :: pid(),
        LocalEndpoint :: 0..65535,
        PeerEndpoint :: 0..65535
    },
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

-define(FABRIC_RX, '$hls_fabric_frame').
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
            ok = hls_fabric:register_route(
                Broker,
                {PeerEndpoint, LocalEndpoint},
                self()
            ),
            #state{
                module = Module,
                fabric = {Broker, LocalEndpoint, PeerEndpoint}
            }
    end,
    {ok, GS}.

handle_call(
    Message,
    _From,
    GS = #state{module = Module, state = State, fabric = none}
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
    GS = #state{module = Module, state = State, fabric = none}
) ->
    {noreply, NewState} = Module:handle_cast(Message, State),
    {noreply, GS#state{state = NewState}};
handle_cast(
    {?FABRIC_RX, {Tag, TxID, Flags}, Payload},
    GS = #state{module = Module, fabric = {_Broker, _Local, _Peer}}
) ->
    Header = #header{tag = Tag, tx_id = TxID, flags = Flags},
    handle_reply(Header, Payload, Module, GS);
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

terminate(_Reason, _State) ->
    %% hls_fabric monitors each registered owner and removes its return route
    %% on every kind of exit, including exits which do not run terminate/2.
    ok.

code_change(_OldVsn, GS, _Extra) ->
    {ok, GS}.

%%%
%%% Helper
%%%

transmit(
    #state{fabric = {Broker, LocalEndpoint, PeerEndpoint}},
    Header,
    Payload
) ->
    hls_fabric:send(
        Broker,
        {LocalEndpoint, PeerEndpoint},
        {Header#header.tag, Header#header.tx_id, Header#header.flags},
        Payload
    ).

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
