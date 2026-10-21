-module(xls_ir_increment_compare).

-moduledoc("Splits wide modular increment comparisons into independent small "
           "comparisons with prefix carry predicates.").

-export([write/2, rewrite/1]).

-doc("Writes fresh transformed IR and a hash-bound change audit. Recognizes "
     "equality/inequality against a same-width add of one; other uses and "
     "nodes remain unchanged. The audit is structural evidence, not semantic "
     "qualification.").

-spec write(file:filename(), file:filename()) -> ok.

write(Input, Output) -> xls_ir_rewrite:write(Input, Output, fun rewrite/1).

-doc("Rewrites wide eq/ne(x,y+1) using four-bit sums and parallel carry "
     "predicates from y's lower bits. Equality operands and addition operands "
     "may be reversed. Requires one optimized function and no reserved "
     "hls_inc_ names. No range, actor or reachable-state assumptions are "
     "used.").

-spec rewrite(binary()) -> {binary(), [map()]}.

rewrite(Source) ->
    {Lines, Id} = xls_ir_rewrite:prepare(Source, <<"hls_inc_">>),
    Ones = xls_ir_rewrite:index(Lines,
                                <<"^  ([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\] = literal\\(value=(?:1|0x"
                                  "1), id=">>),
    Adds = xls_ir_rewrite:index(Lines,
                                <<"^  ([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\] = add\\(([A-Za-z_][A-Za-z"
                                  "0-9_.]*), ([A-Za-z_][A-Za-z0-9_.]*), id=">>),
    {Output, Changes, _} = lists:foldl(fun (L, A) -> line(L, Ones, Adds, A) end, {[], [], Id}, Lines),
    {iolist_to_binary(lists:join(<<"\n">>, lists:reverse(Output))), lists:reverse(Changes)}.

%% Preserve the original comparison identity and source locations after its replacement inputs.
-spec line(binary(), map(), map(), {list(), list(), pos_integer()}) -> {list(),
                                                                        list(),
                                                                        pos_integer()}.

line(Line, Ones, Adds, {Output, Changes, Id}) ->
    Pattern = <<"^(  (?:ret )?)([A-Za-z_][A-Za-z0-9_.]*): bits\\[1\\] = (eq|ne)\\(([A-Za-z_"
                "][A-Za-z0-9_.]*), ([A-Za-z_][A-Za-z0-9_.]*), (id=.*)\\)$">>,
    case re:run(Line, Pattern, [{capture, all_but_first, binary}]) of
        {match, [Prefix, Name, Op, A, B, Attrs]} ->
            case candidate(A, B, Ones, Adds) of
                none -> {[Line | Output], Changes, Id};
                {Width, X, Y} ->
                    {Prelude, Equal, Next} = chunks(0, Width, X, Y, Id, [], []),
                    {All, AL, N1} = node(1, "and", lists:join(", ", Equal), Next),
                    {One, OL, N2} = node(1, "literal", "value=1", N1),
                    New = [Prelude,
                           AL,
                           OL,
                           Prefix,
                           Name,
                           ": bits[1] = ",
                           Op,
                           "(",
                           All,
                           ", ",
                           One,
                           ", ",
                           Attrs,
                           ")"],
                    {[New | Output],
                     [#{comparison => Name, width => Width, left => X, incremented => Y, chunk_bits => 4}
                      | Changes],
                     N2}
            end;
        nomatch -> {[Line | Output], Changes, Id}
    end.

%% Equality is symmetric while incrementing is tied to its literal-one operand.
-spec candidate(binary(), binary(), map(), map()) -> none | {pos_integer(), binary(), binary()}.

candidate(A, B, Ones, Adds) ->
    case increment(B, Ones, Adds) of
        none ->
            case increment(A, Ones, Adds) of
                none -> none;
                {W, Y} -> {W, B, Y}
            end;
        {W, Y} -> {W, A, Y}
    end.

%% Restrict rewriting to widths where a full carry chain crosses multiple chunks.
-spec increment(binary(), map(), map()) -> none | {pos_integer(), binary()}.

increment(N, Ones, Adds) ->
    case maps:find(N, Adds) of
        {ok, [WB, A, B]} ->
            W = binary_to_integer(WB),
            case W > 8 of
                false -> none;
                true ->
                    case {maps:get(A, Ones, none), maps:get(B, Ones, none)} of
                        {[WB], _} -> {W, B};
                        {_, [WB]} -> {W, A};
                        _ -> none
                    end
            end;
        error -> none
    end.

%% Carries depend only on lower input bits; they never ripple through a preceding sum.
-spec chunks(non_neg_integer(), pos_integer(), binary(), binary(), pos_integer(), list(),
             list()) -> {iodata(), [binary()], pos_integer()}.

chunks(Offset, Width, _, _, Id, Lines, Equal) when Offset >= Width ->
    {lists:reverse(Lines), lists:reverse(Equal), Id};
chunks(Offset, Width, X, Y, Id, Lines, Equal) ->
    K = min(4, Width - Offset),
    {SX, LX, I1} = node(K,
                        "bit_slice",
                        [X, ", start=", integer_to_list(Offset), ", width=", integer_to_list(K)],
                        Id),
    {SY, LY, I2} = node(K,
                        "bit_slice",
                        [Y, ", start=", integer_to_list(Offset), ", width=", integer_to_list(K)],
                        I1),
    {Carry, CL, I3} = case Offset of
                          0 -> node(1, "literal", "value=1", I2);
                          _ ->
                              {Low, LL, II} = node(Offset,
                                                   "bit_slice",
                                                   [Y, ", start=0, width=", integer_to_list(Offset)],
                                                   I2),
                              {CC, LC, IN} = node(1, "and_reduce", Low, II),
                              {CC, [LL, LC], IN}
                      end,
    {Wide, WL, I4} = case K of
                         1 -> {Carry, [], I3};
                         _ -> node(K, "zero_ext", [Carry, ", new_bit_count=", integer_to_list(K)], I3)
                     end,
    {Sum, SL, I5} = node(K, "add", [SY, ", ", Wide], I4),
    {Eq, EL, I6} = node(1, "eq", [SX, ", ", Sum], I5),
    chunks(Offset + K, Width, X, Y, I6, [[LX, LY, CL, WL, SL, EL] | Lines], [Eq | Equal]).

%% Allocate pass-specific identities above every original node id.
-spec node(pos_integer(), iodata(), iodata(), pos_integer()) -> {binary(), iodata(), pos_integer()}.

node(W, Op, Body, Id) -> xls_ir_rewrite:node(<<"hls_inc_">>, W, Op, Body, Id).
