-module(xls_entry_outcome_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([prefix, data, condition, message, precomputed, skipped, shared_values, empty, noncase, nonif, nonsegment, nonguarded, nonunused]).
-hls_outputs([first, second, third]).
-hls_mailbox_capacity(1).
-hls_tags([value]).

-export([init/1, prefix/3, data/3, condition/3, message/3,
    precomputed/3, skipped/3, shared_values/3, empty/3, noncase/3, nonif/3, nonsegment/3, nonguarded/3, nonunused/3]).

-record(value, {value = hls_type:zero() :: hls_nums:u32()}).
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) ->
    {ok, prefix, #cell{}}.

prefix(enter, _OldPhase, Cell) ->
    nonzero(Cell#cell.value),
    if
        Cell#cell.value band 1 =:= 0 -> Value = Cell#cell.value + 10;
        true -> Value = 10 + Cell#cell.value
    end,
    {Cell#cell{value = Value}, [
        {cast, third, #value{value = Value}},
        {cast, first, #value{value = Value + 1}}
    ]};
prefix(cast, #value{value = Value}, Cell) ->
    {message, Cell#cell{value = Value}, consume}.

data(enter, _OldPhase, Cell) ->
    {advance(Cell), [{cast, first, #value{value = 11}}]}.

condition(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 10}, [
        {cast, third, #value{value = 11}}
        | case true = (Cell#cell.value =/= 0) of
            true -> [{cast, first, #value{value = 12}}];
            false -> []
        end
    ]}.

message(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 10}, [
        {cast, third, #value{value = 11}},
        {cast, first, #value{value = nonzero(Cell#cell.value)}}
    ]}.

%% Constructing a named segment evaluates it even when it is later omitted.
precomputed(enter, _OldPhase, Cell) ->
    Optional = [{cast, first, #value{value = nonzero(Cell#cell.value)}}],
    {Cell#cell{value = Cell#cell.value + 10}, [
        {cast, third, #value{value = 11}}
        | case false of true -> Optional; false -> [] end
    ]}.

%% An unselected short-circuit branch must not contribute a failure.
skipped(enter, _OldPhase, Cell) ->
    Skipped = case false andalso (true = false) of
        true -> [{cast, third, #value{value = 11}}];
        false -> []
    end,
    Optional = case Cell#cell.value =/= 0 of
        true -> [{cast, second, #value{value = 12}}];
        false -> []
    end,
    {Cell#cell{value = Cell#cell.value + 10},
        Skipped ++ Optional ++ [{cast, first, #value{value = 13}}]}.

%% All projections share values and the failure predicate from one prefix.
shared_values(enter, _OldPhase, Cell) ->
    Next = Cell#cell.value + 10,
    First = Next + 1,
    Optional = case Cell#cell.value =/= 0 of
        true -> [{cast, second, #value{value = First + 1}},
            {cast, first, #value{value = Next}}];
        false -> []
    end,
    {Cell#cell{value = Next}, [
        {cast, third, #value{value = First}} | Optional
    ]}.

empty(enter, _OldPhase, Cell) ->
    true = Cell#cell.value =/= 0,
    {Cell#cell{value = Cell#cell.value + 10}, []}.

-spec nonzero(hls_nums:u32()) -> hls_nums:u32().
nonzero(Value) -> true = Value =/= 0, Value.

-spec advance(#cell{}) -> #cell{}.
advance(Cell) -> Cell#cell{value = nonzero(Cell#cell.value) + 10}.

%% No matching arm invalidates even the effects computed before the choice.
noncase(enter, _OldPhase, Cell) ->
    case Cell#cell.value of
        0 -> {Cell#cell{value = 10}, []};
        1 -> {Cell#cell{value = 11}, [{cast, first, #value{value = 12}}]}
    end.

nonif(enter, _OldPhase, Cell) ->
    if Cell#cell.value < 2 ->
        {Cell#cell{value = 10}, [{cast, second, #value{value = 13}}]}
    end.

nonsegment(enter, _OldPhase, Cell) ->
    {Cell#cell{value = 20}, [{cast, third, #value{value = 14}} |
        if Cell#cell.value =:= 0 -> [];
            Cell#cell.value =:= 1 -> [{cast, first, #value{value = 15}}]
        end]}.

nonguarded(enter, _OldPhase, Cell) ->
    Next = case Cell#cell.value of Value when Value < 2 -> Value + 10 end,
    {Cell#cell{value = Next}, [{cast, first, #value{value = Next}}]}.

nonunused(enter, _OldPhase, Cell) ->
    Unused = case Cell#cell.value of
        0 -> [{cast, first, #value{value = 17}}];
        1 -> []
    end,
    {Cell#cell{value = 30}, case false of true -> Unused; false -> [] end}.
