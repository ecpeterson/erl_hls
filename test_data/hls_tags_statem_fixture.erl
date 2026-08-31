-module(hls_tags_statem_fixture).

-hls_data(cell).
-hls_phases([waiting]).
-hls_outputs([out]).
-hls_mailbox_capacity(3).
-hls_tags([first]).
-include("hls_tags_shared.hrl").
-hls_tags([last]).

-record(first, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(last, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(cell, {
    value = hls_type:zero() :: hls_nums:u32()
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
