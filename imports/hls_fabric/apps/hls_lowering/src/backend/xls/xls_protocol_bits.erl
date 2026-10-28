-module(xls_protocol_bits).
-moduledoc "Renders checked numeric bit projections as contiguous DSLX slices and constants. Transport and inbox renderers use expressions derived by hls_protocol_projection; field meaning and canonical frame layout are not reconstructed from text.".

%% Projection expression rendering.
-export([expression/2]).

%% Chunks are accumulated high-first while reading a low-first bit plan.
-type chunk() ::
    {literal, pos_integer(), non_neg_integer()}
    | {slice, non_neg_integer(), pos_integer()}
    | {reverse, non_neg_integer(), pos_integer()}.

-doc "Renders a low-bit-first projection of a trusted DSLX value expression. Coalesces adjacent constants and contiguous payload runs in either direction; other permutations and duplicates remain explicit. Empty plans use the established one-bit zero placeholder. Does not infer known bits or change a codec.".
-spec expression(string(), [hls_protocol_projection:bit()]) -> iodata().
expression(_, []) ->
    "u1:0";
expression(Value, Bits) ->
    Chunks = lists:foldl(fun append/2, [], Bits),
    ["(", lists:join(" ++ ", [render(Value, C) || C <- Chunks]), ")"].

%% Extend only contiguous runs; a discontinuity starts a new high-order chunk.
-spec append(hls_protocol_projection:bit(), [chunk()]) -> [chunk()].
append(Bit, [{literal, Width, Value} | Rest]) when Bit =:= 0; Bit =:= 1 ->
    [{literal, Width + 1, Value bor (Bit bsl Width)} | Rest];
append({payload, Index}, [{slice, At, Width} | Rest]) when Index =:= At + Width ->
    [{slice, At, Width + 1} | Rest];
append({payload, Index}, [{slice, At, 1} | Rest]) when Index =:= At - 1 ->
    [{reverse, Index, 2} | Rest];
append({payload, Index}, [{reverse, At, Width} | Rest]) when Index =:= At - 1 ->
    [{reverse, Index, Width + 1} | Rest];
append({payload, Index}, Rest) ->
    [{slice, Index, 1} | Rest];
append(Bit, Rest) when Bit =:= 0; Bit =:= 1 -> [{literal, 1, Bit} | Rest].

%% Chunk widths remain explicit, including leading constant zeros.
-spec render(string(), chunk()) -> iodata().
render(_, {literal, Width, Value}) ->
    ["bits[", integer_to_list(Width), "]:", integer_to_list(Value)];
render(Value, {slice, At, Width}) ->
    [Value, "[", integer_to_list(At), "+:bits[", integer_to_list(Width), "]]"];
render(Value, {reverse, At, Width}) ->
    ["rev(", render(Value, {slice, At, Width}), ")"].
