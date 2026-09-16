-module(xls_shift_dslx).
-export([write/1, oracle/4]).

%% Exercise actual expression lowering with independent value/count types.
%% Small operands exhaust all pairs; wider cases stress count-width boundaries.
write(Stage) ->
    Types = [{u1, s3}, {s1, s3}, {u3, s1}, {s3, s3}, {u9, s5}, {s9, u3}] ++
        [{V, C} || V <- [u8, s8], C <- [u8, s8]] ++
        [{u16, s8}, {s16, s32}, {u32, s8}, {s32, s64},
         {u64, s16}, {s64, s64}, {s8, u64}, {u128, s8}],
    Rows = [write(Stage, V, C) || {V, C} <- Types],
    file:write_file(filename:join(Stage, "variants.txt"), Rows).

write(Stage, V, C) ->
    VT = type(V), CT = type(C),
    W = hls_type:value_width(VT), CW = hls_type:value_width(CT),
    Mask = (1 bsl W)-1,
    Inputs = lists:usort([Input band Mask || Input <- [0, 1, 2, 3, 7, Mask bsr 1,
        (1 bsl (W-1)), Mask-1, Mask]]),
    Counts = lists:usort([bits(CT, N) || N <-
        [-1024, -W-1, -W, -W+1, -1, 0, 1, W-1, W, W+1, 1024,
         -(1 bsl (CW-1)), (1 bsl (CW-1))-1, 1 bsl (CW-1),
         (1 bsl CW)-1, 1 bsl 32]]),
    Boundaries = [{A, B} || A <- Inputs, B <- Counts],
    Cases = case {W, CW} of
        _ when W =< 8, CW =< 8 -> [{A, B} || A <- lists:seq(0, Mask),
            B <- lists:seq(0, (1 bsl CW)-1)];
        _ -> Boundaries ++ [{(N * 16#9e3779b97f4a7c15) band Mask,
            bits(CT, (N rem (2*W+3))-W-1)} || N <- lists:seq(1, 128)]
    end,
    Name = atom_to_list(V) ++ "_" ++ atom_to_list(C),
    Prefix = filename:join(Stage, Name),
    Text = ["import hls_failure;\nimport hls_integer;\n",
        function(V, VT, CT, 'bsl'), function(V, VT, CT, 'bsr'),
        io_lib:format("pub fn probe(x: uN[~p], y: uN[~p]) -> bits[~p] {\n"
            "  left(x, y) ++ right(x, y)\n}\n", [W, CW, 2*W]),
        "#[test]\nfn beam_boundaries() {\nlet cases = [\n",
        [io_lib:format("(uN[~p]:~p, uN[~p]:~p, bits[~p]:~p),\n",
            [W, A, CW, B, 2*W, oracle(VT, CT, A, B)]) || {A, B} <- Boundaries],
        io_lib:format(
            "];\nfor (i, ()): (u32, ()) in u32:0..u32:~p {\n"
            " let (a, b, expected) = cases[i];\n"
            " assert_eq(probe(a, b), expected);\n} (())\n}\n", [length(Boundaries)])],
    ok = file:write_file(Prefix ++ ".x", Text),
    ok = file:write_file(Prefix ++ ".mem", [
        io_lib:format("~*.16.0b\n", [(3*W+CW+3) div 4,
            (A bsl (CW+2*W)) bor (B bsl (2*W)) bor oracle(VT, CT, A, B)])
        || {A, B} <- Cases]),
    io_lib:format("~s ~p ~p ~p\n", [Name, W, CW, length(Cases)]).

function(_Name, VT = {hls_type, hls_nums, Name, Args}, CT, Op) ->
    Constructor = atom_to_list(Name) ++ "(" ++
        lists:join(",", [integer_to_list(Arg) || Arg <- Args]) ++ ")",
    Source = lists:flatten(io_lib:format(
        "probe(X, Y) -> hls_nums:wrap(hls_nums:~s, X ~s Y).", [Constructor, Op])),
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    W = hls_type:value_width(VT), CW = hls_type:value_width(CT),
    #{body := Body, result := Result} = xls_parse:clause_outcome(
        Clause, [["(x as ", hls_type:print_type(VT), ")"],
                 ["(y as ", hls_type:print_type(CT), ")"]], state, #{}),
    Function = case Op of 'bsl' -> "left"; 'bsr' -> "right" end,
    [io_lib:format("fn ~s(x: uN[~p], y: uN[~p]) -> uN[~p] {\n", [Function, W, CW, W]),
        xls_parse:print(Body), "(", xls_parse:print(Result), ") as uN[",
        integer_to_list(W), "]\n}\n"].

oracle(VT, CT, A, B) ->
    W = hls_type:value_width(VT),
    Wire = hls_type:width(VT), CountWire = hls_type:width(CT),
    {X, <<>>} = hls_type:unpack(<<A:Wire/little>>, VT),
    {Y, <<>>} = hls_type:unpack(<<B:CountWire/little>>, CT),
    %% Mathematical fixed-width shifts saturate at |count| >= W. Restrict only
    %% enormous counts in the reference to avoid allocating a BEAM bignum with
    %% billions of bits; the exhaustive byte corpus uses the original count.
    Safe = case abs(Y) > 1024 of true -> min(W, max(-W, Y)); false -> Y end,
    (bits(VT, X bsl Safe) bsl W) bor bits(VT, X bsr Safe).

bits(T, V) -> binary:decode_unsigned(hls_type:pack(hls_nums:wrap(T, V), T), little)
    band ((1 bsl hls_type:value_width(T))-1).
type(u1) -> hls_nums:uN(1);
type(s1) -> hls_nums:sN(1);
type(u3) -> hls_nums:uN(3);
type(s3) -> hls_nums:sN(3);
type(s5) -> hls_nums:sN(5);
type(u9) -> hls_nums:uN(9);
type(s9) -> hls_nums:sN(9);
type(u128) -> hls_nums:uN(128);
type(Name) -> hls_nums:Name().
