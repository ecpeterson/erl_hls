-module(xls_collection_dslx).
-export([write/1]).

%% Every result comes from lowering an Erlang call; BEAM supplies its oracle.
%% Exhaust all eight-bit start/count pairs, including signed negative values.
write(Stage) ->
    ok = file:write_file(filename:join(Stage, "constant.x"), constant()),
    lists:foreach(fun({Sign, Width}) ->
        Prefix = filename:join(Stage, atom_to_list(Sign) ++ integer_to_list(Width)),
        Bounds = boundaries(Width),
        Pairs = case Width of
            8 -> [{I, C} || I <- lists:seq(0, 255), C <- lists:seq(0, 255)];
            _ -> Bounds ++ [{N * 65537, N * 31337} || N <- lists:seq(1, 256)]
        end,
        Cases = [sample(Sign, Width, I, C) || {I, C} <- Pairs],
        Small = [sample(Sign, Width, I, C) || {I, C} <- Bounds],
        Text = ["import hls_lists;\nimport hls_failure;\n",
            [function(Sign, Width, Op) || Op <- [nth, set, sublist, array_slice]],
            io_lib:format("pub fn probe(index: uN[~p], count: uN[~p], values: u24, value: u8) -> bits[88] {\n"
                " probe_nth(index, count, values, value) ++ probe_set(index, count, values, value) ++\n"
                " probe_sublist(index, count, values, value) ++ probe_array_slice(index, count, values, value)\n}\n",
                [Width, Width]),
            "#[test]\nfn beam_boundaries() {\nlet cases = [\n",
            [io_lib:format("(uN[~p]:~p, uN[~p]:~p, u24:~p, u8:~p, bits[88]:~p),\n",
                [Width, I, Width, C, V, New, Expected]) || {I, C, V, New, Expected} <- Small],
            io_lib:format(
                "];\nfor (i, ()): (u32, ()) in u32:0..u32:~p {\n"
                " let (index, count, values, value, expected) = cases[i];\n"
                " assert_eq(probe(index, count, values, value), expected);\n} (())\n}\n",
                [length(Small)])],
        ok = file:write_file(Prefix ++ ".x", Text),
        ok = file:write_file(Prefix ++ ".mem", [
            io_lib:format("~*.16.0b\n", [(2*Width+120+3) div 4,
                (I bsl (Width+120)) bor (C bsl 120) bor (V bsl 96) bor
                    (New bsl 88) bor Expected]) || {I, C, V, New, Expected} <- Cases]),
        ok = file:write_file(Prefix ++ ".count", integer_to_list(length(Cases)))
    end, [{S, W} || W <- [8, 32, 64], S <- [u, s]]).

function(Sign, Width, Op) ->
    {Expression, OutType} = operation(Op),
    {ok, Tokens, _} = erl_scan:string("probe(I, C, V, New) -> " ++ Expression ++ "."),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    Integer = [atom_to_list(Sign), "N[", integer_to_list(Width), "]"],
    #{body := Body, result := Result, failure := Failure} = xls_parse:clause_outcome(Clause,
        [["(index as ", Integer, ")"], ["(count as ", Integer, ")"],
         "(values as u8[3])", "value"], state, #{}),
    Bits = hls_type:width(OutType),
    [io_lib:format("fn probe_~s(index: uN[~p], count: uN[~p], values: u24, value: u8) -> bits[~p] {\n",
        [Op, Width, Width, Bits+4]), xls_parse:print(Body),
        "let code = ", xls_parse:print(Failure), ";\n",
        "let result = if code != hls_failure::NONE { zero!<", hls_type:print_type(OutType),
        ">() } else { ", xls_parse:print(Result), " };\n",
        "(result as bits[", integer_to_list(Bits), "]) ++ (code as u4)\n}\n"].

operation(nth) -> {"hls_vec:nth(I, V)", hls_nums:u8()};
operation(set) -> {"hls_vec:set(I, V, New)", hls_lists:list(hls_nums:u8(), 3)};
operation(sublist) -> {"hls_lists:sublist(hls_lists:list(hls_nums:u8(), 3), V, I, C)",
    hls_lists:list(hls_nums:u8(), 3)};
operation(array_slice) -> {"hls_lists:array_slice(hls_lists:list(hls_nums:u8(), 3), V, I, 2)",
    hls_lists:list(hls_nums:u8(), 2)}.

sample(Sign, Width, RawIndex, RawCount) ->
    Index = integer(Sign, Width, RawIndex), Count = integer(Sign, Width, RawCount),
    Values = [(RawIndex * 17 + RawCount + K * 73) band 255 || K <- [1, 2, 3]],
    New = (RawIndex + RawCount * 37) band 255,
    T = hls_lists:list(hls_nums:u8(), 3),
    Calls = [fun() -> hls_vec:nth(Index, Values) end,
        fun() -> hls_vec:set(Index, Values, New) end,
        fun() -> hls_lists:sublist(T, Values, Index, Count) end,
        fun() -> hls_lists:array_slice(T, Values, Index, 2) end],
    Expected = lists:foldl(fun({Op, Call}, Acc) ->
        {_, OutType} = operation(Op),
        Result = try Call() of Value -> packed(Value, OutType) bsl 4
            catch error:badarg -> 14 end,
        (Acc bsl (hls_type:width(OutType)+4)) bor Result
    end, 0, lists:zip([nth, set, sublist, array_slice], Calls)),
    {RawIndex, RawCount, packed(Values, T), New, Expected}.

packed(Value, Type) -> binary:decode_unsigned(hls_type:pack(Value, Type), little).
integer(s, Width, Value) when Value >= (1 bsl (Width-1)) -> Value - (1 bsl Width);
integer(_, _, Value) -> Value.

boundaries(Width) ->
    Mask = (1 bsl Width)-1,
    Values = lists:usort([0, 1, 2, 3, 4, 5, 7, Mask bsr 1, (Mask bsr 1)+1, Mask-1, Mask] ++
        [V || V <- [1 bsl 32, (1 bsl 32)+1, (1 bsl 32)+3], V =< Mask]),
    [{I, C} || I <- Values, C <- Values].

constant() ->
    Source = "probe(V, New) -> {hls_lists:nth(2, V), hls_lists:set(2, V, New), "
        "hls_lists:sublist(hls_lists:list(hls_nums:u32(), 3), V, 2, 1), "
        "hls_lists:array_slice(hls_lists:list(hls_nums:u32(), 3), V, 2, 2)}.",
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    #{body := Body, result := Result, failure := Failure} =
        xls_parse:clause_outcome(Clause, ["values", "replacement"], state, #{}),
    ["import hls_lists;\nimport hls_failure;\n",
        "pub fn constant_probe(values: u32[3], replacement: u32) -> ",
        "((u32, u32[3], u32[3], u32[2]), u16) {\n", xls_parse:print(Body),
        "(", xls_parse:print(Result), ", ", xls_parse:print(Failure), ")\n}\n",
        "#[test]\nfn constant_accesses() {\n",
        "assert_eq(constant_probe(u32[3]:[10, 20, 30], u32:99), ",
        "((u32:20, u32[3]:[10, 99, 30], u32[3]:[20, 0, 0], u32[2]:[20, 30]), u16:0));\n}\n"].
