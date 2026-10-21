-module(xls_ir_conditional_increment).

-moduledoc("Lowers wide increments by a known single bit into independently carried "
           "four-bit chunks.").

-export([write/2, rewrite/1]).

-doc("Writes fresh IR and a hash-bound audit. Matches add by literal one, "
     "zero-extended bit, or a zero-prefix concatenation. Full generated-result "
     "equality must be qualified separately.").

-spec write(file:filename(), file:filename()) -> ok.

write(Input, Output) -> xls_ir_rewrite:write(Input, Output, fun rewrite/1).

-doc("Rewrites increments wider than eight bits in a valid single-function "
     "package without assumptions about operand values, reachable states "
     "or modular overflow. Four-bit carries depend on the original operand's "
     "lower bits and the increment bit, never on another sum.").

-spec rewrite(binary()) -> {binary(), [map()]}.

rewrite(Source) ->
    {Lines, Id} = xls_ir_rewrite:prepare(Source, <<"hls_wordinc_">>),
    {match, Widths0} = re:run(Source,
                              <<"([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\]">>,
                              [global, {capture, [1, 2], binary}]),
    Widths = maps:from_list([{N, binary_to_integer(W)} || [N, W] <- Widths0]),
    Literals = xls_ir_rewrite:index(Lines,
                                    <<"^  ([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\] = literal\\(value=(0|1|0x"
                                      "0|0x1), id=">>),
    Ext = xls_ir_rewrite:index(Lines,
                               <<"^  ([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\] = zero_ext\\(([A-Za-z_][A"
                                 "-Za-z0-9_.]*), new_bit_count=[0-9]+, id=">>),
    Concat = xls_ir_rewrite:index(Lines,
                                  <<"^  ([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\] = concat\\(([A-Za-z_][A-Z"
                                    "a-z0-9_.]*), ([A-Za-z_][A-Za-z0-9_.]*), id=">>),
    Inc0 = maps:fold(fun (N, [W, V], M) ->
                             case lists:member(V, [<<"1">>, <<"0x1">>]) of
                                 true -> M#{N => {binary_to_integer(W), one}};
                                 false -> M
                             end
                     end,
                     #{},
                     Literals),
    Inc1 = maps:fold(fun (N, [W, B], M) ->
                             case maps:get(B, Widths, 0) of
                                 1 -> M#{N => {binary_to_integer(W), B}};
                                 _ -> M
                             end
                     end,
                     Inc0,
                     Ext),
    Inc = maps:fold(fun (N, [W, Z, B], M) ->
                            case {maps:get(Z, Literals, none), maps:get(B, Widths, 0)} of
                                {[ZW, V], 1} ->
                                    case binary_to_integer(ZW) + 1 =:= binary_to_integer(W) andalso
                                             lists:member(V, [<<"0">>, <<"0x0">>])
                                        of
                                        true -> M#{N => {binary_to_integer(W), B}};
                                        false -> M
                                    end;
                                _ -> M
                            end
                    end,
                    Inc1,
                    Concat),
    {Out, Changes, _} = lists:foldl(fun (L, A) -> line(L, Inc, A) end, {[], [], Id}, Lines),
    {iolist_to_binary(lists:join(<<"\n">>, lists:reverse(Out))), lists:reverse(Changes)}.

%% Retain the original add identity via a zero add, removed by the ordinary optimizer.
-spec line(binary(), map(), {list(), list(), pos_integer()}) -> {list(), list(), pos_integer()}.

line(Line, Inc, {Out, Changes, Id}) ->
    P = <<"^(  (?:ret )?)([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\] = add\\(([A-Za"
          "-z_][A-Za-z0-9_.]*), ([A-Za-z_][A-Za-z0-9_.]*), (id=.*)\\)$">>,
    case re:run(Line, P, [{capture, all_but_first, binary}]) of
        {match, [Prefix, Name, WB, A, B, Attrs]} ->
            W = binary_to_integer(WB),
            case choose(W, A, B, Inc) of
                none -> {[Line | Out], Changes, Id};
                {X, Bit0} ->
                    {Bit, Lead, I0} = case Bit0 of
                                          one -> node(1, "literal", "value=1", Id);
                                          _ -> {Bit0, [], Id}
                                      end,
                    {Chunks, Lines, I1} = chunks(0, W, X, Bit, I0, [], []),
                    {Word, WL, I2} = node(W, "concat", lists:join(", ", Chunks), I1),
                    {Zero, ZL, I3} = node(W, "literal", "value=0", I2),
                    New = [Lead,
                           Lines,
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
                     [#{node => Name, width => W, base => X, increment => Bit0, chunk_bits => 4}
                      | Changes],
                     I3}
            end;
        nomatch -> {[Line | Out], Changes, Id}
    end.

%% Addition is commutative; admit only a structurally established single-bit increment.
-spec choose(pos_integer(), binary(), binary(), map()) -> none | {binary(), binary() | one}.

choose(W, _, _, _) when W =< 8 -> none;
choose(W, A, B, M) ->
    case maps:get(B, M, none) of
        {W, Bit} -> {A, Bit};
        _ ->
            case maps:get(A, M, none) of
                {W, Bit} -> {B, Bit};
                _ -> none
            end
    end.

%% Higher chunks receive the prefix carry directly; concatenation restores high-to-low order.
-spec chunks(non_neg_integer(), pos_integer(), binary(), binary(), pos_integer(), list(),
             list()) -> {list(), iodata(), pos_integer()}.

chunks(O, W, _, _, Id, Words, Lines) when O >= W -> {Words, lists:reverse(Lines), Id};
chunks(O, W, X, Bit, Id, Words, Lines) ->
    K = min(4, W - O),
    {Part, PL, I1} = node(K,
                          "bit_slice",
                          [X, ", start=", integer_to_list(O), ", width=", integer_to_list(K)],
                          Id),
    {Carry, CL, I2} = case O of
                          0 -> {Bit, [], I1};
                          _ ->
                              {Low, LL, J1} = node(O,
                                                   "bit_slice",
                                                   [X, ", start=0, width=", integer_to_list(O)],
                                                   I1),
                              {All, AL, J2} = node(1, "and_reduce", Low, J1),
                              {C, L, J3} = node(1, "and", [Bit, ", ", All], J2),
                              {C, [LL, AL, L], J3}
                      end,
    {Wide, EL, I3} = case K of
                         1 -> {Carry, [], I2};
                         _ -> node(K, "zero_ext", [Carry, ", new_bit_count=", integer_to_list(K)], I2)
                     end,
    {Sum, SL, I4} = node(K, "add", [Part, ", ", Wide], I3),
    chunks(O + K, W, X, Bit, I4, [Sum | Words], [[PL, CL, EL, SL] | Lines]).

%% Allocate pass-specific identities above every original node id.
-spec node(pos_integer(), iodata(), iodata(), pos_integer()) -> {binary(), iodata(), pos_integer()}.

node(W, Op, Body, Id) -> xls_ir_rewrite:node(<<"hls_wordinc_">>, W, Op, Body, Id).
