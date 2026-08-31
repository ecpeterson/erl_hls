%%%% ordered_egress_actor
%%%%
%%%% Small generated-RTL fixture for aliased source-order testing.

-module(ordered_egress_actor).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([emitting]).
-hls_outputs([first, second, third, loop]).
-hls_mailbox_capacity(1).
-hls_tags([ordered_value]).

-export([handle_cast/3, handle_enter/3, init/1]).

-record(ordered_value, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(cell, {
    value = hls_type:zero() :: hls_nums:u32()
}).

init([]) ->
    {ok, emitting, #cell{}}.

handle_enter(_OldPhase, emitting, Cell) ->
    {Cell, [
        {cast, third, #ordered_value{value = 3}},
        {cast, first, #ordered_value{value = 1}},
        {cast, second, #ordered_value{value = 2}},
        {cast, loop, #ordered_value{value = 0}}
    ]}.

handle_cast(#ordered_value{value = Value}, emitting, Cell) ->
    {emitting, Cell#cell{value = Value}, consume}.
