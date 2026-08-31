-module(xls_topology_source_fixture).

-behavior(xls_statem).
-compile({parse_transform, xls_pack}).

-xls_data(cell).
-xls_phases([waiting]).
-xls_outputs([out]).
-xls_mailbox_capacity(1).
-xls_tags([message]).

-export([handle_cast/3, handle_enter/3, init/1]).

-record(message, {
    value = xls_type:zero() :: xls_nums:u32()
}).

-record(cell, {
    value = xls_type:zero() :: xls_nums:u32()
}).

init([]) ->
    {ok, waiting, #cell{}}.

handle_enter(_OldPhase, waiting, Cell) ->
    {Cell, [{cast, out, #message{value = Cell#cell.value}}]}.

handle_cast(#message{value = Value}, waiting, Cell) ->
    {waiting, Cell#cell{value = Value}, consume}.
