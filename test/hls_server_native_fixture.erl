-module(hls_server_native_fixture).
-moduledoc "CPU-only server without codec metadata, used to preserve native facade behavior.".
-behaviour(hls_gs).
-export([init/1, handle_call/2, handle_cast/2]).
-doc "Initializes the native counter.".
-spec init([]) -> non_neg_integer().
init([]) -> 0.
-doc "Replies to an ordinary atom without requiring hardware record metadata.".
-spec handle_call(read, non_neg_integer()) -> {reply, non_neg_integer(), non_neg_integer()}.
handle_call(read, Count) -> {reply, Count, Count}.
-doc "Advances the native counter.".
-spec handle_cast(add, non_neg_integer()) -> {noreply, non_neg_integer()}.
handle_cast(add, Count) -> {noreply, Count + 1}.
