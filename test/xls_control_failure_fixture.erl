-module(xls_control_failure_fixture).
-behavior(hls_gs).
-compile({parse_transform, hls_pack}).
-compile(nowarn_export_vars).
-export([init/1, handle_call/2, handle_cast/2, evaluate/3]).

-hls_data(ledger).
-hls_tags([probe, read, change, report]).
-record(ledger, {value = hls_type:zero() :: hls_nums:u32()}).
-record(probe, {mode = hls_type:zero() :: hls_nums:u32(), left = hls_type:zero() :: hls_nums:u32(), right = hls_type:zero() :: hls_nums:u32()}).
-record(read, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(change, {value = hls_type:zero() :: hls_nums:u32()}).
-record(report, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) ->
    Value = hls_nums:wrap(hls_nums:u32(), 7),
    #ledger{value = case Value of 7 -> Value end}.

handle_call(#probe{mode = Mode, left = Left, right = Right}, State) ->
    Value = evaluate(Mode, Left, Right),
    {reply, #report{value = Value}, State#ledger{value = Value}};
handle_call(#read{}, State) ->
    {reply, #report{value = State#ledger.value}, State}.

handle_cast(#change{value = Value}, State) ->
    Next = if Value =/= 0 -> Value end,
    {noreply, State#ledger{value = Next}}.

-spec evaluate(hls_nums:u32(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
evaluate(Mode, X, Y) ->
    if Mode < 8 -> first_group(Mode, X, Y);
        true -> second_group(Mode, X, Y)
    end.

-spec first_group(hls_nums:u32(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
first_group(Mode, X, Y) ->
    case Mode of
        0 -> case X of 0 -> Y; 1 -> X + Y end;
        1 -> if X < Y -> X; X =:= Y -> Y end;
        2 -> case X =:= Y of true -> X end;
        3 -> case X =:= Y of false -> Y end;
        4 -> case {X, Y} of {Same, Same} -> Same end;
        5 -> case X of Bound when Bound < Y -> Bound end;
        6 -> case X of 0 -> Value = Y; 1 -> Value = X end, Value + 1;
        7 -> if X < Y -> Value = X; X =:= Y -> Value = Y end, Value + 1
    end.

-spec second_group(hls_nums:u32(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
second_group(Mode, X, Y) ->
    case Mode of
        %% Order matters when several computations would fail.
        8 -> only_zero(X), only_if(Y);
        9 -> only_if(X), only_zero(Y);
        10 -> true = X =:= 0, only_zero(Y);
        11 -> Value = only_zero(X), true = Y =:= 0, Value;
        %% A missed final clause must beat its unselected body's badmatch.
        12 -> case X of 0 -> true = Y =:= 0, Y end;
        13 -> if X =:= 0 -> true = Y =:= 0, Y end;
        %% Boolean short-circuiting and a successful earlier arm mask failures.
        14 -> case X =:= 0 orelse (only_zero(Y) =:= 0) of
            true -> X; false -> Y end;
        15 -> case X of 0 -> Y; _ -> only_if(Y) end;
        16 -> case only_zero(X) of 1 -> only_if(Y) end;
        %% Homogeneous records and tuple results retain their normal XLS types.
        17 -> R = case #report{value = X} of #report{value = V} when V < Y -> #report{value = V} end,
            R#report.value;
        18 -> {A, B} = if X < Y -> {X, Y} end, A + B;
        %% 19 deliberately has no arm. Arguments evaluate even if ignored.
        20 -> keep(only_zero(X), only_if(Y));
        21 -> keep(only_if(X), only_zero(Y));
        22 -> keep(Y, only_zero(X));
        23 -> case X =:= 0 andalso (only_zero(Y) =:= 0) of
            true -> X; false -> Y end
    end.

-spec only_zero(hls_nums:u32()) -> hls_nums:u32().
only_zero(X) -> case X of 0 -> X end.

-spec only_if(hls_nums:u32()) -> hls_nums:u32().
only_if(X) -> if X =:= 0 -> X end.

-spec keep(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
keep(X, _Ignored) -> X.
