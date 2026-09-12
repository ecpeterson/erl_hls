-module(xls_helpers_fixture).
-export([factored/3, inline/3]).
%% Intentionally exercise matching a variable exported by a branch.
-compile(nowarn_export_vars).

-hls_data(cell).
-hls_tags([report]).
-record(cell, {value :: hls_nums:u32()}).
-record(report, {value :: hls_nums:u32()}).

%% Separate BEAM oracles and separate XLS compilation inputs. All
%% intermediate integers in the generated tests stay inside their types.
%% Typed groups keep XLS from formatting a single deeply nested 30-arm
%% conditional during constant analysis; each group retains an ordered case.
factored(Mode, X, Y) ->
    if Mode < 10 -> factored_low(Mode, X, Y);
        Mode < 20 -> factored_middle(Mode, X, Y);
        true -> factored_high(Mode, X, Y)
    end.

-spec factored_low(hls_nums:u8(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
factored_low(Mode, X, Y) ->
    case Mode of
        0 -> add(add(X, Y), add(Y, X));
        1 -> equal(X, Y);
        2 -> ignored(equal(X, Y)), Y;
        3 -> equal(X, Y), Y;
        4 -> case X =:= 0 of true -> Y; false -> equal(X, Y) end;
        5 -> case (X =:= 0) orelse checked_bool(X =:= Y) of
            true -> hls_nums:wrap(hls_nums:u32(), 1);
            false -> hls_nums:wrap(hls_nums:u32(), 0)
        end;
        6 -> ignored(Bound = X), Bound + Y;
        7 -> Report = report(update(#cell{value = X}, Y)), Report#report.value;
        8 -> pair_value({X, Y});
        9 -> constant() + constant(X);
        _ -> hls_nums:wrap(hls_nums:u32(), 0)
    end.

-spec factored_middle(hls_nums:u8(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
factored_middle(Mode, X, Y) ->
    case Mode of
        10 ->
            Fixed = hls_fixed:wrap(hls_fixed:signed(32, 16), X),
            hls_type:as(hls_nums:u32(), fixed_double(Fixed));
        11 ->
            Vector = hls_lists:new(hls_nums:u16(), 2),
            Full = hls_vec:set(2, hls_vec:set(1, Vector,
                hls_nums:wrap(hls_nums:u16(), X)), hls_nums:wrap(hls_nums:u16(), Y)),
            hls_type:as(hls_nums:u32(), vector_total(Full));
        12 -> add(14, X);
        13 -> ignored_pair(X, Y);
        14 -> joined(X, Y);
        15 ->
            Result = case X < Y of
                true -> First = X + 1, Second = Y + 2, X;
                false -> Second = X + 2, First = Y + 1, Y
            end,
            First + Second + Result;
        16 ->
            case X of
                0 -> Value = Y;
                1 -> Value = Y + 1;
                Value -> Value
            end,
            Value + Y;
        17 ->
            if X < Y -> Value = X; X =:= Y -> Value = X + Y;
                true -> Value = Y end,
            Value + 1;
        18 ->
            case X < Y of
                true -> case X =:= 0 of true -> Value = Y; false -> Value = X end;
                false -> Value = X + Y
            end,
            Value;
        19 ->
            case X < Y of true -> Value = X; false -> Value = Y end,
            Value = X, Value;
        _ -> hls_nums:wrap(hls_nums:u32(), 0)
    end.

-spec factored_high(hls_nums:u8(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
factored_high(Mode, X, Y) ->
    case Mode of
        20 ->
            case X < Y of true -> X = Y; false -> Y end,
            X;
        21 ->
            case X < Y of true -> true = (X =:= 0), Value = Y; false -> Value = X end,
            Value;
        22 ->
            case Choice = (X < Y) of true -> Value = X; false -> Value = Y end,
            case Choice of true -> Value + 1; false -> Value + 2 end;
        23 ->
            Value = case X < Y of true -> Value = X; false -> Value = Y end,
            Value;
        24 ->
            case X < Y of
                true -> Pair = {X, Y}, Cell = #cell{value = X}, X;
                false -> Cell = #cell{value = Y}, Pair = {Y, X}, Y
            end,
            {First, Second} = Pair, Cell#cell.value + First + Second;
        25 ->
            case {X, Y} of
                {Value, Value} when Value < 10 -> Value;
                _ -> Value = X + Y
            end,
            Value;
        26 ->
            %% These branch-local names intentionally have different types.
            case X < Y of
                true -> Local = #cell{value = X}, Local#cell.value;
                false -> Local = Y, Local
            end;
        27 ->
            case X < Y of true -> Value = equal(X, Y); false -> Value = X end,
            Value;
        28 ->
            true = X =:= Y,
            case X =:= 0 of true -> Value = X; false -> Value = Y end,
            Value;
        29 ->
            case X < Y of true -> Value = X; false -> Value = Y end,
            case Y of Value -> X; _ -> Y end;
        _ -> hls_nums:wrap(hls_nums:u32(), 0)
    end.

inline(Mode, X, Y) ->
    if Mode < 10 -> inline_low(Mode, X, Y);
        Mode < 20 -> inline_middle(Mode, X, Y);
        true -> inline_high(Mode, X, Y)
    end.

-spec inline_low(hls_nums:u8(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
inline_low(Mode, X, Y) ->
    case Mode of
        0 -> (X + Y) + (Y + X);
        1 -> X = Y, X;
        2 -> X = Y, Y;
        3 -> X = Y, Y;
        4 -> case X =:= 0 of true -> Y; false -> X = Y, X end;
        5 -> case (X =:= 0) orelse (true = (X =:= Y)) of
            true -> hls_nums:wrap(hls_nums:u32(), 1);
            false -> hls_nums:wrap(hls_nums:u32(), 0)
        end;
        6 -> Bound = X, Bound + Y;
        7 -> Cell = #cell{value = X}, Updated = Cell#cell{value = Cell#cell.value + Y},
            Report = #report{value = Updated#cell.value}, Report#report.value;
        8 -> {First, Second} = {X, Y}, First + Second;
        9 -> hls_nums:wrap(hls_nums:u32(), 17) + X;
        _ -> hls_nums:wrap(hls_nums:u32(), 0)
    end.

-spec inline_middle(hls_nums:u8(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
inline_middle(Mode, X, Y) ->
    case Mode of
        10 ->
            Fixed = hls_fixed:wrap(hls_fixed:signed(32, 16), X),
            hls_type:as(hls_nums:u32(), Fixed + Fixed);
        11 ->
            Vector = hls_lists:new(hls_nums:u16(), 2),
            Full = hls_vec:set(2, hls_vec:set(1, Vector,
                hls_nums:wrap(hls_nums:u16(), X)), hls_nums:wrap(hls_nums:u16(), Y)),
            hls_type:as(hls_nums:u32(), hls_vec:nth(1, Full) + hls_vec:nth(2, Full));
        12 -> 14 + X;
        14 ->
            Value = case X < Y of true -> X; false -> Y end,
            Value + X;
        15 ->
            {First, Second, Result} = case X < Y of
                true -> {X + 1, Y + 2, X};
                false -> {Y + 1, X + 2, Y}
            end,
            First + Second + Result;
        16 -> (case X of 0 -> Y; 1 -> Y + 1; _ -> X end) + Y;
        17 -> (if X < Y -> X; X =:= Y -> X + Y; true -> Y end) + 1;
        18 -> case X < Y of
            true -> case X =:= 0 of true -> Y; false -> X end;
            false -> X + Y
        end;
        19 -> Value = case X < Y of true -> X; false -> Y end, Value = X, Value;
        _ -> hls_nums:wrap(hls_nums:u32(), 0)
    end.

-spec inline_high(hls_nums:u8(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
inline_high(Mode, X, Y) ->
    case Mode of
        20 -> case X < Y of true -> X = Y; false -> Y end, X;
        21 -> case X < Y of true -> true = (X =:= 0), Y; false -> X end;
        22 -> case X < Y of true -> X + 1; false -> Y + 2 end;
        23 -> case X < Y of true -> X; false -> Y end;
        24 ->
            {Pair, Cell} = case X < Y of
                true -> {{X, Y}, #cell{value = X}};
                false -> {{Y, X}, #cell{value = Y}}
            end,
            {First, Second} = Pair, Cell#cell.value + First + Second;
        25 -> case {X, Y} of {Same, Same} when Same < 10 -> Same; _ -> X + Y end;
        26 -> case X < Y of true -> X; false -> Y end;
        27 -> case X < Y of true -> X = Y, X; false -> X end;
        28 -> true = X =:= Y, case X =:= 0 of true -> X; false -> Y end;
        29 -> Value = case X < Y of true -> X; false -> Y end,
            case Y of Value -> X; _ -> Y end;
        _ -> hls_nums:wrap(hls_nums:u32(), 0)
    end.

-spec add(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
add(X, Y) -> X + Y.

-spec equal(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
equal(X, Y) -> X = Y, X.

-spec ignored(hls_nums:u32()) -> hls_nums:u32().
ignored(_) -> 0.

-spec ignored_pair(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
ignored_pair(_, _) -> 0.

-spec checked_bool(boolean()) -> boolean().
checked_bool(Value) -> true = Value, Value.

-spec update(#cell{}, hls_nums:u32()) -> #cell{}.
update(Cell, Offset) -> Cell#cell{value = Cell#cell.value + Offset}.

-spec report(#cell{}) -> #report{}.
report(Cell) -> #report{value = Cell#cell.value}.

-spec pair_value({hls_nums:u32(), hls_nums:u32()}) -> hls_nums:u32().
pair_value(Pair) -> {First, Second} = Pair, add(First, Second).

-spec constant() -> hls_nums:u32().
constant() -> 17.

-spec constant(hls_nums:u32()) -> hls_nums:u32().
constant(X) -> X.

-spec fixed_double(hls_fixed:signed(32, 16)) -> hls_fixed:signed(32, 16).
fixed_double(X) -> X + X.

-spec vector_total(hls_vec:vector(hls_nums:u16(), 2)) -> hls_nums:u16().
vector_total(Vector) -> hls_vec:nth(1, Vector) + hls_vec:nth(2, Vector).

-spec joined(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
joined(X, Y) ->
    case X < Y of true -> Value = X; false -> Value = Y end,
    Value + X.
