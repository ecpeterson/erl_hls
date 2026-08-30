-module(xls_tags_fixture).

-xls_data(state).
-xls_tags([first]).
-include("xls_tags_shared.hrl").
-xls_tags([last]).
-compile({parse_transform, xls_pack}).

-export([init/1, handle_call/2, handle_cast/2]).

-record(first, {
    value = xls_type:zero() :: xls_nums:u32()
}).

-record(last, {
    value = xls_type:zero() :: xls_nums:u32()
}).

-record(state, {
    value = xls_type:zero() :: xls_nums:u32()
}).

init([]) ->
    #state{}.

handle_call(#last{value = Value}, State) ->
    {reply, #last{value = Value}, State}.

handle_cast(#first{value = Value}, State) ->
    {noreply, State#state{value = Value}};
handle_cast(#shared{value = Value}, State) ->
    {noreply, State#state{value = Value}}.
