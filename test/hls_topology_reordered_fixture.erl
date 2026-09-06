-module(hls_topology_reordered_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([waiting]).
-hls_outputs([message_out, padding_out]).
-hls_mailbox_capacity(1).
-hls_tags([padding, message]).

-export([init/1, callback_mode/0, waiting/3]).

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

callback_mode() ->
    [state_functions, state_enter].

-spec waiting(hls_statem:event_type(), term(), #cell{}) ->
    hls_statem:enter_result() | hls_statem:state_result().
waiting(enter, _OldPhase, Cell) ->
    Value = Cell#cell.value,
    {keep_state, Cell, [
        {cast, message_out, #message{value = Value}},
        {cast, padding_out, #padding{value = Value}}
    ]};
waiting(cast, #padding{value = Value}, Cell) ->
    {next_state, waiting, Cell#cell{value = Value}};
waiting(cast, #message{value = Value}, Cell) ->
    {next_state, waiting, Cell#cell{value = Value}}.
