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

-export([init/1, emitting/3]).

-record(ordered_value, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(cell, {
    value = hls_type:zero() :: hls_nums:u32()
}).

init([]) ->
    {ok, emitting, #cell{}}.

-spec emitting(enter, hls_statem:phase(), #cell{}) ->
        hls_statem:enter_result(#cell{});
    (cast, #ordered_value{}, #cell{}) -> hls_statem:cast_result(#cell{}).
emitting(enter, _OldPhase, Cell) ->
    {Cell, [
        {cast, third, #ordered_value{value = 3}},
        {cast, first, #ordered_value{value = 1}},
        {cast, second, #ordered_value{value = 2}},
        {cast, loop, #ordered_value{value = 0}}
    ]};
emitting(cast, #ordered_value{value = Value}, Cell) ->
    {emitting, Cell#cell{value = Value}, consume}.
