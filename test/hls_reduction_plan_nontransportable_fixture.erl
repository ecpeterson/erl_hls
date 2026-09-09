-module(hls_reduction_plan_nontransportable_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([gathering]).
-hls_outputs([north, south]).
-hls_mailbox_capacity(2).
-hls_tags([message]).

-export([gathering/3, init/1, reduce/3]).

-record(message, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(sum, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(cell, {
    value = hls_type:zero() :: hls_nums:u32()
}).

init([]) ->
    {ok, gathering, #cell{}}.

gathering(enter, _OldPhase, Cell) ->
    Message = #message{value = Cell#cell.value},
    {Cell, [
        {open_reduction, sum, 0, {count, 2},
            {commutative_monoid, #sum{value = 0}}},
        {cast, north, Message},
        {cast, south, Message}
    ]};
gathering(cast, #message{value = Value}, Cell = #cell{}) ->
    {gathering, Cell, {contribute, sum, 0,
        #sum{value = Value}}};
gathering(internal,
        {reduction_complete, sum, 0, #sum{}}, Cell) ->
    {repeat_phase, Cell, consume}.

reduce(sum, #sum{value = Left}, #sum{value = Right}) ->
    #sum{value = Left + Right}.
