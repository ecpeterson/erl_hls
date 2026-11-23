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

-doc "Returns the fixture's declared initial callback state.".
-spec init([]) -> {'ok','boot',#cell{}}.
init([]) -> {ok, boot, #cell{}}.
-doc "Accepts configuration before entering the fixture's active phase.".
-spec boot('cast' | 'enter',term(),term()) -> {term(),[]} | {'sending',term(),'consume'}.
boot(enter, _, Cell) -> {Cell, []};
boot(cast, #kick{round = 0}, Cell) -> {sending, Cell, consume}.
-doc "Emits the next ordered batch of fixture work.".
-spec sending('cast' | 'enter',term(),#cell{round::number()}) -> {#cell{round::number()},[{'cast','first' | 'second',{term(),term()}},...]} | {'done',#cell{round::number()},'consume'} | {'repeat_phase',#cell{round::number()},'consume'}.
sending(enter, _, Cell) ->
    {Cell, [{cast, first, #work{sequence = 2 * Cell#cell.round}},
            {cast, second, #work{sequence = 2 * Cell#cell.round + 1}}]};
sending(cast, #kick{round = Round}, Cell) ->
    true = Round =:= Cell#cell.round + 1,
    if Round < 32 -> {repeat_phase, Cell#cell{round = Round}, consume};
       true -> {done, Cell#cell{round = Round}, consume}
    end.
-doc "Retains the completed fixture state without producing further work.".
-spec done('cast' | 'enter',term(),term()) -> {term(),[]} | {'done',term(),'fail'}.
done(enter, _, Cell) -> {Cell, []};
done(cast, #kick{}, Cell) -> {done, Cell, fail}.
