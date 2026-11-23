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

-doc "Returns the fixture's declared initial callback state.".
-spec init([]) -> {'ok','first',#cell{}}.
init([]) -> {ok, first, #cell{}}.

-doc "Exercises the first reduction site in the inconsistent-pattern witness.".
-spec first('cast' | 'enter' | 'internal',term(),term()) -> {#cell{},[{'cast','north' | 'south',{term(),term()}} | {'open_reduction','sum',0,{term(),term()},{term(),term()}},...]} | {'first',term(),{'contribute','sum',0,#sum{}}} | {'second',term(),'consume'}.
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

-doc "Exercises the second reduction site in the inconsistent-pattern witness.".
-spec second('cast' | 'enter' | 'internal',term(),term()) -> {#cell{},[{'cast','east' | 'west',{term(),term()}} | {'open_reduction','sum',1,{term(),term()},{term(),term()}},...]} | {'first',term(),'consume'} | {'second',term(),{'contribute','sum',1,#sum{}}}.
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

-doc "Combines fixture contributions using its declared bounded arithmetic.".
-spec reduce('sum',#sum{value::number()},#sum{value::number()}) -> #sum{value::number()}.
reduce(sum, #sum{value = Left}, #sum{value = Right}) ->
    #sum{value = Left + Right}.
