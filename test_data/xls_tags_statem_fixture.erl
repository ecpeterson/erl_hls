-module(xls_tags_statem_fixture).

-xls_data(cell).
-xls_phases([waiting]).
-xls_outputs([out]).
-xls_mailbox_capacity(3).
-xls_tags([first]).
-include("xls_tags_shared.hrl").
-xls_tags([last]).

-record(first, {
    value = xls_type:zero() :: xls_nums:u32()
}).

-record(last, {
    value = xls_type:zero() :: xls_nums:u32()
}).

-record(cell, {
    value = xls_type:zero() :: xls_nums:u32()
}).

init([]) ->
    InitialPhase = waiting,
    {ok, InitialPhase, #cell{}}.

handle_enter(_OldPhase, waiting, Cell) ->
    {Cell, [{cast, out, #first{value = Cell#cell.value}}]}.

handle_cast(#first{value = Value}, waiting, Cell) ->
    {waiting, Cell#cell{value = Value}, consume};
handle_cast(#shared{value = Value}, waiting, Cell) ->
    {waiting, Cell#cell{value = Value}, consume};
handle_cast(#last{value = Value}, waiting, Cell) ->
    {waiting, Cell#cell{value = Value}, consume}.
