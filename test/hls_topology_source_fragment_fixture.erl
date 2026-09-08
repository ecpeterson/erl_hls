-module(hls_topology_source_fragment_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([idle, gathering, reporting]).
-hls_outputs([north, south, report]).
-hls_mailbox_capacity(2).
-hls_tags([message, notice]).

-export([init/1, idle/3, gathering/3, reporting/3, reduce/3]).

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

init([]) ->
    {ok, idle, #cell{}}.

-spec idle(enter, hls_statem:phase(), #cell{}) ->
        hls_statem:enter_result(#cell{});
    (cast, #message{}, #cell{}) -> hls_statem:cast_result(#cell{}).
idle(enter, _OldPhase, Cell) ->
    {Cell, []};
idle(cast, #message{}, Cell) ->
    {gathering, Cell, consume}.

-spec gathering(enter, hls_statem:phase(), #cell{}) ->
        hls_statem:enter_result(#cell{});
    (cast, #message{}, #cell{}) -> hls_statem:cast_result(#cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) ->
        hls_statem:internal_result(#cell{}).
gathering(enter, _OldPhase, Cell) ->
    Value = Cell#cell.value,
    Message = #message{value = Value},
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

-spec reporting(enter, hls_statem:phase(), #cell{}) ->
        hls_statem:enter_result(#cell{});
    (cast, #notice{}, #cell{}) -> hls_statem:cast_result(#cell{}).
reporting(enter, _OldPhase, Cell) ->
    {Cell, [{cast, report, #notice{value = Cell#cell.value}}]};
reporting(cast, #notice{}, Cell) ->
    {idle, Cell, consume}.

reduce(sum, #sum{value = Left}, #sum{value = Right}) ->
    #sum{value = Left + Right}.
