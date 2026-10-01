-module(hls_tags_statem_fixture).

-export([init/1, waiting/3]).

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

-spec waiting(enter, hls_statem:phase(), #cell{}) ->
        hls_statem:enter_result(#cell{});
    (cast, #first{} | #shared{} | #last{}, #cell{}) ->
        hls_statem:cast_result(#cell{}).
waiting(enter, _OldPhase, Cell) ->
    {Cell, [{cast, out, #first{value = Cell#cell.value}}]};
waiting(cast, #first{value = Value}, Cell) ->
    {waiting, Cell#cell{value = Value}, consume};
waiting(cast, #shared{value = Value}, Cell) ->
    {waiting, Cell#cell{value = Value}, consume};
waiting(cast, #last{value = Value}, Cell) ->
    {waiting, Cell#cell{value = Value}, consume}.
