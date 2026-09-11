-module(xls_entry_branch_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([choice, nested, tail, appended, selected_failure, prefix_failure]).
-hls_outputs([first, second, third]).
-hls_mailbox_capacity(1).
-hls_tags([small, wide]).

-export([init/1, choice/3, nested/3, tail/3, appended/3,
    selected_failure/3, prefix_failure/3]).

-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).
-record(small, {value = hls_type:zero() :: hls_nums:u32()}).
-record(wide, {value = hls_type:zero() :: hls_nums:u32(),
    check = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, choice, #cell{}}.

%% Different schemas and ports at the same position; differing list lengths.
choice(enter, _OldPhase, Cell) ->
    case Cell#cell.value of
        0 -> {Cell, []};
        1 ->
            Message = #small{value = 11},
            {Cell#cell{value = 21}, [{cast, third, Message}]};
        2 ->
            {Cell#cell{value = 22}, [
                {cast, first, #wide{value = 12, check = 102}},
                {cast, third, #small{value = 13}}
            ]};
        _ ->
            {Cell#cell{value = 23}, [
                {cast, second, #wide{value = 14, check = 103}},
                {cast, first, #small{value = 15}},
                {cast, third, #wide{value = 16, check = 104}}
            ]}
    end;
choice(cast, #wide{value = Value}, Cell) ->
    {choice, Cell#cell{value = Value}, consume}.

%% Branch-local names, source-ordered overlapping guards, nested case/if.
nested(enter, _OldPhase, Cell) ->
    Xls_entry_0 = Cell#cell.value + 10,
    if
        Cell#cell.value < 2 ->
            Message = #wide{value = Xls_entry_0, check = 111},
            {Cell, case Cell#cell.value =:= 0 of
                true -> [{cast, second, Message}];
                false -> [{cast, first, Message}, {cast, third, #small{value = 2}}]
            end};
        Cell#cell.value < 4 ->
            Message = #small{value = 112},
            {Cell#cell{value = 10}, [{cast, first, Message}]};
        true ->
            {Cell, []}
    end.

%% A common head evaluates before the branch in its tail.
tail(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 10}, [
        {cast, third, #wide{value = Cell#cell.value, check = 200}}
        | case Cell#cell.value =:= 0 of
            true -> [];
            false -> [{cast, first, #small{value = 201}}]
        end
    ]}.

%% Both sides of concatenation can branch. Inactive payload failures must
%% not poison the selected result, and the suffix retains its source order.
appended(enter, _OldPhase, Cell) ->
    {Cell, (case Cell#cell.value band 1 =:= 0 of
        true -> [{cast, second, #small{value = 211}}];
        false -> []
    end) ++ (if
        Cell#cell.value < 4 -> [{cast, first, #wide{value = 212, check = 213}}];
        true -> []
    end) ++ [{cast, third, #small{value = 214}}]}.

selected_failure(enter, _OldPhase, Cell) ->
    {Cell#cell{value = 123}, [
        {cast, third, #small{value = 220}}
        | case Cell#cell.value =:= 0 of
            true -> [];
            false ->
                true = Cell#cell.value =:= 1,
                [{cast, first, #wide{value = 221, check = 222}}]
        end
    ]}.

prefix_failure(enter, _OldPhase, Cell) ->
    true = Cell#cell.value =/= 0,
    {Cell, if Cell#cell.value < 2 -> []; true ->
        [{cast, first, #wide{value = 230, check = 231}}]
    end}.
