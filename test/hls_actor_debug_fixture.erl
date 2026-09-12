-module(hls_actor_debug_fixture).
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, boot/3, active/3]).
-hls_data(cell).
-hls_phases([boot, active]).
-hls_outputs([out]).
-hls_mailbox_capacity(2).
-hls_tags([configure, report]).
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).
-record(configure, {value = hls_type:zero() :: hls_nums:u32()}).
-record(report, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, boot, #cell{}}.
boot(enter, _, Cell) -> {Cell, []};
boot(cast, #configure{value = 3}, Cell) ->
    Value = included_outer(0),
    {active, Cell#cell{value = Value}, consume};
boot(cast, #configure{value = 4}, Cell) ->
    {boot, Cell, fail};
boot(cast, #configure{value = Value}, Cell) when Value =/= 5 ->
    {active, Cell#cell{value = Value}, consume}.
active(enter, _, Cell) ->
    %% Independent failure origins coexist with healthy, backpressured actors.
    Value = case Cell#cell.value of
        0 -> included_outer(0);
        2 ->
            true = Cell#cell.value =:= 0,
            included_outer(0);
        6 -> included_if(Cell#cell.value);
        7 -> if Cell#cell.value =:= 7 -> hls_type:as(hls_nums:u32(), 1); true -> included_outer(0) end;
        1 -> Cell#cell.value
    end,
    {Cell, [{cast, out, #report{value = Value}}]};
active(cast, #configure{}, Cell) -> {active, Cell, consume}.

-include("hls_actor_debug_helpers.hrl").
