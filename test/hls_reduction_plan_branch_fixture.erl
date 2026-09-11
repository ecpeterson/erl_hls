-module(hls_reduction_plan_branch_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([idle, gathering, reporting]).
-hls_outputs([north, south, report, alternate]).
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

idle(enter, _OldPhase, Cell) ->
    {Cell, []};
idle(cast, #message{}, Cell) ->
    {gathering, Cell, consume}.

gathering(enter, _OldPhase, Cell) ->
    Message = #message{value = Cell#cell.value},
    {Cell, [
        {open_reduction, sum, 0, {count, 2},
            {commutative_monoid, #sum{value = 0}}},
        {cast, north, Message},
        {cast, south, Message}
        | case Cell#cell.value =:= 0 of
            true -> [{cast, report, #notice{value = 1}}];
            false -> [{cast, alternate, #notice{value = 2}}]
        end
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

reporting(enter, _OldPhase, Cell) ->
    {Cell, [{cast, report, #notice{value = Cell#cell.value}}]};
reporting(cast, #notice{}, Cell) ->
    {idle, Cell, consume}.

reduce(sum, #sum{value = Left}, #sum{value = Right}) ->
    #sum{value = Left + Right}.
