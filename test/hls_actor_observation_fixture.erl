-module(hls_actor_observation_fixture).
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, boot/3, active/3]).
-hls_data(cell).
-hls_phases([boot, active]).
-hls_outputs([first, second]).
-hls_mailbox_capacity(1).
-hls_tags([configure, report]).
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).
-record(configure, {value = hls_type:zero() :: hls_nums:u32()}).
-record(report, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, boot, #cell{}}.
boot(enter, _, Cell) -> {Cell, []};
boot(cast, #configure{value = Value}, Cell) ->
    {active, Cell#cell{value = Value}, consume}.
active(enter, _, Cell) ->
    {Cell, [{cast, first, #report{value = Cell#cell.value}},
        {cast, second, #report{value = Cell#cell.value + 1}}]};
active(cast, #configure{}, Cell) -> {active, Cell, consume}.
