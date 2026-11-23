-module(hls_mixed_worker).
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, boot/3, active/3]).
-hls_data(cell).
-hls_phases([boot, active]).
-hls_outputs([result_a, result_b]).
-hls_mailbox_capacity(2).
-include("hls_mixed_protocol.hrl").
-record(cell, {id = hls_type:zero() :: hls_nums:u32(),
               next = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, boot, #cell{}}.
boot(enter, _, Cell) -> {Cell, []};
boot(cast, #configure{id = Id}, Cell) -> {active, Cell#cell{id = Id}, consume}.
active(enter, _, Cell) ->
    Actions = if Cell#cell.next =:= 0 -> [];
        true -> [
            {cast, result_a, #result{id = Cell#cell.id, sequence = 2 * (Cell#cell.next - 1)}},
            {cast, result_b, #result{id = Cell#cell.id, sequence = 2 * (Cell#cell.next - 1) + 1}}]
    end,
    {Cell, Actions};
active(cast, #pulse{value = 0}, Cell) -> {active, Cell, consume};
active(cast, #work{sequence = Sequence}, Cell) ->
    %% A reordered aliased port or routed input preceding startup fails here.
    true = Sequence =:= Cell#cell.next,
    {repeat_phase, Cell#cell{next = Sequence + 1}, consume}.
