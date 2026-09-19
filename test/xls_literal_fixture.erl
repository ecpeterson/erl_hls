-module(xls_literal_fixture).
-moduledoc false.
-export([run/2]).
-compile(nowarn_export_vars).
-hls_data(cell).
-hls_tags([report]).
-compile({parse_transform, hls_pack}).

%% Mixed field types exercise logical widths independently of packed widths.
-record(cell, {
    value = hls_type:zero() :: hls_nums:u32(),
    sample = hls_type:zero() :: hls_nums:u8(),
    signed = hls_type:zero() :: hls_nums:sN(5),
    padded = hls_type:zero() :: hls_bits:padded(hls_nums:uN(3), 32)
}).
%% Message constructors retain their tag and packed payload representation.
-record(report, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Exercises signature- and field-directed literals and selected failures without explicit literal casts.".
-spec run(hls_nums:u8(), hls_nums:u8()) -> hls_nums:s32().
run(Mode, X) ->
    case Mode < 17 of true -> select(Mode, X); false -> records(Mode, X) end.

%% Keep ordinary BEAM integers as the oracle for these bounded expressions.
-spec select(hls_nums:u8(), hls_nums:u8()) -> hls_nums:s32().
select(Mode, X) ->
    case Mode of
        0 -> tuple_value({X =:= 0, 0, -1});
        1 -> signed(case X =:= 0 of true -> 0; false -> -7 end);
        2 -> Pair = pair(X =:= 0), tuple_value(Pair);
        3 -> Pair = {X =:= 0, 65, -16}, tuple_value(Pair);
        4 ->
            case X =:= 0 of true -> Value = -3, 0; false -> Value = 127, 0 end,
            signed(Value);
        5 -> signed(if X < 2 -> -1; X < 8 -> 2; true -> 17 end);
        6 ->
            signed(Value = case X =:= 0 of true -> 11; false -> 12 end),
            Value;
        7 -> signed(case X =:= 0 of true -> true = (X =:= 1), -1; false -> 5 end);
        8 -> signed(1) + signed(1 + 2) + signed(1 bsl 4);
        9 -> hls_type:as(hls_nums:s32(), narrow(X =:= 0));
        10 -> tuple_value({X =:= 0, $A, +3});
        11 -> matched(X);
        12 -> nested({0, {false, -9}});
        13 ->
            {Flag, Count, Value} = {true, 15, -4},
            tuple_value({Flag, Count, Value});
        14 -> signed(begin Value = -32, Value end);
        15 ->
            case X =:= 0 of
                true -> Local = 1, byte_value(Local);
                false -> Local = 300, wide_value(Local)
            end;
        _ -> -99
    end.

%% Keep record witnesses separate so XLS need not infer one huge conditional.
-spec records(hls_nums:u8(), hls_nums:u8()) -> hls_nums:s32().
records(Mode, X) ->
    case Mode of
        17 ->
            {Sample, Hit} = case X =:= 0 of true -> {X, 0}; false -> {X, 7} end,
            Cell = #cell{value = Hit, sample = Sample},
            hls_type:as(hls_nums:s32(), Cell#cell.value);
        18 ->
            {_, Hit} = case X =:= 0 of true -> {X, 0}; false -> {X, 7} end,
            Cell = #cell{value = Hit},
            hls_type:as(hls_nums:s32(), Cell#cell.value);
        19 ->
            Cell = update(#cell{value = 100}, X =:= 0),
            hls_type:as(hls_nums:s32(), Cell#cell.value);
        20 ->
            Cell = #cell{signed = if X < 8 -> -16; true -> 15 end},
            hls_type:as(hls_nums:s32(), Cell#cell.signed);
        21 ->
            Cell = #cell{padded = case X =:= 0 of true -> 0; false -> 7 end},
            hls_type:as(hls_nums:s32(), Cell#cell.padded);
        22 ->
            Message = #report{value = case X =:= 0 of true -> 0; false -> $A end},
            #report{value = Value} = Message,
            hls_type:as(hls_nums:s32(), Value);
        23 ->
            Cell = #cell{value = hls_type:as(hls_nums:u32(), X)},
            case Cell of #cell{value = 0} -> -1; #cell{value = Value} -> hls_type:as(hls_nums:s32(), Value) end;
        24 ->
            case X =:= 0 of true -> Hit = 7, X; false -> Hit = 0, X end,
            Cell = #cell{value = Hit},
            hls_type:as(hls_nums:s32(), Cell#cell.value);
        25 ->
            Cell = #cell{value = case X =:= 0 of
                true -> true = (X =:= 1), 0; false -> 7 end},
            hls_type:as(hls_nums:s32(), Cell#cell.value);
        26 ->
            #cell{value = Value} = #cell{value = 7},
            hls_type:as(hls_nums:s32(), Value);
        27 ->
            Pair = case X =:= 0 of true -> {0, 0}; false -> {7, 15} end,
            {Wide, _} = Pair,
            {_, Small} = Pair,
            Cell = #cell{value = Wide, sample = Small},
            hls_type:as(hls_nums:s32(), Cell#cell.value) +
                hls_type:as(hls_nums:s32(), Cell#cell.sample)
    end.

%% A mixed signed/unsigned tuple exercises literal widths in nested branches.
-spec pair(boolean()) -> {boolean(), hls_nums:u16(), hls_nums:s32()}.
pair(Flag) ->
    case Flag of true -> {true, 1, -1}; false -> {false, 65535, 2} end.

%% The conversion of an already typed value remains explicit.
-spec tuple_value({boolean(), hls_nums:u16(), hls_nums:s32()}) -> hls_nums:s32().
tuple_value({Flag, Count, Value}) ->
    case Flag of true -> Value; false -> hls_type:as(hls_nums:s32(), Count) + Value end.

%% Identity exposes the declared argument context at the call site.
-spec signed(hls_nums:s32()) -> hls_nums:s32().
signed(Value) -> Value.

%% Signed bounds at a non-byte width must not inherit a default machine width.
-spec narrow(boolean()) -> hls_nums:sN(5).
narrow(true) -> -16;
narrow(false) -> 15.

%% A non-total helper retains function-clause failure, including its guard.
-spec matched(hls_nums:u8()) -> hls_nums:s32().
matched(0) -> -1;
matched(X) when X < 8 -> 2.

%% Nested tuple arguments retain each field's independent type.
-spec nested({hls_nums:u32(), {boolean(), hls_nums:s32()}}) -> hls_nums:s32().
nested({_, {_, Value}}) -> Value.

%% Equal result types do not force unused branch-local inputs to agree.
-spec byte_value(hls_nums:u8()) -> hls_nums:s32().
byte_value(Value) -> hls_type:as(hls_nums:s32(), Value).

%% Widening/narrowing an existing value is still an explicit operation.
-spec wide_value(hls_nums:u32()) -> hls_nums:s32().
wide_value(Value) -> hls_type:as(hls_nums:s32(), Value).

%% A record update supplies context through a bound, nested branch result.
-spec update(#cell{}, boolean()) -> #cell{}.
update(Cell, Flag) ->
    Value = case Flag of true -> 3 + 4; false -> 0 end,
    Cell#cell{value = Value}.
