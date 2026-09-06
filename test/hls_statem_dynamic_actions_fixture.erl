-module(hls_statem_dynamic_actions_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([waiting]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-hls_tags([message]).

-export([init/1, waiting/3]).

-record(message, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(cell, {
    value = hls_type:zero() :: hls_nums:u32()
}).

init([]) ->
    {ok, waiting, #cell{}}.

-spec waiting(hls_statem:event_type(), term(), #cell{}) ->
    hls_statem:callback_result(#cell{}).
waiting(enter, _OldPhase, Cell) ->
    {Cell, actions(Cell)};
waiting(cast, #message{value = Value}, Cell) ->
    {waiting, Cell#cell{value = Value}, consume}.

actions(Cell) ->
    [{cast, out, #message{value = Cell#cell.value}}].
