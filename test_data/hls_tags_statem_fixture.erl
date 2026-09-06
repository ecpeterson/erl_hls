-module(hls_tags_statem_fixture).

-export([init/1, callback_mode/0, waiting/3]).

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

callback_mode() ->
    [state_functions, state_enter].

-spec waiting(hls_statem:event_type(), term(), #cell{}) ->
    hls_statem:enter_result() | hls_statem:state_result().
waiting(enter, _OldPhase, Cell) ->
    {keep_state, Cell, [{cast, out, #first{value = Cell#cell.value}}]};
waiting(cast, #first{value = Value}, Cell) ->
    {next_state, waiting, Cell#cell{value = Value}};
waiting(cast, #shared{value = Value}, Cell) ->
    {next_state, waiting, Cell#cell{value = Value}};
waiting(cast, #last{value = Value}, Cell) ->
    {next_state, waiting, Cell#cell{value = Value}}.
