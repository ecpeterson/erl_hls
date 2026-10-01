-module(hls_gs).
-moduledoc """
A CPU adapter and callback contract for hardware-backed servers.

Immediate servers use `init/1`, `handle_call/2`, and `handle_cast/2`.
`-hls_pending_calls(N)` opts into retained replies through `handle_call/3`
and bounded iteration through `handle_continue/2`; see
`docs/retained-replies.md` for ordering, capacity and failure semantics. When a module is translated, clauses for
the same input record are tried in source order. The body of the first clause
whose supported head and guard sequence match is selected. An input record tag
handled by the server must belong exclusively to either `handle_call/2` or
`handle_cast/2`, because the generated request header does not otherwise
encode which callback family should receive it.

`-hls_replies([{RequestTag, [ReplyTag, ...]}, ...]).` declares the allowed
public reply records for every call tag. `hls_pack` embeds the checked contract
in the BEAM; the CPU adapter checks callback results against it, and hardware
returns `reply_contract` on violation. Fabric proxies require this metadata
and match replies against each outstanding request's set. See
`docs/service-contracts.md` for declarations, errors, and execution semantics.

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
-export([init/1, handle_call/3, handle_cast/2, handle_continue/2, handle_info/2, terminate/2, code_change/3]).
-export_type([from/0, call_result/1, async_result/1]).
-export([from/0, width/2, zero/2, pack/3, unpack/3, print_type/2]).
-export([generic_unpack/2]).
-export([encode_request/3, decode_reply/3]).
-behavior(gen_server).

%%%
%%% behavior definition
%%%

-type init_arg() :: any().
-type in_record() :: any().
-type out_record() :: any().
-type state() :: any().

-callback init(init_arg()) -> state().
-callback handle_call(in_record(), state()) -> {reply, out_record(), state()}.
-doc "Handles a cast; retained servers may finish one caller and schedule internal work.".
-callback handle_cast(in_record(), state()) -> async_result(state()).
-doc "Receives a reply handle which may be retained until a later callback, subject to the declared capacity.".
-callback handle_call(in_record(), from(), state()) -> call_result(state()).
-doc "Runs a declared continuation before the next external request; may finish one retained caller.".
-callback handle_continue(atom(), state()) -> async_result(state()).
-optional_callbacks([handle_call/2, handle_call/3, handle_continue/2]).

-doc "An activation-local reply handle; retain and return it unchanged, never construct or reuse it.".
-type from() :: hls_nums:u64().

%% A callback step emits at most one reply, optionally followed by one continuation.
-type action() :: {reply, from(), tuple()} | {continue, atom()}.

-doc "A cast/continuation result; Actions contains at most one reply followed by at most one continuation.".
-type async_result(S) :: {noreply, S} | {noreply, S, {continue, atom()} | [action()]}.

-doc "A call result: reply immediately or retain From; an optional continuation precedes later requests.".
-type call_result(S) :: async_result(S) | {reply, tuple(), S} |
    {reply, tuple(), S, {continue, atom()}}.

-record(state, {
    module :: module(),
    contract = none :: none | hls_service_contract:contract(),
    fabric = none :: none | hls_fabric_client:state(),
    state :: state(),
    pending = none :: none | hls_gs_deferred:pending()
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
-define(ERROR_BADARG, 14).
-define(ERROR_REPLY_CONTRACT, 15).

%% Failed casts can emit ERROR replies. Never lend their ID to a call.
-define(CAST_TX_ID, 255).

-doc "Initializes the CPU callback or a checked hardware proxy with optional bounded reply ownership.".
-spec init({module(), term(), list()}) -> {ok, #state{}} | {stop, term()}.
init({Module, Arg, Options}) ->
    case {transport(Options), Arg} of
        {cpu, _} ->
            Contract = case hls_service_contract:from_module(Module) of
                {ok, Value} -> Value;
                none -> none
            end,
            Pending = case Contract of
                #{pending_calls := _} -> hls_gs_deferred:new(Contract);
                _ -> none
            end,
            {ok, #state{state = Module:init(Arg), module = Module, contract = Contract, pending = Pending}};
        {{fabric, Broker, LocalEndpoint, PeerEndpoint}, []} ->
            case hls_service_contract:from_module(Module) of
                none -> {stop, {missing_hls_service_contract, Module}};
                {ok, Contract} ->
                    case hls_fabric_client:new(Broker, LocalEndpoint, PeerEndpoint, ?CAST_TX_ID) of
                        {ok, Client} -> {ok, #state{module = Module, fabric = Client,
                            contract = Contract}};
                        {error, Reason} -> {stop, Reason}
                    end
            end;
        {{fabric, _Broker, _LocalEndpoint, _PeerEndpoint}, _} ->
            {stop, {unsupported_hls_init_argument, Arg}}
    end.

-doc "Serves proxy inspection and dispatches validated application calls.".
-spec handle_call(term(), gen_server:from(), #state{}) -> term().
%% CPU servers have no physical fabric session to inspect.
handle_call('$hls_fabric_info', _From, GS = #state{fabric = none}) ->
    {reply, none, GS};
%% Inspect proxy admission independently of application reply completion.
handle_call('$hls_fabric_info', _From, GS = #state{fabric = Client}) ->
    {reply, hls_fabric_client:info(Client), GS};
%% Validate the request family before allocating a retained reply or transmitting.
handle_call(Message, From, GS = #state{contract = Contract}) ->
    case call_replies(Message, Contract) of
        invalid -> {reply, {error, {invalid_request, call, element(1, Message)}}, GS};
        Replies -> call(Message, From, Replies, GS)
    end.

%% Select bounded CPU execution, immediate CPU execution or the existing physical proxy.
-spec call(term(), gen_server:from(), none | [atom()], #state{}) -> term().
call(Message, From, Replies, GS = #state{pending = Pending}) when Pending =/= none ->
    deferred(call, Message, {From, Replies}, GS);
call(Message, _From, Replies, GS = #state{module = Module, state = State, fabric = none}) ->
    {reply, Reply, NewState} = Module:handle_call(Message, State),
    ok = check_reply(Message, Reply, Replies),
    {reply, Reply, GS#state{state = NewState}};
call(Message, From, Replies, GS = #state{module = Module, fabric = Client}) ->
    {Tag, Payload, Context} = encode(Module, Message, Replies),
    Next = hls_fabric_client:request(Tag, Payload, Context, From, Client),
    {noreply, GS#state{fabric = Next}}.

-doc "Dispatches CPU casts, completed fabric frames and outgoing proxy casts.".
-spec handle_cast(term(), #state{}) -> term().
%% Bounded CPU casts can finish retained calls without acquiring another reply slot.
handle_cast(Message, GS = #state{pending = Pending, contract = Contract}) when Pending =/= none ->
    ok = check_cast(Message, Contract),
    deferred(cast, Message, none, GS);
%% Immediate CPU servers preserve their existing callback contract.
handle_cast(
    Message,
    GS = #state{module = Module, state = State, fabric = none, contract = Contract}
) ->
    ok = check_cast(Message, Contract),
    {noreply, NewState} = Module:handle_cast(Message, State),
    {noreply, GS#state{state = NewState}};
%% A credited physical reply completes its existing host transaction.
handle_cast(
    {?FABRIC_RX, Receipt, Route, Header, Payload},
    GS = #state{fabric = Client}
) ->
    Next = hls_fabric_client:receive_frame(Receipt, Route, Header, Payload, fun decode_reply/3, Client),
    {noreply, GS#state{fabric = Next}};
%% Outgoing casts retain the dedicated non-call transaction ID.
handle_cast(Message, GS = #state{module = Module, fabric = Client, contract = Contract}) ->
    ok = check_cast(Message, Contract),
    {Tag, Payload, _Context} = encode(Module, Message, none),
    Next = hls_fabric_client:cast(Tag, ?CAST_TX_ID, Payload, Client),
    {noreply, GS#state{fabric = Next}}.

-doc "Runs bounded internal work before selecting another mailbox request.".
-spec handle_continue(atom(), #state{}) -> {noreply, #state{}} | {noreply, #state{}, {continue, atom()}}.
handle_continue(Name, GS) -> deferred(continue, Name, none, GS).

%% gen_server continuations preserve callback ordering without recursive drains.
-spec deferred(call | cast | continue, term(), term(), #state{}) ->
    {noreply, #state{}} | {noreply, #state{}, {continue, atom()}}.
deferred(Kind, Message, From, GS = #state{module = Module, state = State, pending = Pending}) ->
    {Next, Replies, Continue} = hls_gs_deferred:dispatch(Kind, Module, Message, From, State, Pending),
    Updated = GS#state{state = Next, pending = Replies},
    case Continue of
        none -> {noreply, Updated};
        {continue, Name} -> {noreply, Updated, {continue, Name}}
    end.

handle_info(Message, GS = #state{fabric = Client})
        when Client =/= none ->
    {noreply, GS#state{fabric = hls_fabric_client:handle_info(Message, Client)}};
handle_info(_Message, GS) -> {noreply, GS}.

decode_reply(TagID, Payload, {Module, Replies}) ->
    %% Keep the allowed set with the slot, including abandoned calls. A known
    %% but unrelated record is no more evidence of completion than an unknown tag.
    try
        Tag = Module:unpack_tag(TagID),
        true = Tag =:= error orelse lists:member(Tag, Replies),
        {Reply, <<>>} = unpack_reply(Module, Tag, Payload),
        {reply, Reply}
    catch
        error:_ -> ignore
    end.

-doc "Encodes a hardware request without starting a proxy. The returned context is passed to decode_reply/3.".
encode_request(Module, Kind, Message) ->
    {ok, Contract} = hls_service_contract:from_module(Module),
    Replies = case Kind of
        call ->
            case call_replies(Message, Contract) of
                invalid -> error({invalid_request, call, element(1, Message)});
                Allowed -> Allowed
            end;
        cast -> ok = check_cast(Message, Contract), none
    end,
    encode(Module, Message, Replies).

encode(Module, Message, Replies) ->
    {Module:pack_tag(element(1, Message)),
        hls_codec:align(Module:pack(Message), 32), {Module, Replies}}.

call_replies(_Message, none) -> none;
call_replies(Message, #{calls := Calls}) ->
    maps:get(element(1, Message), Calls, invalid).

check_reply(_Request, _Reply, none) -> ok;
check_reply(Request, Reply, Replies) ->
    case is_tuple(Reply) andalso tuple_size(Reply) > 0
            andalso lists:member(element(1, Reply), Replies) of
        true -> ok;
        false -> error({reply_contract, element(1, Request), Reply, Replies})
    end.

check_cast(_Message, none) -> ok;
check_cast(Message, #{casts := Casts}) ->
    case lists:member(element(1, Message), Casts) of
        true -> ok;
        false -> error({invalid_request, cast, element(1, Message)})
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
        {fabric, Broker, LocalEndpoint, PeerEndpoint} ->
            {fabric, Broker, LocalEndpoint, PeerEndpoint};
        {fabric, Broker, PeerEndpoint} ->
            {fabric, Broker, 0, PeerEndpoint};
        false ->
            case Options of
                [] -> cpu;
                _ -> error({invalid_hls_gs_options, Options})
            end
    end.

unpack_reply(_Module, error, <<ErrorCode:32/little-unsigned-integer>>) ->
    {{error, {remote_error, error_reason(ErrorCode)}}, <<>>};
unpack_reply(_Module, error, _Payload) ->
    error(invalid_error_payload);
unpack_reply(Module, Tag, Payload) ->
    Width = Module:pack_width(Tag),
    true = bit_size(Payload) =:= ((Width + 31) div 32) * 32,
    {Record, _Padding} = hls_codec:split(Payload, Width),
    Module:unpack(Tag, Record).

%% Decode generic callback faults and bounded-server admission failures.
-spec error_reason(non_neg_integer()) -> term().
error_reason(16) -> busy;
error_reason(17) -> reply_handle_exhausted;
error_reason(18) -> duplicate_transaction;
error_reason(?ERROR_FUNCTION_CLAUSE) -> function_clause;
error_reason(?ERROR_MATCH_FAILURE) -> match_failure;
error_reason(?ERROR_REQUEST_LENGTH) -> request_length;
error_reason(?ERROR_CASE_CLAUSE) -> case_clause;
error_reason(?ERROR_IF_CLAUSE) -> if_clause;
error_reason(?ERROR_BADARITH) -> badarith;
error_reason(?ERROR_BADARG) -> badarg;
error_reason(?ERROR_REPLY_CONTRACT) -> reply_contract;
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

-doc "Returns the fixed storage width of a retained reply handle.".
-spec width(from, []) -> 64.
width(from, []) -> 64.
-doc "Returns the invalid handle used for empty application storage.".
-spec zero(from, []) -> 0.
zero(from, []) -> 0.
-doc "Serializes a retained handle for typed application state.".
-spec pack(from(), from, []) -> bitstring().
pack(Value, from, []) -> hls_nums:pack(Value, u64, []).
-doc "Decodes a retained handle from typed application state.".
-spec unpack(bitstring(), from, []) -> {from(), bitstring()}.
unpack(Bits, from, []) -> hls_nums:unpack(Bits, u64, []).
-doc "Renders the fixed hardware representation of a retained handle.".
-spec print_type(from, []) -> string().
print_type(from, []) -> "u64".

-doc "Constructs the type descriptor for an activation-local retained reply handle.".
-spec from() -> hls_type:descriptor().
from() -> {hls_type, ?MODULE, from, []}.
