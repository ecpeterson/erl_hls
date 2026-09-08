-module(hls_reduction_plan_inconsistent_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([first, second]).
-hls_outputs([north, east, west, south]).
-hls_mailbox_capacity(2).
-hls_tags([first_message, second_message]).
-export([init/1, first/3, second/3, reduce/3]).

-record(first_message, {value = hls_type:zero() :: hls_nums:u32()}).
-record(second_message, {value = hls_type:zero() :: hls_nums:u32()}).
-record(sum, {value = hls_type:zero() :: hls_nums:u32()}).
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, first, #cell{}}.

first(enter, _OldPhase, Cell) ->
    Message = #first_message{value = Cell#cell.value},
    {Cell, [
        {open_reduction, sum, 0, {count, 2},
            {commutative_monoid, #sum{value = 0}}},
        {cast, north, Message},
        {cast, south, Message}
    ]};
first(cast, #first_message{value = Value}, Cell) ->
    {first, Cell, {contribute, sum, 0, #sum{value = Value}}};
first(internal, {reduction_complete, sum, 0, #sum{}}, Cell) ->
    {second, Cell, consume}.

second(enter, _OldPhase, Cell) ->
    Message = #second_message{value = Cell#cell.value},
    {Cell, [
        {open_reduction, sum, 1, {count, 2},
            {commutative_monoid, #sum{value = 0}}},
        {cast, east, Message},
        {cast, west, Message}
    ]};
second(cast, #second_message{value = Value}, Cell) ->
    {second, Cell, {contribute, sum, 1, #sum{value = Value}}};
second(internal, {reduction_complete, sum, 1, #sum{}}, Cell) ->
    {first, Cell, consume}.

reduce(sum, #sum{value = Left}, #sum{value = Right}) ->
    #sum{value = Left + Right}.
