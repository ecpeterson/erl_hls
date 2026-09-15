-module(hls_list_reduction_fixture).
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, gathering/3, done/3, reduce/3]).
-hls_data(cell).
-hls_phases([gathering, done]).
-hls_outputs([out]).
-hls_mailbox_capacity(2).
-hls_tags([value]).
-record(cell, {value = hls_type:zero() :: hls_nums:u32(),
    values = hls_type:zero() :: hls_vec:vector(hls_nums:u32(), 2)}).
-record(value, {key = hls_type:zero() :: hls_nums:u32(),
    values = hls_type:zero() :: hls_vec:vector(hls_nums:u32(), 2)}).
-record(sum, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, gathering, #cell{}}.
gathering(enter, _, Cell) ->
    {Cell, [{open_reduction, sum, 0, {count, 2}, {commutative_monoid, #sum{value = 0}}}]};
gathering(cast, #value{key = Key, values = [A, B]}, Cell) ->
    {gathering, Cell, {contribute, sum, Key, #sum{value = A + B}}};
gathering(internal, {reduction_complete, sum, _Key, #sum{value = Value}}, Cell) ->
    {done, Cell#cell{value = Value}, consume}.
done(enter, _, Cell) -> {Cell, []}.
reduce(sum, #sum{value = A}, #sum{value = B}) -> #sum{value = A + B}.
