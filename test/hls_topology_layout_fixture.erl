-module(hls_topology_layout_fixture).

-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([waiting]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-hls_tags([message]).

-export([handle_cast/3, handle_enter/3, init/1]).

-record(message, {
    value = hls_type:zero() :: hls_nums:u64()
}).

-record(cell, {
    value = hls_type:zero() :: hls_nums:u64()
}).

init([]) ->
    {ok, waiting, #cell{}}.

handle_enter(_OldPhase, waiting, Cell) ->
    {Cell, [{cast, out, #message{value = Cell#cell.value}}]}.

handle_cast(#message{value = Value}, waiting, Cell) ->
    {waiting, Cell#cell{value = Value}, consume}.
