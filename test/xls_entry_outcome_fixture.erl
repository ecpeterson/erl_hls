-module(xls_entry_outcome_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([prefix, data, condition, message, disabled, skipped, shared_values, empty]).
-hls_outputs([first, second, third]).
-hls_mailbox_capacity(1).
-hls_tags([value]).

-export([init/1, prefix/3, data/3, condition/3, message/3,
    disabled/3, skipped/3, shared_values/3, empty/3]).

-record(value, {value = hls_type:zero() :: hls_nums:u32()}).
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) ->
    {ok, prefix, #cell{}}.

prefix(enter, _OldPhase, Cell) ->
    true = Cell#cell.value =/= 0,
    Value = Cell#cell.value + 10,
    {Cell#cell{value = Value}, [
        {cast, third, #value{value = Value}},
        {cast, first, #value{value = Value + 1}}
    ]};
prefix(cast, #value{value = Value}, Cell) ->
    {message, Cell#cell{value = Value}, consume}.

data(enter, _OldPhase, Cell) ->
    {case Cell#cell.value =/= 0 of
        true -> Cell#cell{value = Cell#cell.value + 10};
        false -> true = false, Cell
    end, [{cast, first, #value{value = 11}}]}.

condition(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 10}, [
        {cast, third, #value{value = 11}},
        {cast_if, true = (Cell#cell.value =/= 0), first, #value{value = 12}}
    ]}.

message(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 10}, [
        {cast, third, #value{value = 11}},
        {cast, first, #value{value = case Cell#cell.value =/= 0 of
            true -> Cell#cell.value;
            false -> true = false, Cell#cell.value
        end}}
    ]}.

%% cast_if suppresses sending, not evaluation of the returned message.
disabled(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 10}, [
        {cast, third, #value{value = 11}},
        {cast_if, false, first, #value{value = case Cell#cell.value =/= 0 of
            true -> Cell#cell.value;
            false -> true = false, Cell#cell.value
        end}}
    ]}.

%% An unselected short-circuit branch must not contribute a failure.
skipped(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 10}, [
        {cast_if, false andalso (true = false), third, #value{value = 11}},
        {cast_if, Cell#cell.value =/= 0, second, #value{value = 12}},
        {cast, first, #value{value = 13}}
    ]}.

%% All projections share values and the failure predicate from one prefix.
shared_values(enter, _OldPhase, Cell) ->
    Next = Cell#cell.value + 10,
    First = Next + 1,
    Enabled = Cell#cell.value =/= 0,
    {Cell#cell{value = Next}, [
        {cast, third, #value{value = First}},
        {cast_if, Enabled, second,
            #value{value = First + 1}},
        {cast_if, Enabled, first, #value{value = Next}}
    ]}.

empty(enter, _OldPhase, Cell) ->
    true = Cell#cell.value =/= 0,
    {Cell#cell{value = Cell#cell.value + 10}, []}.
