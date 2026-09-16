-module(hls_reply_fixture).
-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).
-export([init/1, handle_call/2, handle_cast/2]).

-hls_data(ledger).
-hls_tags([query, read, change, small, large, wrong]).
-hls_replies([{query, [small, large]}, {read, [small]}]).

-record(ledger, {value = hls_type:zero() :: hls_nums:u32()}).
-record(query, {mode = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u32()}).
-record(read, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(change, {value = hls_type:zero() :: hls_nums:u32()}).
-record(small, {value = hls_type:zero() :: hls_nums:u32()}).
-record(large, {value = hls_type:zero() :: hls_nums:u32(), previous = hls_type:zero() :: hls_nums:u32()}).
-record(wrong, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> #ledger{value = 7}.

handle_call(#query{mode = 0, value = Value}, State) ->
    {reply, small_reply(Value), State#ledger{value = Value}};
handle_call(#query{mode = 1, value = Value}, State) ->
    Reply = case Value of
        0 -> #large{previous = State#ledger.value};
        _ -> #large{value = Value, previous = State#ledger.value}
    end,
    {reply, Reply, State#ledger{value = Value}};
handle_call(#query{mode = 2, value = Value}, State) ->
    %% Deliberate implementation defect: a public record outside this call's set.
    {reply, #wrong{value = Value}, State#ledger{value = Value}};
handle_call(#query{mode = 3, value = Value}, State) ->
    true = Value =:= 0,
    {reply, #wrong{}, State};
handle_call(#read{}, State) ->
    {reply, #small{value = State#ledger.value}, State}.

handle_cast(#change{value = Value}, State) ->
    {noreply, State#ledger{value = Value}}.

-spec small_reply(hls_nums:u32()) -> #small{}.
small_reply(Value) -> #small{value = Value}.
