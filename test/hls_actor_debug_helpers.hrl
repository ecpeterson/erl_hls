%% Included helpers deliberately share the actor's line-number range.
-spec included_outer(hls_nums:u32()) -> hls_nums:u32().
included_outer(Value) -> included_inner(Value).

-spec included_inner(hls_nums:u32()) -> hls_nums:u32().
included_inner(Value) ->
    case Value of 1 -> Value end.

-spec included_if(hls_nums:u32()) -> hls_nums:u32().
included_if(Value) ->
    if Value =:= 1 -> Value end.

-spec included_div(hls_nums:u32()) -> hls_nums:u32().
included_div(Value) ->
    1 div (Value - 8).

-spec included_rem(hls_nums:u32()) -> hls_nums:u32().
included_rem(Value) ->
    Value rem (Value - 9).

-spec included_nth(hls_nums:u32()) -> hls_nums:u32().
included_nth(Index) ->
    1 + hls_vec:nth(Index, hls_lists:new(hls_nums:u32(), 3)). % Retain the BEAM caller frame.

-spec included_set(hls_nums:u32()) -> hls_nums:u32().
included_set(Index) ->
    Values = hls_vec:set(Index, hls_lists:new(hls_nums:u32(), 3), Index),
    hls_vec:nth(1, Values).

-spec included_slice(hls_nums:u32()) -> hls_nums:u32().
included_slice(Start) ->
    Values = hls_lists:array_slice(hls_lists:list(hls_nums:u32(), 3),
        hls_lists:new(hls_nums:u32(), 3), Start, 2),
    hls_vec:nth(1, Values).

-spec included_pattern(hls_nums:u32()) -> hls_nums:u32().
included_pattern(Value) ->
    [Value, _] = hls_lists:new(hls_nums:u32(), 2),
    Value.

-spec included_list_head(hls_vec:vector(hls_nums:u32(), 2)) -> hls_nums:u32().
included_list_head([1, _]) -> hls_type:as(hls_nums:u32(), 1).

-spec included_list_case(hls_nums:u32()) -> hls_nums:u32().
included_list_case(Value) ->
    Values = hls_vec:set(1, hls_lists:new(hls_nums:u32(), 2), Value),
    case Values of [0, Other] -> Other end.

-spec included_list_tail(hls_nums:u32()) -> hls_nums:u32().
included_list_tail(Value) ->
    Values = hls_vec:set(2, hls_lists:new(hls_nums:u32(), 3), Value),
    [_ | Tail] = Values,
    hls_vec:nth(1, Tail) div Value.
