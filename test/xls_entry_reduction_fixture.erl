-module(xls_entry_reduction_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([gathering, invalid_identity, optional]).
-hls_outputs([first, second]).
-hls_mailbox_capacity(1).
-hls_tags([value, other_value, optional_value]).

-export([init/1, gathering/3, invalid_identity/3, optional/3, reduce/3]).

-record(value, {value = hls_type:zero() :: hls_nums:u32()}).
-record(other_value, {value = hls_type:zero() :: hls_nums:u32()}).
-record(optional_value, {value = hls_type:zero() :: hls_nums:u32()}).
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).
-record(sum, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, gathering, #cell{}}.

gathering(enter, _OldPhase, Cell) ->
    true = Cell#cell.value =/= 0,
    {Cell#cell{value = Cell#cell.value + 10}, [
        {open_reduction, sum, Cell#cell.value, {count, 1},
            {commutative_monoid, #sum{value = 3}}},
        {cast, first, #value{value = 11}},
        {cast, second, #value{value = case Cell#cell.value =/= 1 of
            true -> Cell#cell.value;
            false -> true = false, Cell#cell.value
        end}}
    ]};
gathering(cast, #value{value = Value}, Cell) ->
    {gathering, Cell, {contribute, sum, Value, #sum{value = Value}}};
gathering(internal, {reduction_complete, sum, _Key, #sum{}}, Cell) ->
    {invalid_identity, Cell, consume}.

invalid_identity(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 10}, [
        {open_reduction, sum, 7, {count, 1},
            {commutative_monoid, #sum{value = case true of
                true -> true = false, hls_type:as(hls_nums:u32(), 3);
                false -> hls_type:as(hls_nums:u32(), 0)
            end}}},
        {cast, first, #value{value = 11}}
    ]};
invalid_identity(cast, #other_value{value = Value}, Cell) ->
    {invalid_identity, Cell, {contribute, sum, 7, #sum{value = Value}}};
invalid_identity(internal, {reduction_complete, sum, _Key, #sum{}}, Cell) ->
    {gathering, Cell, consume}.

reduce(sum, #sum{value = Left}, #sum{value = Right}) ->
    #sum{value = Left + Right}.

%% The non-opening branch must preserve an already open reduction.
optional(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 10}, case Cell#cell.value =:= 0 of
        true -> [];
        false -> [
            {open_reduction, sum, Cell#cell.value, {count, 1},
                {commutative_monoid, #sum{value = 3}}},
            {cast, first, #value{value = Cell#cell.value}}
        ]
    end};
optional(cast, #optional_value{value = Value}, Cell) ->
    {optional, Cell, {contribute, sum, Value, #sum{value = Value}}};
optional(internal, {reduction_complete, sum, _Key, #sum{}}, Cell) ->
    {gathering, Cell, consume}.
