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

-doc "Returns the fixture's declared initial callback state.".
-spec init([]) -> {'ok','boot',#cell{}}.
init([]) -> {ok, boot, #cell{}}.
-doc "Accepts configuration before entering the fixture's active phase.".
-spec boot('cast' | 'enter',term(),term()) -> {term(),[]} | {'boot',term(),'postpone'} | {'gathering',#cell{},'consume'}.
boot(enter, _, Cell) -> {Cell, []};
boot(cast, #configure{value = Mode}, Cell) ->
    {gathering, Cell#cell{mode = Mode}, consume};
boot(cast, #message{}, Cell) ->
    {boot, Cell, postpone}.

-doc "Opens the fixture reduction and accepts its declared contribution messages.".
-spec gathering('cast' | 'enter' | 'internal',term(),term()) -> {#cell{},[{'cast','left' | 'middle' | 'right',{term(),term()}} | {'open_reduction','sum',0,{term(),term()},{term(),term()}},...]} | {'done',#cell{},'consume'} | {'gathering',term(),{'contribute','sum',0,#sum{}}}.
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

-doc "Retains the completed fixture state without producing further work.".
-spec done('cast' | 'enter',term(),term()) -> {#cell{},[{'cast','out',{term(),term()}},...]} | {'done',term(),'consume'}.
done(enter, _, Cell) ->
    {Cell, [{cast, out, #report{value = Cell#cell.total}}]};
done(cast, #configure{}, Cell) -> {done, Cell, consume}.

%% Deliberately partial sum: selected inputs inject faults into a pure combiner.
-doc "Combines fixture contributions using its declared bounded arithmetic.".
-spec reduce('sum',#sum{value::number()},#sum{}) -> #sum{value::number()}.
reduce(sum, #sum{value = Left}, #sum{value = Right}) ->
    Checked = checked(Right),
    #sum{value = Left + Checked}.

%% Evaluates the fixture's checked arithmetic path.
-spec checked(hls_nums:u32()) -> hls_nums:u32().
checked(Value) ->
    case Value of
        0 -> hls_type:as(hls_nums:u32(), 1) div Value;
        2 -> case Value of 1 -> Value end;
        3 -> true = Value =:= 1, Value;
        4 -> only_one(Value);
        _ -> Value
    end.

%% Matches the accepted sentinel and rejects the negative witness.
-spec only_one(hls_nums:u32()) -> hls_nums:u32().
only_one(Value) -> if Value =:= 1 -> Value end.
