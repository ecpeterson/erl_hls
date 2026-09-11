-module(hls_reduction_plan_conditional_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([gathering]).
-hls_outputs([north, south]).
-hls_mailbox_capacity(2).
-hls_tags([message]).
-export([init/1, gathering/3, reduce/3]).

-record(message, {value = hls_type:zero() :: hls_nums:u32()}).
-record(sum, {value = hls_type:zero() :: hls_nums:u32()}).
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, gathering, #cell{}}.

gathering(enter, _OldPhase, Cell) ->
    Message = #message{value = Cell#cell.value},
    {Cell, [
        {open_reduction, sum, 0, {count, 2},
            {commutative_monoid, #sum{value = 0}}},
        {cast, south, Message}
        | case Cell#cell.value =:= 0 of
            true -> [{cast, north, Message}];
            false -> []
        end
    ]};
gathering(cast, #message{value = Value}, Cell) ->
    {gathering, Cell, {contribute, sum, 0, #sum{value = Value}}};
gathering(internal,
        {reduction_complete, sum, 0, #sum{}}, Cell) ->
    {repeat_phase, Cell, consume}.

reduce(sum, #sum{value = Left}, #sum{value = Right}) ->
    #sum{value = Left + Right}.
