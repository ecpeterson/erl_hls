-module(erl_hls_compile_actor).
-moduledoc "Minimal external actor compiled through the installed umbrella facade.".

-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).

-export([init/1, handle_call/2, handle_cast/2]).

-hls_data(state).
-hls_tags([advance, read, value]).
-hls_replies([{read, [value]}]).

-record(state, {value = hls_type:zero() :: hls_nums:u8()}).
-record(advance, {value = hls_type:zero() :: hls_nums:u8()}).
-record(read, {marker = hls_type:zero() :: hls_nums:u8()}).
-record(value, {value = hls_type:zero() :: hls_nums:u8()}).

-doc "Initializes the external actor at the provider-defined zero value.".
-spec init([]) -> #state{}.
init([]) -> #state{}.

-doc "Reads the retained finite byte.".
-spec handle_call(#read{}, #state{}) -> {reply, #value{}, #state{}}.
handle_call(#read{}, State = #state{value = Value}) ->
    {reply, #value{value = Value}, State}.

-doc "Replaces the retained finite byte.".
-spec handle_cast(#advance{}, #state{}) -> {noreply, #state{}}.
handle_cast(#advance{value = Value}, State) ->
    {noreply, State#state{value = Value}}.
