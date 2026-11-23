-module(hls_topology_source_fragment_port_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([gathering, reporting]).
-hls_outputs([north, south, report]).
-hls_mailbox_capacity(2).
-hls_tags([message, notice]).

-export([init/1, gathering/3, reporting/3, reduce/3]).

-record(message, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(notice, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(sum, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(cell, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-doc "Returns the fixture's declared initial callback state.".
-spec init([]) -> {'ok','gathering',#cell{}}.
init([]) ->
    {ok, gathering, #cell{}}.

-doc "Opens the fixture reduction and accepts its declared contribution messages.".
-spec gathering('cast' | 'enter' | 'internal',term(),term()) -> {#cell{},[{'cast','north' | 'south',{term(),term()}} | {'open_reduction','sum',0,{term(),term()},{term(),term()}},...]} | {'gathering',term(),{'contribute','sum',0,#sum{}}} | {'reporting',#cell{},'consume'}.
gathering(enter, _OldPhase, Cell) ->
    Message = #message{value = Cell#cell.value},
    {Cell, [
        {open_reduction, sum, 0, {count, 2},
            {commutative_monoid, #sum{value = 0}}},
        {cast, north, Message},
        {cast, south, Message}
    ]};
gathering(cast, #message{value = Value}, Cell) ->
    {gathering, Cell,
        {contribute, sum, 0, #sum{value = Value}}};
gathering(
    internal,
    {reduction_complete, sum, 0, #sum{value = Total}},
    Cell
) ->
    {reporting, Cell#cell{value = Total}, consume}.

-doc "Publishes the completed fixture result through its declared output.".
-spec reporting('cast' | 'enter',term(),term()) -> {#cell{},[{'cast','north' | 'report',{term(),term()}},...]} | {'reporting',term(),'consume'}.
reporting(enter, _OldPhase, Cell) ->
    Notice = #notice{value = Cell#cell.value},
    {Cell, [
        {cast, north, Notice},
        {cast, report, Notice}
    ]};
reporting(cast, #notice{}, Cell) ->
    {reporting, Cell, consume}.

-doc "Combines fixture contributions using its declared bounded arithmetic.".
-spec reduce('sum',#sum{value::number()},#sum{value::number()}) -> #sum{value::number()}.
reduce(sum, #sum{value = Left}, #sum{value = Right}) ->
    #sum{value = Left + Right}.
