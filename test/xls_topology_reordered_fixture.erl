-module(xls_topology_reordered_fixture).

-behavior(xls_statem).
-compile({parse_transform, xls_pack}).

-xls_data(cell).
-xls_phases([waiting]).
-xls_outputs([message_out, padding_out]).
-xls_mailbox_capacity(1).
-xls_tags([padding, message]).

-export([handle_cast/3, handle_enter/3, init/1]).

-record(padding, {
    value = xls_type:zero() :: xls_nums:u32()
}).

-record(message, {
    value = xls_type:zero() :: xls_nums:u32()
}).

-record(cell, {
    value = xls_type:zero() :: xls_nums:u32()
}).

init([]) ->
    {ok, waiting, #cell{}}.

handle_enter(_OldPhase, waiting, Cell) ->
    Value = Cell#cell.value,
    {Cell, [
        {cast, message_out, #message{value = Value}},
        {cast, padding_out, #padding{value = Value}}
    ]}.

handle_cast(#padding{value = Value}, waiting, Cell) ->
    {waiting, Cell#cell{value = Value}, consume};
handle_cast(#message{value = Value}, waiting, Cell) ->
    {waiting, Cell#cell{value = Value}, consume}.
