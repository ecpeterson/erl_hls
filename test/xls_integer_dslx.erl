-module(xls_integer_dslx).
-moduledoc "BEAM-derived division/remainder and static-integer scalar witnesses for DSLX/JIT and RTL.".
-export([write/1, oracle/3]).

-doc "Writes exhaustive small-width division/remainder vectors, wider boundary/spread vectors, and finite static-expression probes with BEAM-derived results and failure flags.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    lists:foreach(fun({Name, Type, Constructor}) ->
        W = hls_type:value_width(Type),
        Boundaries = boundaries(W),
        Cases = case W of
            _ when W =< 8 -> [{A, B} || A <- lists:seq(0, (1 bsl W)-1),
                B <- lists:seq(0, (1 bsl W)-1)];
            _ -> Boundaries ++ spread(W)
        end,
        Text = ["import hls_failure;\nimport hls_integer;\n", function(Constructor, Type, 'div'), function(Constructor, Type, 'rem'),
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
        Prefix = filename:join(Stage, Name),
        ok = file:write_file(Prefix ++ ".x", Text),
        %% Fixed-size records let Icarus read the exhaustive corpus without
        %% compiling hundreds of thousands of individual test statements.
        ok = file:write_file(Prefix ++ ".mem", [
            io_lib:format("~*.16.0b\n", [(4*W+2+3) div 4,
                (A bsl (3*W+2)) bor (B bsl (2*W+2)) bor oracle(Type, A, B)])
            || {A, B} <- Cases]),
        ok = file:write_file(Prefix ++ ".count", integer_to_list(length(Cases)))
    end, [{Sign ++ integer_to_list(W),
        case Sign of "u" -> hls_nums:uN(W); "s" -> hls_nums:sN(W) end,
        Sign ++ "N(" ++ integer_to_list(W) ++ ")"}
        || W <- [1, 3, 8, 9, 16, 32, 64], Sign <- ["u", "s"]]),
    write_static(Stage).

%% Lowers wrapped division or remainder into a width-specific probe with an explicit failure flag.
-spec function(string(), hls_type:descriptor(), 'div' | 'rem') -> iodata().
function(Constructor, Type, Op) ->
    Source = lists:flatten(io_lib:format(
        "probe(X, Y) -> hls_nums:wrap(hls_nums:~s, X ~s Y).", [Constructor, Op])),
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    W = hls_type:value_width(Type),
    #{body := Body, result := Result, failed := Failed} = xls_clause_lower:clause_outcome(
        Clause, [["(x as ", xls_type:print_type(Type), ")"],
                 ["(y as ", xls_type:print_type(Type), ")"]], state, #{}),
    Function = case Op of 'div' -> "quotient"; 'rem' -> "remainder" end,
    [io_lib:format("fn ~s(x: uN[~p], y: uN[~p]) -> (uN[~p], bool) {\n", [Function, W, W, W]),
        xls_clause_lower:print(Body), "let failed = ", xls_clause_lower:print(Failed), ";\n",
        "((if failed { 0 } else { ", xls_clause_lower:print(Result), " }) as uN[",
        integer_to_list(W), "], failed)\n}\n"].

oracle(Type, A, B) ->
    W = hls_type:value_width(Type),
    Wire = hls_type:width(Type),
    {X, <<>>} = hls_type:unpack(<<A:Wire/little>>, Type),
    {Y, <<>>} = hls_type:unpack(<<B:Wire/little>>, Type),
    try
        Q = hls_codec:unsigned(hls_type:pack(hls_nums:wrap(Type, X div Y), Type)),
        R = hls_codec:unsigned(hls_type:pack(hls_nums:wrap(Type, X rem Y), Type)),
        ((Q band ((1 bsl W)-1)) bsl (W+2)) bor ((R band ((1 bsl W)-1)) bsl 1)
    catch error:badarith -> (1 bsl (W+1)) bor 1
    end.

boundaries(W) ->
    High = 1 bsl (W-1),
    Values = lists:usort([V || V <- [0, 1, 2, 3, 7, High-2, High-1, High, High+1,
        2*High-3, 2*High-2, 2*High-1], V >= 0, V < 2*High]),
    [{A, B} || A <- Values, B <- Values].

spread(W) ->
    Mask = (1 bsl W)-1,
    [{(N * 16#9e3779b97f4a7c15) band Mask,
      (N * 16#d1342543de82ef95 + 7) band Mask} || N <- lists:seq(1, 256)].


%% Keep static constants, guard failure and narrow wrapping in one small scalar
%% corpus; the original width/division matrix above remains independent.
-spec write_static(file:filename()) -> ok.
write_static(Stage) ->
    Expressions = static_expressions(),
    Inputs = [-(1 bsl 31), -32769, -32768, -32767, -1, 0, 1, 7, 32767, 32768,
        (1 bsl 31) - 1],
    Cases = [{Mode, X band ((1 bsl 32) - 1), static_oracle(Source, X)}
        || {Mode, {_Name, Source}} <- lists:enumerate(0, Expressions), X <- Inputs],
    Text = ["import hls_failure;\nimport hls_integer;\nimport hls_bits;\n",
        [static_function(Name, Source) || {Name, Source} <- Expressions],
        "pub fn probe(mode: u5, x: bits[32]) -> bits[33] {\n",
        [["if mode == u5:", integer_to_list(Mode), " { ", Name,
          "(x as s32) } else "]
            || {Mode, {Name, _}} <- lists:enumerate(0, Expressions)],
        "{ bits[33]:0 }\n}\n",
        "#[test]\nfn beam_static_expressions() {\nlet cases = [\n",
        [io_lib:format("(u5:~B, bits[32]:~B, bits[33]:~B),\n", [Mode, X, Expected])
            || {Mode, X, Expected} <- Cases],
        io_lib:format(
            "];\nfor (i, ()): (u32, ()) in u32:0..u32:~B {\n"
            "let (mode, x, expected) = cases[i];\n"
            "assert_eq(probe(mode, x), expected);\n} (())\n}\n", [length(Cases)])],
    Prefix = filename:join(Stage, "static_integer"),
    ok = file:write_file(Prefix ++ ".x", Text),
    ok = file:write_file(Prefix ++ ".mem", [io_lib:format("~18.16.0b\n",
        [(Mode bsl 65) bor (X bsl 33) bor Expected])
        || {Mode, X, Expected} <- Cases]),
    file:write_file(Prefix ++ ".count", integer_to_list(length(Cases))).

%% Original source expressions are evaluated by BEAM, then independently lowered.
%% Signed destinations distinguish mathematical constants from premature u16 wrap.
-spec static_expressions() -> [{string(), string()}].
static_expressions() ->
    [{"subtraction", "hls_type:as(hls_nums:s32(), 0 - (1 bsl 15))"},
     {"negation", signed_expression("-(1 bsl 15)")},
     {"complement", signed_expression("bnot ((1 bsl 15) - 1)")},
     {"nested_arithmetic", signed_expression("((3 + 5) * 7 - (11 rem 4)) div (2 + 1)")},
     {"nested_bits", signed_expression("((1 bsl 24) bsr (3 + 2)) bxor ((1 bsl 9) - 1)")},
     {"guard_threshold", "case X of V when V < -(1 bsl 15) -> " ++
        signed_expression("-1") ++ "; _ -> " ++ signed_expression("1") ++ " end"},
     {"guard_zero", "case X of V when V div (3 - 3) > 0 -> " ++
        signed_expression("77") ++ "; _ -> " ++ signed_expression("42") ++ " end"},
     {"guard_alternative", "case X of V when 1 div (3 - 3) > 0; V < 0 -> " ++
        signed_expression("-7") ++ "; _ -> " ++ signed_expression("42") ++ " end"},
     {"body_zero", signed_expression("1 div (3 - 3)")},
     {"body_dynamic_zero", signed_expression("X div (3 - 3)")},
     {"narrow_wrap", signed_expression("hls_nums:wrap(hls_nums:uN(3), X + (1 bsl 3))")},
     {"negative_shift", signed_expression("bnot (8 bsl -(1 + 1))")},
     {"negative_alias", "N = 32768, hls_type:as(hls_nums:s32(), -(N))"},
     {"exact_alias", "A = 256, B = A - 1, " ++
        "hls_type:as(hls_nums:s32(), hls_type:as(hls_nums:u8(), B))"},
     {"typed_narrow", "A = hls_type:as(hls_nums:u8(), 0), " ++
        "B = hls_type:as(hls_nums:u8(), 1), " ++
        signed_expression("hls_nums:wrap(hls_nums:u8(), A - B)")},
     {"guard_alias", "N = 1 bsl 15, case X of V when V < -N -> " ++
        signed_expression("-1") ++ "; _ -> " ++ signed_expression("1") ++ " end"},
     {"static_typed_mismatch", "A = 255, A = hls_type:as(hls_nums:s8(), -1), 7"},
     {"typed_static_mismatch", "A = hls_type:as(hls_nums:s8(), -1), A = 255, 7"},
     {"static_typed_match", "A = 255, A = hls_type:as(hls_nums:u8(), 255), 7"},
     {"case_bound_mismatch", "A = 255, case hls_type:as(hls_nums:s8(), -1) of " ++
        "A -> " ++ signed_expression("7") ++ "; _ -> " ++ signed_expression("9") ++ " end"}].

%% The source API, not a handwritten DSLX cast, establishes the signed destination.
-spec signed_expression(string()) -> string().
signed_expression(Expression) -> "hls_nums:wrap(hls_nums:s32(), " ++ Expression ++ ")".

%% Production helper preparation applies source selection, comparison facts and
%% literal typing before lowering; this fixture introduces no callable helpers.
-spec static_function(string(), string()) -> iodata().
static_function(Name, Source) ->
    {Forms, []} = xls_helpers:prepare([static_form(Text) || Text <- [
        "-module(integer_static_fixture).", "-hls_data(state).", "-hls_tags([]).",
        "-spec probe(hls_nums:s32()) -> hls_nums:s32().",
        "probe(X) -> " ++ Source ++ "."]], [{probe, 1}]),
    [Clause] = hls_source:find_function(Forms, probe, 1),
    #{body := Body, result := Result, failed := Failed} =
        xls_clause_lower:clause_outcome(Clause, ["x"], state, #{}),
    ["fn ", Name, "(x: s32) -> bits[33] {\n", xls_clause_lower:print(Body),
        "let failed = ", xls_clause_lower:print(Failed), ";\n",
        "((if failed { s32:0 } else { ", xls_clause_lower:print(Result),
        " }) as u32) ++ (failed as u1)\n}\n"].

%% BEAM evaluates the unannotated body and implements guard exception boundaries;
%% escaping arithmetic or repeated-match failures become the result failure bit.
-spec static_oracle(string(), integer()) -> non_neg_integer().
static_oracle(Source, X) ->
    {function, _, _, _, [{clause, _, _, _, Body}]} =
        static_form("probe(X) -> " ++ Source ++ "."),
    Bindings = erl_eval:add_binding('X', X, erl_eval:new_bindings()),
    try erl_eval:exprs(Body, Bindings) of
        {value, Value, _} -> (Value band ((1 bsl 32) - 1)) bsl 1
    catch
        error:badarith -> 1;
        error:{badmatch, _} -> 1
    end.

%% Parse one complete declaration while preserving real Erlang operator trees.
-spec static_form(string()) -> erl_parse:abstract_form().
static_form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.
