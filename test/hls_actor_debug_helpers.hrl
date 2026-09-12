%% Included helpers deliberately share the actor's line-number range.
-spec included_outer(hls_nums:u32()) -> hls_nums:u32().
included_outer(Value) -> included_inner(Value).

-spec included_inner(hls_nums:u32()) -> hls_nums:u32().
included_inner(Value) ->
    case Value of 1 -> Value end.

-spec included_if(hls_nums:u32()) -> hls_nums:u32().
included_if(Value) ->
    if Value =:= 1 -> Value end.
