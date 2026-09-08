-module(hls_reduction_plan_population_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([counting, collecting]).
-hls_outputs([north, south]).
-hls_mailbox_capacity(2).
-hls_tags([count_message, member_message]).
-export([init/1, counting/3, collecting/3, reduce/3]).

-record(count_message, {value = hls_type:zero() :: hls_nums:u32()}).
-record(member_message, {
    member = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()
}).
-record(sum, {value = hls_type:zero() :: hls_nums:u32()}).
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, counting, #cell{}}.

counting(enter, _OldPhase, Cell) ->
    Message = #count_message{value = Cell#cell.value},
    {Cell, [
        {open_reduction, sum, 0, {count, 2},
            {commutative_monoid, #sum{value = 0}}},
        {cast, north, Message},
        {cast, south, Message}
    ]};
counting(cast, #count_message{value = Value}, Cell) ->
    {counting, Cell, {contribute, sum, 0, #sum{value = Value}}};
counting(internal, {reduction_complete, sum, 0, #sum{}}, Cell) ->
    {collecting, Cell, consume}.

collecting(enter, _OldPhase, Cell) ->
    North = #member_message{member = 0, value = Cell#cell.value},
    South = #member_message{member = 1, value = Cell#cell.value},
    {Cell, [
        {open_reduction, sum, 1, {members, [0, 1]},
            {commutative_monoid, #sum{value = 0}}},
        {cast, north, North},
        {cast, south, South}
    ]};
collecting(
    cast,
    #member_message{member = Member, value = Value},
    Cell
) ->
    {collecting, Cell,
        {contribute, sum, 1, Member, #sum{value = Value}}};
collecting(internal, {reduction_complete, sum, 1, #sum{}}, Cell) ->
    {counting, Cell, consume}.

reduce(sum, #sum{value = Left}, #sum{value = Right}) ->
    #sum{value = Left + Right}.
