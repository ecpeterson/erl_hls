-module(xls_integer_dslx).
-export([write/1, oracle/3]).

%% Exhaust the eight-bit input space in RTL; larger widths use boundaries and
%% a deterministic spread. JIT compares a small boundary corpus at every width.
write(Stage) ->
    lists:foreach(fun(Name) ->
        Type = hls_nums:Name(),
        W = hls_type:width(Type),
        Boundaries = boundaries(W),
        Cases = case W of
            8 -> [{A, B} || A <- lists:seq(0, 255), B <- lists:seq(0, 255)];
            _ -> Boundaries ++ spread(W)
        end,
        Text = ["import hls_failure;\nimport hls_integer;\n", function(Name, Type, 'div'), function(Name, Type, 'rem'),
            io_lib:format("pub fn probe(x: uN[~p], y: uN[~p]) -> bits[~p] {\n"
                "  let (q, qfail) = quotient(x, y);\n"
                "  let (r, rfail) = remainder(x, y);\n"
                "  q ++ (qfail as u1) ++ r ++ (rfail as u1)\n}\n", [W, W, 2*W+2]),
            "#[test]\nfn beam_boundaries() {\nlet cases = [\n",
            [io_lib:format("(uN[~p]:~p, uN[~p]:~p, bits[~p]:~p),\n",
                [W, A, W, B, 2*W+2, oracle(Type, A, B)]) || {A, B} <- Boundaries],
            io_lib:format(
                "];\nfor (i, ()): (u32, ()) in u32:0..u32:~p {\n"
                " let (a, b, expected) = cases[i];\n"
                " assert_eq(probe(a, b), expected);\n} (())\n}\n", [length(Boundaries)])],
        Prefix = filename:join(Stage, atom_to_list(Name)),
        ok = file:write_file(Prefix ++ ".x", Text),
        %% Fixed-size records let Icarus read the exhaustive corpus without
        %% compiling hundreds of thousands of individual test statements.
        ok = file:write_file(Prefix ++ ".mem", [
            io_lib:format("~*.16.0b\n", [(4*W+2+3) div 4,
                (A bsl (3*W+2)) bor (B bsl (2*W+2)) bor oracle(Type, A, B)])
            || {A, B} <- Cases]),
        ok = file:write_file(Prefix ++ ".count", integer_to_list(length(Cases)))
    end, [u8, s8, u16, s16, u32, s32, u64, s64]).

function(Name, Type, Op) ->
    Source = lists:flatten(io_lib:format(
        "probe(X, Y) -> hls_nums:wrap(hls_nums:~s(), X ~s Y).", [Name, Op])),
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    W = hls_type:width(Type),
    #{body := Body, result := Result, failed := Failed} = xls_parse:clause_outcome(
        Clause, [["(x as ", hls_type:print_type(Type), ")"],
                 ["(y as ", hls_type:print_type(Type), ")"]], state, #{}),
    Function = case Op of 'div' -> "quotient"; 'rem' -> "remainder" end,
    [io_lib:format("fn ~s(x: uN[~p], y: uN[~p]) -> (uN[~p], bool) {\n", [Function, W, W, W]),
        xls_parse:print(Body), "let failed = ", xls_parse:print(Failed), ";\n",
        "((if failed { 0 } else { ", xls_parse:print(Result), " }) as uN[",
        integer_to_list(W), "], failed)\n}\n"].

oracle(Type, A, B) ->
    W = hls_type:width(Type),
    {X, <<>>} = hls_type:unpack(<<A:W/little>>, Type),
    {Y, <<>>} = hls_type:unpack(<<B:W/little>>, Type),
    try
        Q = binary:decode_unsigned(hls_type:pack(hls_nums:wrap(Type, X div Y), Type), little),
        R = binary:decode_unsigned(hls_type:pack(hls_nums:wrap(Type, X rem Y), Type), little),
        (Q bsl (W+2)) bor (R bsl 1)
    catch error:badarith -> (1 bsl (W+1)) bor 1
    end.

boundaries(W) ->
    High = 1 bsl (W-1),
    Values = lists:usort([0, 1, 2, 3, 7, High-2, High-1, High, High+1,
        2*High-3, 2*High-2, 2*High-1]),
    [{A, B} || A <- Values, B <- Values].

spread(W) ->
    Mask = (1 bsl W)-1,
    [{(N * 16#9e3779b97f4a7c15) band Mask,
      (N * 16#d1342543de82ef95 + 7) band Mask} || N <- lists:seq(1, 256)].
