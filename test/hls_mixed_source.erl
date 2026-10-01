-module(hls_mixed_source).
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, boot/3, sending/3, done/3]).
-hls_data(cell).
-hls_phases([boot, sending, done]).
-hls_outputs([first, second]).
-hls_mailbox_capacity(2).
-include("hls_mixed_protocol.hrl").
-record(cell, {round = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, boot, #cell{}}.
boot(enter, _, Cell) -> {Cell, []};
boot(cast, #kick{round = 0}, Cell) -> {sending, Cell, consume}.
sending(enter, _, Cell) ->
    {Cell, [{cast, first, #work{sequence = 2 * Cell#cell.round}},
            {cast, second, #work{sequence = 2 * Cell#cell.round + 1}}]};
sending(cast, #kick{round = Round}, Cell) ->
    true = Round =:= Cell#cell.round + 1,
    if Round < 32 -> {repeat_phase, Cell#cell{round = Round}, consume};
       true -> {done, Cell#cell{round = Round}, consume}
    end.
done(enter, _, Cell) -> {Cell, []};
done(cast, #kick{}, Cell) -> {done, Cell, fail}.
