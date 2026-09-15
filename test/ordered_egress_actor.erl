%%%% ordered_egress_actor
%%%%
%%%% Small generated-RTL fixture for aliased source-order testing.

-module(ordered_egress_actor).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([emitting, done]).
-hls_outputs([first, second, third, loop]).
-hls_mailbox_capacity(1).
-hls_tags([ordered_value]).

-export([init/1, emitting/3, done/3]).

-define(ROUNDS, 16).

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
        {cast, third, #ordered_value{value = 4 * Cell#cell.value + 3}},
        {cast, first, #ordered_value{value = 4 * Cell#cell.value + 1}},
        {cast, second, #ordered_value{value = 4 * Cell#cell.value + 2}},
        {cast, loop, #ordered_value{value = Cell#cell.value + 1}}
    ]};
emitting(cast, #ordered_value{value = Value}, Cell) when Value < ?ROUNDS ->
    {repeat_phase, Cell#cell{value = Value}, consume};
emitting(cast, #ordered_value{value = Value}, Cell) ->
    {done, Cell#cell{value = Value}, consume}.

done(enter, _OldPhase, Cell) ->
    {Cell, [{cast, first, #ordered_value{value = 4 * Cell#cell.value}}]};
done(cast, #ordered_value{}, Cell) ->
    {done, Cell, consume}.
