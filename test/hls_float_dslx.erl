-module(hls_float_dslx).
-export([write/1, cases/1, oracle/4]).

write(Stage) ->
    lists:foreach(fun(Name) ->
        Type = hls_nums:Name(),
        W = hls_type:width(Type),
        Text = ["import hls_bits;\nimport apfloat;\nimport hls_float;\nimport hls_failure;\nimport hls_lists;\n",
            [probe(Type, Op) || Op <- [add, sub, mul, eq, lt]],
            io_lib:format("pub fn probe(mode: u3, x: uN[~p], y: uN[~p]) -> (uN[~p], bool) {\n"
                " match mode { u3:0 => add(x,y), u3:1 => sub(x,y), u3:2 => mul(x,y),"
                " u3:3 => eq(x,y), _ => lt(x,y) }\n}\n", [W, W, W]),
            [checks(Type, Op) || Op <- [add, sub, mul, eq, lt]], collections(Type)],
        ok = file:write_file(filename:join(Stage, atom_to_list(Name) ++ ".x"), Text),
        Vectors = [begin
            {Bits, Failed} = oracle(Type, Op, A, B),
            io_lib:format("check(3'd~p, ~p'h~.16b, ~p'h~.16b, ~p'h~.16b, 1'b~p);\n",
                [Index - 1, W, A, W, B, W, Bits, case Failed of true -> 1; false -> 0 end])
         end || {Index, Op} <- lists:enumerate([add, sub, mul, eq, lt]), {A, B} <- cases(Type)],
        ok = file:write_file(filename:join(Stage, atom_to_list(Name) ++ ".svh"), Vectors),
        write_actor(Stage, Name, Type)
    end, [float16, float32, float64]),
    lists:foreach(fun({Name, ArgumentType, Expression}) ->
        {ok, Tokens, _} = erl_scan:string("probe(X, Y) -> " ++ Expression ++ "."),
        {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
        #{body := Body, result := Result} =
            xls_parse:clause_outcome(Clause, ["x", "y"], state, #{}),
        ok = file:write_file(filename:join(Stage, Name ++ ".x"),
            ["import hls_bits;\nimport apfloat;\nimport hls_float;\nimport hls_failure;\n",
                "pub fn probe(x: ", hls_type:print_type(ArgumentType), ", y: ",
                hls_type:print_type(ArgumentType), ") -> ",
                hls_type:print_type(hls_nums:float16()), " {\n",
                xls_parse:print([Body, Result]), "\n}\n"])
    end, [{"integer_operator", hls_nums:float16(), "X + Y"},
        {"wrong_precision", hls_nums:float32(), "hls_float:add(hls_nums:float16(), X, Y)"},
        {"integer_operand", hls_nums:u16(), "hls_float:add(hls_nums:float16(), X, Y)"}]).

probe(Type = {hls_type, _, Name, []}, Op) ->
    Source = lists:flatten(io_lib:format(
        "probe(X, Y) -> hls_float:~s(hls_nums:~s(), X, Y).", [Op, Name])),
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    W = hls_type:width(Type),
    #{body := Body, result := Result, failure := Failure} =
        xls_parse:clause_outcome(Clause,
            [hls_type:dslx_from_bits(Type, "x"), hls_type:dslx_from_bits(Type, "y")], state, #{}),
    Encoded = case Op of
        eq -> ["(", Result, ") as uN[", integer_to_list(W), "]"];
        lt -> ["(", Result, ") as uN[", integer_to_list(W), "]"];
        _ -> hls_type:dslx_to_bits(Type, Result)
    end,
    ["pub fn ", atom_to_list(Op), "(x: uN[", integer_to_list(W), "], y: uN[",
        integer_to_list(W), "]) -> (uN[", integer_to_list(W), "], bool) {\n",
        xls_parse:print(Body), "let failed = ", xls_parse:print(Failure),
        " != hls_failure::NONE;\n(if failed { uN[", integer_to_list(W),
        "]:0 } else { ", xls_parse:print(Encoded), " }, failed)\n}\n"].

checks(Type, Op) ->
    W = hls_type:width(Type),
    %% Keep interpreted/JIT tests small. The full corpus is replayed through
    %% optimized generated RTL without building a giant DSLX constant array.
    All = cases(Type),
    Cases = [lists:nth(N, All) || N <- [1, 35, 86, 146, 175, 232, 261, 300,
        337, 348, 379, 405, 492, 550, 624, 700, 810, 849, 938, 1023]] ++ ties(Type),
    ["#[test]\nfn check_", atom_to_list(Op), "() {\nlet cases = [\n",
        [begin
            {Bits, Failed} = oracle(Type, Op, A, B),
            io_lib:format("(uN[~p]:~p, uN[~p]:~p, (uN[~p]:~p, ~s)),\n",
                [W, A, W, B, W, Bits, Failed])
         end || {A, B} <- Cases],
        io_lib:format(" ];\nfor (i, ()): (u32, ()) in u32:0..u32:~p {\n"
            " let (x, y, expected) = cases[i];\n assert_eq(~s(x, y), expected);\n } (())\n}\n",
            [length(Cases), Op])].

oracle(Type, Op, A, B) ->
    W = hls_type:width(Type),
    try
        {X, <<>>} = hls_type:unpack(<<A:W/little>>, Type),
        {Y, <<>>} = hls_type:unpack(<<B:W/little>>, Type),
        case hls_float:Op(Type, X, Y) of
            true -> {1, false};
            false -> {0, false};
            V -> <<Bits:W/little>> = hls_type:pack(V, Type), {Bits, false}
        end
    catch error:badarith -> {0, true}; error:function_clause -> {0, true}
    end.

cases(Type) ->
    {E, F} = hls_float:format(Type),
    Bias = (1 bsl (E - 1)) - 1,
    One = Bias bsl F,
    Inf = ((1 bsl E) - 1) bsl F,
    Sign = 1 bsl (E + F),
    Positive = [0, 1, (1 bsl F) - 1, 1 bsl F, (1 bsl F) + 1,
        One - 1, One, One + 1, One + 2, One + (1 bsl (F - 1)),
        One + (1 bsl F), Inf - 1, Inf, Inf + 1],
    Values = Positive ++ [V bor Sign || V <- Positive],
    Mask = (Sign bsl 1) - 1,
    [{A, B} || A <- Values, B <- Values] ++ ties(Type) ++
        [{(N * 16#9e3779b97f4a7c15) band Mask,
          (N * 16#d1342543de82ef95 + 7) band Mask} || N <- lists:seq(1, 256)].

ties(Type) ->
    {E, F} = hls_float:format(Type),
    Bias = (1 bsl (E - 1)) - 1,
    One = Bias bsl F,
    HalfUlp = (Bias - F - 1) bsl F,
    Sign = 1 bsl (E + F),
    [{A bor S, B bor S} || S <- [0, Sign],
        A <- [One, One + 1, One + (1 bsl F) - 1],
        B <- [HalfUlp - 1, HalfUlp, HalfUlp + 1]].

collections(Type = {hls_type, _, Name, []}) ->
    ListType = hls_lists:list(Type, 3),
    W = hls_type:width(Type),
    Source = lists:flatten(io_lib:format("slice(Values, Start, Count) -> "
        "hls_lists:sublist(hls_lists:list(hls_nums:~s(), 3), Values, Start, Count).", [Name])),
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    #{body := Body, result := Result} = xls_parse:clause_outcome(Clause,
        [hls_type:dslx_from_bits(ListType, "raw"), "start", "count"], state, #{}),
    {Tiny, <<>>} = hls_type:unpack(<<1:W/little>>, Type),
    Values = [1.5, -Tiny, -0.0],
    Raw = binary:decode_unsigned(hls_type:pack(Values, ListType), little),
    [io_lib:format("fn slice(raw: uN[~p], start: u32, count: u32) -> uN[~p] {\n", [3*W, 3*W]),
        xls_parse:print([Body, hls_type:dslx_to_bits(ListType, Result)]), "\n}\n",
        "#[test]\nfn float_collections() {\n",
        [begin
            Expected = binary:decode_unsigned(hls_type:pack(
                hls_lists:sublist(ListType, Values, Start, Count), ListType), little),
            io_lib:format("assert_eq(slice(uN[~p]:~p, u32:~p, u32:~p), uN[~p]:~p);\n",
                [3*W, Raw, Start, Count, 3*W, Expected])
         end || {Start, Count} <- [{1, 2}, {2, 1}, {3, 1}]], "}\n"].

write_actor(Stage, Name, Type) ->
    W = hls_type:width(Type),
    Options = [{d, 'FLOAT_TYPE', Name}] ++ case W of 16 -> [{d, 'HALF'}]; _ -> [] end,
    Source = "test/hls_float_fixture.erl",
    {ok, hls_float_fixture, Binary} = compile:file(Source, [binary, return_errors] ++ Options),
    code:purge(hls_float_fixture),
    {module, hls_float_fixture} = code:load_binary(hls_float_fixture, Source, Binary),
    Initial = hls_float_fixture:init([]),
    InitialBits = binary:decode_unsigned(hls_float_fixture:pack(Initial), little),
    {E, F} = hls_float:format(Type),
    Bias = (1 bsl (E - 1)) - 1,
    One = Bias bsl F,
    Max = (((1 bsl E) - 1) bsl F) - 1,
    Sign = 1 bsl (E + F),
    Pairs = [{One, One}, {One, Sign}, {Sign, 0}, {Sign, Sign},
        {1 bsl F, 1}, {1 bsl F, (Bias - 1) bsl F},
        {One + 1, One - 1}, {Max, Max}, {Max, One + (1 bsl F)},
        {One bor Sign, One}, {Max, Max + 1}],
    Cases = [{Mode, A, B, actor_oracle(Type, Mode, A, B)}
        || Mode <- lists:seq(0, 6), {A, B} <- Pairs,
            Mode =/= 5 orelse B =/= Max + 1],
    Vectors = [io_lib:format("calculate(32'd~p, ~p'h~.16b, ~p'h~.16b, ~p'h~.16b, 1'b~p);\n",
        [Mode, W, A, W, B, W, Expected, case Failed of true -> 1; false -> 0 end])
        || {Mode, A, B, {Expected, Failed}} <- Cases],
    ok = file:write_file(filename:join(Stage, atom_to_list(Name) ++ "_actor.svh"), Vectors),
    %% Exercise the compositional codec on nested vectors with distinct signed
    %% zero/subnormal/normal values; all-zero history would miss ordering bugs.
    Decode = fun(Bits) -> {V, <<>>} = hls_type:unpack(<<Bits:W/little>>, Type), V end,
    States = [Initial, {ledger, Decode(Sign),
        [[Decode(1), Decode(One)], [Decode(Max), Decode(Sign bor 1)]]}],
    StateChecks = [begin
        Packed = binary:decode_unsigned(hls_float_fixture:pack(State), little),
        [io_lib:format("let decoded = ledger_from_bits(uN[~p]:~p);\n"
            "assert_eq(bits_from_ledger(decoded), uN[~p]:~p);\n",
            [5 * W, Packed, 5 * W, Packed]),
            [begin
                Bits = binary:decode_unsigned(hls_type:pack(Value, Type), little),
                io_lib:format("assert_eq(apfloat::flatten(decoded.history[u32:~p][u32:~p]), uN[~p]:~p);\n",
                    [I - 1, J - 1, W, Bits])
             end || {I, Row} <- lists:enumerate(Rows), {J, Value} <- lists:enumerate(Row)]]
        end || State = {ledger, _, Rows} <- States],
    Actor = xls_parse:to_xls(Source, #{source_options => Options}),
    ok = file:write_file(filename:join(Stage, atom_to_list(Name) ++ "_actor.x"),
        [Actor, "\n#[test]\nfn record_codecs() {\n", StateChecks,
            io_lib:format("assert_eq(bits_from_ledger(initial_state()), uN[~p]:~p);\n}\n",
                [5 * W, InitialBits])]).

actor_oracle(Type, Mode, A, B) ->
    W = hls_type:width(Type),
    try
        {X, <<>>} = hls_type:unpack(<<A:W/little>>, Type),
        {Y, <<>>} = hls_type:unpack(<<B:W/little>>, Type),
        Value = hls_float_fixture:compute(Mode, X, Y),
        <<Bits:W/little>> = hls_type:pack(Value, Type),
        {Bits, false}
    catch error:badarith -> {0, true}; error:function_clause -> {0, true}
    end.
