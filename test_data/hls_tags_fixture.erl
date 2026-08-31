-module(hls_tags_fixture).

-hls_data(state).
-hls_tags([first]).
-include("hls_tags_shared.hrl").
-hls_tags([last]).
-compile({parse_transform, hls_pack}).

-export([init/1, handle_call/2, handle_cast/2]).

-record(first, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(last, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(state, {
    value = hls_type:zero() :: hls_nums:u32()
}).

init([]) ->
    #state{}.

handle_call(#last{value = Value}, State) ->
    {reply, #last{value = Value}, State}.

handle_cast(#first{value = Value}, State) ->
    {noreply, State#state{value = Value}};
handle_cast(#shared{value = Value}, State) ->
    {noreply, State#state{value = Value}}.
