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

handle_call(#probe{mode = 42, left = X, right = Y}, State)
        when X div Y > 0; X rem Y =:= 0 ->
    {reply, #report{value = 101}, State#ledger{value = 101}};
handle_call(#probe{mode = 42}, State) ->
    {reply, #report{value = 202}, State#ledger{value = 202}};
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
        Mode < 25 -> second_group(Mode, X, Y);
        Mode < 47 -> arithmetic_group(Mode, X, Y);
        true -> collection_group(Mode, X, Y)
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

%% Divisor failure follows expression selection, and each guard sequence has
%% its own exception boundary. These run through both helpers and the service.
-spec arithmetic_group(hls_nums:u32(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
arithmetic_group(Mode, X, Y) ->
    if Mode < 32 -> arithmetic_first(Mode, X, Y);
       Mode < 39 -> arithmetic_second(Mode, X, Y);
       true -> arithmetic_third(Mode, X, Y)
    end.

-spec arithmetic_first(hls_nums:u32(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
arithmetic_first(Mode, X, Y) ->
    case Mode of
        25 -> X div Y;
        26 -> X rem Y;
        27 -> case Y of 0 -> X; _ -> X div Y end;
        28 -> case Y =/= 0 andalso X div Y > 0 of true -> X; false -> Y end;
        29 -> case Y =:= 0 orelse X rem Y =:= 0 of true -> X; false -> Y end;
        30 -> if X div Y > 0 -> X; true -> Y end;
        31 -> if X rem Y =:= 0 -> X; true -> Y end
    end.

-spec arithmetic_second(hls_nums:u32(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
arithmetic_second(Mode, X, Y) ->
    case Mode of
        32 -> if (X div Y > 0) orelse true -> X; true -> Y end;
        33 -> if X div Y > 0; Y =:= 0 -> X; true -> Y end;
        34 -> if X div Y >= 0, X rem Y =:= 0 -> X; true -> Y end;
        35 -> if X div Y > 0 -> X end;
        36 -> true = X =:= 0, X div Y;
        37 -> V = X div Y, true = X =:= 0, V;
        38 -> X div (Y div X)
    end.

-spec arithmetic_third(hls_nums:u32(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
arithmetic_third(Mode, X, Y) ->
    case Mode of
        39 -> X rem 0;
        40 -> X div 2;
        41 -> case X of V when V div Y > 0; V rem Y =:= 0 -> X; _ -> Y end;
        42 -> if X div Y > 0; X rem Y =:= 0 -> hls_type:as(hls_nums:u32(), 101); true -> hls_type:as(hls_nums:u32(), 202) end;
        %% A guard must not erase a failure from an earlier body expression.
        43 -> V = X div Y, if X rem Y =:= 0 -> V; true -> X end;
        44 -> if true orelse X div Y > 0 -> X; true -> Y end;
        45 -> if false andalso X div Y > 0 -> X; true -> Y end;
        46 -> case (X div Y > 0) orelse true of true -> X; false -> Y end
    end.

-spec collection_group(hls_nums:u32(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
collection_group(Mode, X, Y) ->
    if Mode < 53 -> collection_values(Mode, X, Y);
       true -> collection_failures(Mode, X, Y)
    end.

-spec collection_values(hls_nums:u32(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
collection_values(Mode, X, Y) ->
    Values = hls_lists:set(2, hls_lists:new(hls_nums:u32(), 3), Y),
    case Mode of
        47 -> hls_vec:nth(X, Values);
        48 -> hls_vec:nth(2, hls_vec:set(X, Values, X));
        49 -> hls_lists:nth(1, hls_lists:sublist(hls_lists:list(hls_nums:u32(), 3), Values, X, Y));
        50 -> hls_lists:nth(1, hls_lists:array_slice(hls_lists:list(hls_nums:u32(), 3), Values, X, 2));
        51 -> case X of 0 -> Y; _ -> hls_vec:nth(X, Values) end;
        52 -> case X =:= 0 orelse hls_vec:nth(X, Values) =:= Y of true -> X; false -> Y end
    end.

-spec collection_failures(hls_nums:u32(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
collection_failures(Mode, X, Y) ->
    Values = hls_lists:new(hls_nums:u32(), 3),
    case Mode of
        53 -> V = hls_lists:nth(X, Values), true = Y =:= 0, V;
        54 -> true = Y =:= 0, hls_lists:nth(X, Values);
        55 -> keep(hls_lists:nth(X, Values), X div Y);
        56 -> hls_lists:nth(4, Values);
        57 -> hls_vec:nth(16#100000001, Values);
        58 -> hls_vec:nth(-1, Values)
    end.
