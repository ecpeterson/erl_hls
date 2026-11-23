-module(hls_actor_pid_fixture).
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, ready/3, odd/3, even/3]).
-hls_data(cell).
-hls_phases([ready, odd, even]).
-hls_outputs([out]).
-hls_mailbox_capacity(2).
-hls_tags([work, report]).

-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).
-record(work, {value = hls_type:zero() :: hls_nums:u32()}).
-record(report, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, ready, #cell{}}.
ready(enter, _, Cell) -> {Cell, []};
ready(cast, #work{value = Value}, Cell) ->
    {odd, Cell#cell{value = Value}, consume}.
odd(enter, _, Cell) -> {Cell, [{cast, out, #report{value = Cell#cell.value}}]};
odd(cast, #work{value = Value}, Cell) ->
    {even, Cell#cell{value = Value}, consume}.
even(enter, _, Cell) -> {Cell, [{cast, out, #report{value = Cell#cell.value}}]};
even(cast, #work{value = Value}, Cell) ->
    {odd, Cell#cell{value = Value}, consume}.
