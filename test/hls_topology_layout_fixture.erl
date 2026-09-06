-module(hls_topology_layout_fixture).

-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([waiting]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-hls_tags([message]).

-export([init/1, waiting/3]).

-record(message, {
    value = hls_type:zero() :: hls_nums:u64()
}).

-record(cell, {
    value = hls_type:zero() :: hls_nums:u64()
}).

init([]) ->
    {ok, waiting, #cell{}}.

-spec waiting(enter, hls_statem:phase(), #cell{}) ->
        hls_statem:enter_result(#cell{});
    (cast, #message{}, #cell{}) -> hls_statem:cast_result(#cell{}).
waiting(enter, _OldPhase, Cell) ->
    {Cell, [{cast, out, #message{value = Cell#cell.value}}]};
waiting(cast, #message{value = Value}, Cell) ->
    {waiting, Cell#cell{value = Value}, consume}.
