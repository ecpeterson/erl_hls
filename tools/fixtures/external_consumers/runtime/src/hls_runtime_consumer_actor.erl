-module(hls_runtime_consumer_actor).
-moduledoc "Precompiled callback used by the external runtime-only release witness.".

-behaviour(hls_gs).

-export([init/1, handle_call/2, handle_cast/2]).

-doc "Initializes the finite callback state without compiler metadata.".
-spec init([]) -> non_neg_integer().
init([]) -> 0.

-doc "Returns the retained state through the ordinary CPU adapter.".
-spec handle_call(read, non_neg_integer()) -> {reply, non_neg_integer(), non_neg_integer()}.
handle_call(read, State) -> {reply, State, State}.

-doc "Advances the retained state through the ordinary CPU adapter.".
-spec handle_cast(advance, non_neg_integer()) -> {noreply, non_neg_integer()}.
handle_cast(advance, State) -> {noreply, State + 1}.
