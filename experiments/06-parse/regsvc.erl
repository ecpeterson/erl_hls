%%%% regsvc.erl
%%%%
%%%% TODO:
%%%%    + generate spontaneous messages, probably modeled as a timeout

-module(regsvc).
-export([ping/2, get/2, set/4, bulk_get/3]).  % client interface
-export([start_link/0, stop/1]).  % server interface
-export([init/1, handle_call/2, handle_cast/2]).  % xls_gs callbacks

-behavior(xls_gs).
-xls_tags([set, get, ping, bulk_get, ack, read]).  % xls struct payloads
-compile({parse_transform, xls_parse}).  % auto-defines un/pack

%%%
%%% Types
%%%

-record(set, {
    register = 0 :: xls_types:u32(),
    value = 0 :: xls_types:u32(),
    mask = 0 :: xls_types:u32()
}).

-record(get, {
    register = 0 :: xls_types:u32()
}).

-record(ping, {
    value = 0 :: xls_types:u32()
}).

-record(bulk_get, {
    start = 0 :: xls_types:u32(),
    count = 0 :: xls_types:u32()
}).

-record(ack, {
    value = 0 :: xls_types:u32()
}).

-record(read, {
    value = 0 :: xls_types:u32()
}).

-record(state, {
    registers :: xls_lists:list(u32, 16)  % TODO: put a real type here. can also transpile a constructor?
}).

%%%
%%% Client interface
%%%

ping(PID, Value) ->
    #ack{value = Reply} = gen_server:call(PID, #ping{value = Value}),
    Reply.

get(PID, Register) ->
    #read{value = Value} = gen_server:call(PID, {get, Register}),
    Value.

set(PID, Register, Value, Mask) ->
    gen_server:cast(PID, {set, Register, Value, Mask}).

bulk_get(PID, Start, Count) ->
    gen_server:call(PID, {bulk_get, Start, Count}).

%%%
%%% Server management
%%%

start_link() ->
    xls_gs:start_link(?MODULE, []).

stop(PID) ->
    xls_gs:stop(PID).

%%%
%%% gen_server behavior
%%%

-spec init(any()) -> #state{}.  % obligatory type signature
init([]) ->
    #state{
        registers = xls_lists:new([u32, 16])
    }.

handle_cast(#set{register = Register, value = Value, mask = Mask}, State) ->
    OldValue = xls_lists:nth(Register + 1, State#state.registers),
    NewValue = (OldValue band bnot Mask) bor (Value band Mask),
    NewRegisters = xls_lists:set(Register + 1, State#state.registers, NewValue),
    {noreply, State#state{registers = NewRegisters}}.

handle_call(#ping{value = Value}, State) ->
    {reply, #ack{value = Value}, State};
handle_call(#get{register = Register}, State) ->
    Value = xls_lists:nth(Register + 1, State#state.registers),
    {reply, #read{value = Value}, State}.
% handle_call(#bulk_get{start = Start, count = Count}, State) ->
%     Whole = tuple_to_list(State),
%     {_Left, Right} = lists:split(Start, Whole),
%     {Result, _Right} = lists:split(Count, Right),
%     {reply, list_to_tuple(Result), State}.
