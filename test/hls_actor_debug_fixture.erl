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
boot(cast, #configure{value = Value}, Cell) ->
    {active, Cell#cell{value = Value}, consume}.
active(enter, _, Cell) ->
    %% Slot zero fails while its healthy neighbor emits a blocked report.
    Value = case Cell#cell.value of 1 -> Cell#cell.value end,
    {Cell, [{cast, out, #report{value = Value}}]};
active(cast, #configure{}, Cell) -> {active, Cell, consume}.
