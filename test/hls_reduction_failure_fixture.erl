-module(hls_reduction_failure_fixture).
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, boot/3, gathering/3, done/3, reduce/3]).
-hls_data(cell).
-hls_phases([boot, gathering, done]).
-hls_outputs([left, middle, right, out]).
-hls_mailbox_capacity(4).
-hls_tags([configure, message, report]).
-record(cell, {mode = hls_type:zero() :: hls_nums:u32(), total = hls_type:zero() :: hls_nums:u32()}).
-record(configure, {value = hls_type:zero() :: hls_nums:u32()}).
-record(message, {value = hls_type:zero() :: hls_nums:u32()}).
-record(report, {value = hls_type:zero() :: hls_nums:u32()}).
-record(sum, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, boot, #cell{}}.
boot(enter, _, Cell) -> {Cell, []};
boot(cast, #configure{value = Mode}, Cell) ->
    {gathering, Cell#cell{mode = Mode}, consume}.

gathering(enter, _, Cell) ->
    {Cell, [
        {open_reduction, sum, 0, {count, 3}, {commutative_monoid, #sum{value = 0}}},
        {cast, left, #message{value = 1}},
        {cast, middle, #message{value = Cell#cell.mode}},
        {cast, right, #message{value = 1}}
    ]};
gathering(cast, #message{value = Value}, Cell) ->
    {gathering, Cell, {contribute, sum, 0, #sum{value = Value}}};
gathering(internal, {reduction_complete, sum, 0, #sum{value = Total}}, Cell) ->
    {done, Cell#cell{total = Total}, consume}.

done(enter, _, Cell) ->
    {Cell, [{cast, out, #report{value = Cell#cell.total}}]};
done(cast, #configure{}, Cell) -> {done, Cell, consume}.

%% Deliberately partial sum: selected inputs inject faults into a pure combiner.
reduce(sum, #sum{value = Left}, #sum{value = Right}) ->
    Checked = checked(Right),
    #sum{value = Left + Checked}.

-spec checked(hls_nums:u32()) -> hls_nums:u32().
checked(Value) ->
    case Value of
        0 -> hls_type:as(hls_nums:u32(), 1) div Value;
        2 -> case Value of 1 -> Value end;
        3 -> true = Value =:= 1, Value;
        4 -> only_one(Value);
        _ -> Value
    end.

-spec only_one(hls_nums:u32()) -> hls_nums:u32().
only_one(Value) -> if Value =:= 1 -> Value end.
