-module(xls_entry_branch_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([choice, nested, tail, appended, selected_failure, prefix_failure,
    bound, bound_tail, bound_tuple, discarded]).
-hls_outputs([first, second, third]).
-hls_mailbox_capacity(1).
-hls_tags([small, wide]).

-export([init/1, choice/3, nested/3, tail/3, appended/3,
    selected_failure/3, prefix_failure/3, bound/3, bound_tail/3,
    bound_tuple/3, discarded/3]).

-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).
-record(small, {value = hls_type:zero() :: hls_nums:u32()}).
-record(wide, {value = hls_type:zero() :: hls_nums:u32(),
    check = hls_type:zero() :: hls_nums:u32()}).

-doc "Returns the fixture's declared initial callback state.".
-spec init([]) -> {ok, hls_statem:phase(), #cell{}}.
init([]) -> {ok, choice, #cell{}}.

%% Different schemas and ports at the same position; differing list lengths.
-doc "Exercises entry alternatives with different bounded effect lists.".
-spec choice(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{}).
choice(enter, _OldPhase, Cell) ->
    Result = case Cell#cell.value of
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
    end,
    Alias = Result,
    Alias;
choice(cast, #wide{value = Value}, Cell) ->
    {choice, Cell#cell{value = Value}, consume}.

%% Branch-local names, source-ordered overlapping guards, nested case/if.
-doc "Exercises nested branch selection in phase-entry results.".
-spec nested(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
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
-doc "Exercises a conditional tail following a common effect prefix.".
-spec tail(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
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
-doc "Exercises concatenated literal action-list segments.".
-spec appended(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
appended(enter, _OldPhase, Cell) ->
    {Cell, (case Cell#cell.value band 1 =:= 0 of
        true -> [{cast, second, #small{value = 211}}];
        false -> []
    end) ++ (if
        Cell#cell.value < 4 -> [{cast, first, #wide{value = 212, check = 213}}];
        true -> []
    end) ++ [{cast, third, #small{value = 214}}]}.

-doc "Checks that a failure in the selected branch suppresses the whole entry.".
-spec selected_failure(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
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

-doc "Checks that a failing eager prefix suppresses later entry effects.".
-spec prefix_failure(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
prefix_failure(enter, _OldPhase, Cell) ->
    true = Cell#cell.value =/= 0,
    {Cell, if Cell#cell.value < 2 -> []; true ->
        [{cast, first, #wide{value = 230, check = 231}}]
    end}.

%% One choice binds the new state and a variable-length, heterogeneous batch.
-doc "Exercises a named entry result without reevaluating captured payloads.".
-spec bound(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
bound(enter, _OldPhase, Cell) ->
    Result = case Cell#cell.value of
        0 -> {Cell#cell{value = 30}, []};
        1 ->
            Message = #wide{value = 31, check = 301},
            {Cell#cell{value = 31}, [{cast, first, Message}]};
        _ -> {Cell#cell{value = 32}, [
            {cast, second, #small{value = 32}},
            {cast, third, #small{value = 33}}
        ]}
    end,
    {Next, Actions} = Result,
    Outcome = {Next, Actions},
    Outcome.

%% Branch-local segment aliases compose with later choices and common heads.
-doc "Exercises a named action-list tail selected by a branch.".
-spec bound_tail(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
bound_tail(enter, _OldPhase, Cell) ->
    Tail = case Cell#cell.value band 1 of
        0 ->
            Local = [{cast, first, #small{value = 40}}],
            Local;
        _ ->
            Message = #wide{value = 41, check = 401},
            [{cast, second, Message}]
    end,
    Selected = if Cell#cell.value < 4 -> Tail; true -> [] end,
    {Cell, [{cast, third, #small{value = 42}} | Selected]}.

%% Nested tuple destructuring and two independently named list fields.
-doc "Exercises tuple binding of data and ordered action segments.".
-spec bound_tuple(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
bound_tuple(enter, _OldPhase, Cell) ->
    {{Next, Before}, After} = if
        Cell#cell.value < 2 ->
            true = Cell#cell.value =/= 0,
            {{Cell#cell{value = 50}, [{cast, second, #small{value = 51}}]}, []};
        true ->
            {{Cell#cell{value = 52}, []}, [{cast, first, #wide{value = 53, check = 501}}]}
    end,
    {Next, Before ++ [{cast, third, #small{value = 54}}] ++ After}.

%% Discarding an evaluated segment does not discard its match-failure check.
-doc "Checks that discarded eager computations retain their failure behavior.".
-spec discarded(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
discarded(enter, _OldPhase, Cell) ->
    _ = case Cell#cell.value of
        0 ->
            true = false,
            [{cast, first, #small{value = 60}}];
        _ -> []
    end,
    {Cell#cell{value = 61}, [{cast, third, #small{value = 62}}]}.
