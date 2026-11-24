-module(hls_compile_boundary_fixture).
-moduledoc "A minimal source actor for the computation-only Stage 3 projection.".

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

-doc "Starts at the provider-defined zero value.".
-spec init([]) -> #state{}.
init([]) -> #state{}.

-doc "Returns the current finite byte without changing state.".
-spec handle_call(#read{}, #state{}) -> {reply, #value{}, #state{}}.
handle_call(#read{}, State = #state{value = Value}) ->
    {reply, #value{value = Value}, State}.

-doc "Replaces the finite byte with the supplied checked record field.".
-spec handle_cast(#advance{}, #state{}) -> {noreply, #state{}}.
handle_cast(#advance{value = Value}, State) ->
    {noreply, State#state{value = Value}}.
