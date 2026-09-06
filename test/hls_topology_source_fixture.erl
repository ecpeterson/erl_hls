-module(hls_topology_source_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([waiting]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-hls_tags([message]).

-export([init/1, callback_mode/0, waiting/3]).

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
    {keep_state, Cell, [{cast, out, #message{value = Cell#cell.value}}]};
waiting(cast, #message{value = Value}, Cell) ->
    {next_state, waiting, Cell#cell{value = Value}}.
