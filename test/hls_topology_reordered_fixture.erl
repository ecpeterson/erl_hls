-module(hls_topology_reordered_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([waiting]).
-hls_outputs([message_out, padding_out]).
-hls_mailbox_capacity(1).
-hls_tags([padding, message]).

-export([init/1, waiting/3]).

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

-spec waiting(enter, hls_statem:phase(), #cell{}) ->
        hls_statem:enter_result(#cell{});
    (cast, #padding{} | #message{}, #cell{}) ->
        hls_statem:cast_result(#cell{}).
waiting(enter, _OldPhase, Cell) ->
    Value = Cell#cell.value,
    {Cell, [
        {cast, message_out, #message{value = Value}},
        {cast, padding_out, #padding{value = Value}}
    ]};
waiting(cast, #padding{value = Value}, Cell) ->
    {waiting, Cell#cell{value = Value}, consume};
waiting(cast, #message{value = Value}, Cell) ->
    {waiting, Cell#cell{value = Value}, consume}.
