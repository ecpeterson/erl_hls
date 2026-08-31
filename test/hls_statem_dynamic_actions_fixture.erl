-module(hls_statem_dynamic_actions_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([waiting]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-hls_tags([message]).

-export([handle_cast/3, handle_enter/3, init/1]).

-record(message, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(cell, {
    value = hls_type:zero() :: hls_nums:u32()
}).

init([]) ->
    {ok, waiting, #cell{}}.

handle_enter(_OldPhase, waiting, Cell) ->
    {Cell, actions(Cell)}.

handle_cast(#message{value = Value}, waiting, Cell) ->
    {waiting, Cell#cell{value = Value}, consume}.

actions(Cell) ->
    [{cast, out, #message{value = Cell#cell.value}}].
