-module(xls_ir_small_add).

-moduledoc("Lowers wide additions of structurally two-to-four-bit unsigned values "
           "to parallel prefix carries.").

-export([write/2, rewrite/1]).

-doc("Writes fresh transformed IR and its exact source audit. Full-result "
     "equivalence must be qualified separately.").

-spec write(file:filename(), file:filename()) -> ok.

write(Input, Output) -> xls_ir_rewrite:write(Input, Output, fun rewrite/1).

-doc("Requires a valid single-function package with no reserved hls_smalladd_ "
     "names. Rewrites additions wider than eight bits when an operand is "
     "a zero-extension or zero-prefixed concatenation of two to four bits. "
     "Preserves modular overflow for arbitrary values without reachable-state "
     "assumptions. Carries beyond the first nibble use that nibble's carry "
     "and original prefix bits, not other sums.").

-spec rewrite(binary()) -> {binary(), [map()]}.

rewrite(Source) ->
    {Lines, Id} = xls_ir_rewrite:prepare(Source, <<"hls_smalladd_">>),
    {match, Ws} = re:run(Source,
                         <<"([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\]">>,
                         [global, {capture, [1, 2], binary}]),
    Widths = maps:from_list([{N, binary_to_integer(W)} || [N, W] <- Ws]),
    Zeros = xls_ir_rewrite:index(Lines,
                                 <<"^  ([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\] = literal\\(value=(?:0|0x"
                                   "0), id=">>),
    Ext = xls_ir_rewrite:index(Lines,
                               <<"^  ([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\] = zero_ext\\(([A-Za-z_][A"
                                 "-Za-z0-9_.]*), new_bit_count=[0-9]+, id=">>),
    Concat = xls_ir_rewrite:index(Lines,
                                  <<"^  ([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\] = concat\\(([A-Za-z_][A-Z"
                                    "a-z0-9_.]*), ([A-Za-z_][A-Za-z0-9_.]*), id=">>),
    Small0 = maps:fold(fun (N, [W, B], M) ->
                               K = maps:get(B, Widths, 0),
                               case K >= 2 andalso K =< 4 of
                                   true -> M#{N => {binary_to_integer(W), B, K}};
                                   false -> M
                               end
                       end,
                       #{},
                       Ext),
    Small = maps:fold(fun (N, [W, Z, B], M) ->
                              K = maps:get(B, Widths, 0),
                              case maps:get(Z, Zeros, none) of
                                  [ZW] when K >= 2, K =< 4 ->
                                      case binary_to_integer(ZW) + K =:= binary_to_integer(W) of
                                          true -> M#{N => {binary_to_integer(W), B, K}};
                                          false -> M
                                      end;
                                  _ -> M
                              end
                      end,
                      Small0,
                      Concat),
    {Out, Changes, _} = lists:foldl(fun (L, A) -> line(L, Small, A) end, {[], [], Id}, Lines),
    {iolist_to_binary(lists:join(<<"\n">>, lists:reverse(Out))), lists:reverse(Changes)}.

%% Keep the original node identity through a zero add removed by ordinary optimization.
-spec line(binary(), map(), {list(), list(), pos_integer()}) -> {list(), list(), pos_integer()}.

line(Line, Small, {Out, Changes, Id}) ->
    Pattern = <<"^(  (?:ret )?)([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\] = add\\(([A-Za"
                "-z_][A-Za-z0-9_.]*), ([A-Za-z_][A-Za-z0-9_.]*), (id=.*)\\)$">>,
    case re:run(Line, Pattern, [{capture, all_but_first, binary}]) of
        {match, [Prefix, Name, WB, A, B, Attrs]} ->
            W = binary_to_integer(WB),
            case choose(W, A, B, Small) of
                none -> {[Line | Out], Changes, Id};
                {X, Y, K} ->
                    {Low, LL, I1} = node(4, "bit_slice", [X, ", start=0, width=4"], Id),
                    {LX, XL, I2} = node(5, "zero_ext", [Low, ", new_bit_count=5"], I1),
                    {LY, YL, I3} = node(5, "zero_ext", [Y, ", new_bit_count=5"], I2),
                    {Sum, SL, I4} = node(5, "add", [LX, ", ", LY], I3),
                    {Part, PL, I5} = node(4, "bit_slice", [Sum, ", start=0, width=4"], I4),
                    {Carry, CL, I6} = node(1, "bit_slice", [Sum, ", start=4, width=1"], I5),
                    {Words, Rest, I7} = chunks(4, W, X, Carry, I6, [Part], []),
                    {Word, WL, I8} = node(W, "concat", lists:join(", ", Words), I7),
                    {Zero, ZL, I9} = node(W, "literal", "value=0", I8),
                    New = [LL,
                           XL,
                           YL,
                           SL,
                           PL,
                           CL,
                           Rest,
                           WL,
                           ZL,
                           Prefix,
                           Name,
                           ": bits[",
                           WB,
                           "] = add(",
                           Word,
                           ", ",
                           Zero,
                           ", ",
                           Attrs,
                           ")"],
                    {[New | Out],
                     [#{node => Name, width => W, base => X, small_operand => Y, small_width => K,
                        chunk_bits => 4}
                      | Changes],
                     I9}
            end;
        nomatch -> {[Line | Out], Changes, Id}
    end.

%% Addition is commutative; structural zero extension establishes the bound.
-spec choose(pos_integer(), binary(), binary(), map()) -> none |
                                                          {binary(), binary(), pos_integer()}.

choose(W, _, _, _) when W =< 8 -> none;
choose(W, A, B, M) ->
    case maps:get(B, M, none) of
        {W, Y, K} -> {A, Y, K};
        _ ->
            case maps:get(A, M, none) of
                {W, Y, K} -> {B, Y, K};
                _ -> none
            end
    end.

%% Each higher nibble uses the first carry and an independent original-bit prefix.
-spec chunks(non_neg_integer(), pos_integer(), binary(), binary(), pos_integer(), list(),
             list()) -> {list(), iodata(), pos_integer()}.

chunks(O, W, _, _, Id, Words, Lines) when O >= W -> {Words, lists:reverse(Lines), Id};
chunks(O, W, X, First, Id, Words, Lines) ->
    K = min(4, W - O),
    {Part, PL, I1} = node(K,
                          "bit_slice",
                          [X, ", start=", integer_to_list(O), ", width=", integer_to_list(K)],
                          Id),
    {Carry, CL, I2} = case O of
                          4 -> {First, [], I1};
                          _ ->
                              {Low, LL, J1} = node(O - 4,
                                                   "bit_slice",
                                                   [X, ", start=4, width=", integer_to_list(O - 4)],
                                                   I1),
                              {All, AL, J2} = node(1, "and_reduce", Low, J1),
                              {C, L, J3} = node(1, "and", [First, ", ", All], J2),
                              {C, [LL, AL, L], J3}
                      end,
    {Wide, EL, I3} = case K of
                         1 -> {Carry, [], I2};
                         _ -> node(K, "zero_ext", [Carry, ", new_bit_count=", integer_to_list(K)], I2)
                     end,
    {Sum, SL, I4} = node(K, "add", [Part, ", ", Wide], I3),
    chunks(O + K, W, X, First, I4, [Sum | Words], [[PL, CL, EL, SL] | Lines]).

%% Allocate pass-specific identities above every original node id.
-spec node(pos_integer(), iodata(), iodata(), pos_integer()) -> {binary(), iodata(), pos_integer()}.

node(W, Op, Body, Id) -> xls_ir_rewrite:node(<<"hls_smalladd_">>, W, Op, Body, Id).
