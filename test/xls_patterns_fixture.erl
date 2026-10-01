%% A fixed, reviewable corpus. Expected values and exception kinds come from BEAM.
-module(xls_patterns_fixture).
-compile([export_all, nowarn_export_all]).
-hls_data(cell).
-hls_tags([]).
-record(cell, {values = hls_type:zero() :: hls_vec:vector(hls_nums:s32(), 3)}).

probes() -> [exact, prefix, tail_alias, repeated, bound, assignment, assignment_failure,
    whole_alias, short_case, short_assignment, long_case, skipped_failure, helper_head,
    helper_clauses, helper_miss, helper_repeated, joined_tail, first_failure,
    argument_failure, record_assignment, tuple_lists, negative, guarded_head,
    tail_result, tail_match, literal_assignment, nested_case, helper_body_failure,
    helper_body_match, matrix_tail, record_helper, tuple_helper].

exact(_, Values) ->
    case Values of [A, B, C] -> A + B + C end.
prefix(_, Values) ->
    [Head | Tail] = Values,
    Head + hls_vec:nth(1, Tail).
tail_alias(_, Values) ->
    case Values of [A | Rest = [B, C]] -> A + B + C + hls_vec:nth(2, Rest) end.
repeated(_, Values) ->
    case Values of [A, A, B] -> A + B; [A, B, C] -> A - B - C end.
bound(X, Values) ->
    case Values of [X | _] -> X; [_, B, _] -> B end.
assignment(_, Values) ->
    [A, B, C] = Values,
    A - B + C.
assignment_failure(X, Values) ->
    [X, 0, _] = Values,
    X.
whole_alias(_, Values) ->
    Whole = [A | Rest] = Values,
    A + hls_vec:nth(2, Rest) + hls_vec:nth(1, Whole).
short_case(_, Values) ->
    case Values of [] -> hls_type:as(hls_nums:s32(), 0); [A] -> A end.
short_assignment(X, Values) ->
    [_] = Values,
    X.
long_case(_, Values) ->
    case Values of [A, _, _, A] -> A; [_, B, _] -> B end.
skipped_failure(_, Values) ->
    case Values of [] -> hls_type:as(hls_nums:s32(), 1) div 0; [A | _] -> A end.
helper_head(_, Values) -> sum(Values).
helper_clauses(_, Values) -> choose(Values).
helper_miss(_, Values) -> only_zero(Values).
helper_repeated(X, Values) -> same(X, hls_vec:nth(1, Values)).
joined_tail(X, Values) ->
    case X > 0 of
        true -> [_ | Tail] = Values, X;
        false -> [_, _ | Last] = Values, Tail = prepend_zero(Last), X
    end,
    hls_vec:nth(1, Tail).
first_failure(X, Values) ->
    _ = hls_type:as(hls_nums:s32(), 1) div X,
    [0 | _] = Values,
    X.
argument_failure(X, Values) ->
    same(hls_type:as(hls_nums:s32(), 1) div X, hls_vec:nth(1, Values)).
record_assignment(_, Values) ->
    Record = #cell{values = Values},
    #cell{values = [A, B, C]} = Record,
    A + B - C.
tuple_lists(_, Values) ->
    {Whole = [A | _], [B, _, C]} = {Values, Values},
    A + B + C + hls_vec:nth(2, Whole).
negative(_, Values) ->
    case Values of [-1, A, _] -> A; [A | _] -> A end.
guarded_head(X, Values) -> guard_choice(X, Values).
tail_result(_, Values) ->
    hls_vec:nth(2, drop_head(Values)).
tail_match(_, Values) ->
    [_ | Tail] = Values,
    [A | [B]] = Tail,
    A + B.
literal_assignment(_, Values) ->
    -1 = hls_vec:nth(1, Values),
    hls_vec:nth(3, Values).
nested_case(X, Values) ->
    case {X, #cell{values = Values}} of
        {0, #cell{values = [A, A | _]}} -> A;
        {_, #cell{values = [_, B, _]}} -> B
    end.

helper_body_failure(_, Values) -> selected_failure(Values).
helper_body_match(_, Values) -> selected_match(Values).
matrix_tail(_, Values) ->
    Matrix = hls_vec:set(2, hls_lists:new(hls_vec:vector(hls_nums:s32(), 3), 2), Values),
    [_ | Rows] = Matrix,
    [[A, B, C]] = Rows,
    A + B + C.
record_helper(_, Values) -> record_choice(#cell{values = Values}).
tuple_helper(X, Values) -> tuple_choice({X, #cell{values = Values}}).

-spec record_choice(#cell{}) -> hls_nums:s32().
record_choice(Whole = #cell{values = [A, A | _]}) when A > 0 ->
    hls_vec:nth(3, Whole#cell.values);
record_choice(#cell{values = [A, B, C]}) -> A + B - C.
-spec tuple_choice({hls_nums:s32(), #cell{}}) -> hls_nums:s32().
tuple_choice({0, #cell{values = [A, A | _]}}) -> A;
tuple_choice({X, #cell{values = [_, B, _]}}) when X =/= 0 -> X + B.

-spec selected_failure(hls_vec:vector(hls_nums:s32(), 3)) -> hls_nums:s32().
selected_failure([0 | _]) -> hls_type:as(hls_nums:s32(), 1) div 0;
selected_failure([A | _]) -> A.
-spec selected_match(hls_vec:vector(hls_nums:s32(), 3)) -> hls_nums:s32().
selected_match(Whole = [A, A | _]) -> [A, 0, _] = Whole, A;
selected_match([A | _]) -> A.

-spec sum(hls_vec:vector(hls_nums:s32(), 3)) -> hls_nums:s32().
sum([A, B, C]) -> A + B + C.
-spec choose(hls_vec:vector(hls_nums:s32(), 3)) -> hls_nums:s32().
choose([A, A | _]) when A =/= 0 -> A;
choose([_, 0, C]) -> C;
choose([A, B, C]) -> A + B + C.
-spec only_zero(hls_vec:vector(hls_nums:s32(), 3)) -> hls_nums:s32().
only_zero([0, A | _]) -> A.
-spec same(hls_nums:s32(), hls_nums:s32()) -> hls_nums:s32().
same(X, X) -> X.
-spec guard_choice(hls_nums:s32(), hls_vec:vector(hls_nums:s32(), 3)) -> hls_nums:s32().
guard_choice(X, [A | _]) when A div X > 0; X =:= 0 -> A;
guard_choice(_, [_, B | _]) -> B.
-spec drop_head(hls_vec:vector(hls_nums:s32(), 3)) -> hls_vec:vector(hls_nums:s32(), 2).
drop_head([_ | Tail]) -> Tail.
-spec prepend_zero(hls_vec:vector(hls_nums:s32(), 1)) -> hls_vec:vector(hls_nums:s32(), 2).
prepend_zero([Last]) ->
    hls_vec:set(2, hls_lists:new(hls_nums:s32(), 2), Last).
