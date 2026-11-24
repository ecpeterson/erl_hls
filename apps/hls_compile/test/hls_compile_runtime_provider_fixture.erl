-module(hls_compile_runtime_provider_fixture).
-moduledoc """
A computation-only actor whose state exercises the runtime-owned retained-handle
provider without starting a service.
""".

-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).

-export([init/1, handle_call/2, handle_cast/2]).

-hls_data(state).
-hls_tags([advance, read, value]).
-hls_replies([{read, [value]}]).

%% The invalid zero handle is ordinary empty storage; this witness never retains a caller.
-record(state, {
    handle = hls_type:zero() :: hls_gs:from(),
    value = hls_type:zero() :: hls_nums:u8()
}).
-record(advance, {value = hls_type:zero() :: hls_nums:u8()}).
-record(read, {marker = hls_type:zero() :: hls_nums:u8()}).
-record(value, {value = hls_type:zero() :: hls_nums:u8()}).

-doc "Starts with provider-defined empty handle and byte values.".
-spec init([]) -> #state{}.
init([]) -> #state{}.

-doc "Returns the current finite byte without changing state.".
-spec handle_call(#read{}, #state{}) -> {reply, #value{}, #state{}}.
handle_call(#read{}, State = #state{value = Value}) ->
    {reply, #value{value = Value}, State}.

-doc "Replaces the finite byte without interpreting the empty retained-handle field.".
-spec handle_cast(#advance{}, #state{}) -> {noreply, #state{}}.
handle_cast(#advance{value = Value}, State) ->
    {noreply, State#state{value = Value}}.
