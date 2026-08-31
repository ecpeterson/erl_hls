-module(hls_topology_reordered_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([waiting]).
-hls_outputs([message_out, padding_out]).
-hls_mailbox_capacity(1).
-hls_tags([padding, message]).

-export([handle_cast/3, handle_enter/3, init/1]).

-record(padding, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(message, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(cell, {
    value = hls_type:zero() :: hls_nums:u32()
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
