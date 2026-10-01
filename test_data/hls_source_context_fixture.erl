-module(hls_source_context_fixture).
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([waiting]).
-hls_outputs([out]).
-hls_mailbox_capacity(?CAPACITY).
-hls_tags([message]).
-export([init/1, waiting/3]).

-include("config.hrl").

-record(message, {value = hls_type:zero() :: hls_nums:?WORD_TYPE()}).
-record(cell, {value = hls_type:zero() :: hls_nums:?WORD_TYPE()}).

init([]) -> {ok, waiting, #cell{value = hls_type:as(hls_nums:?WORD_TYPE(), ?INITIAL)}}.

waiting(enter, _Old, Cell) -> {Cell, []};
waiting(cast, #message{value = Value}, Cell) ->
    {waiting, Cell#cell{value = Value}, consume}.
