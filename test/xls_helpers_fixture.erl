-module(xls_helpers_fixture).
-export([factored/3, inline/3]).

-hls_data(cell).
-hls_tags([report]).
-record(cell, {value :: hls_nums:u32()}).
-record(report, {value :: hls_nums:u32()}).

%% Separate BEAM oracles and separate XLS compilation inputs. All
%% intermediate integers in the generated tests stay inside their types.
factored(Mode, X, Y) ->
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
        _ -> hls_nums:wrap(hls_nums:u32(), 0)
    end.

inline(Mode, X, Y) ->
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
        10 ->
            Fixed = hls_fixed:wrap(hls_fixed:signed(32, 16), X),
            hls_type:as(hls_nums:u32(), Fixed + Fixed);
        11 ->
            Vector = hls_lists:new(hls_nums:u16(), 2),
            Full = hls_vec:set(2, hls_vec:set(1, Vector,
                hls_nums:wrap(hls_nums:u16(), X)), hls_nums:wrap(hls_nums:u16(), Y)),
            hls_type:as(hls_nums:u32(), hls_vec:nth(1, Full) + hls_vec:nth(2, Full));
        12 -> 14 + X;
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
