-module(xls_dslx_tests).
-moduledoc "Syntax rendering regressions; semantic entry behavior is covered by the existing finite BEAM/DSLX witnesses.".
-include_lib("eunit/include/eunit.hrl").

%% Postfix operators retain their receiver and bit offsets without reparsing leaves.
-spec access_and_cast_test() -> ok.
access_and_cast_test() ->
    Frame = xls_dslx:field(xls_dslx:ref(<<"input">>), "frame"),
    Bits = xls_dslx:slice(xls_dslx:cast(Frame, {bits, 128}), 8, 16),
    ?assertEqual(<<"(input.frame as bits[128])[8:24]">>, text(Bits)),
    Item = xls_dslx:field(xls_dslx:index(xls_dslx:ref("items"),
        xls_dslx:literal("u32", 2)), 1),
    ?assertEqual(<<"items[u32:2].1">>, text(Item)),
    ?assertEqual(<<"(u8:3,)">>, text(xls_dslx:tuple([xls_dslx:literal("u8", 3)]))).

%% Grouping preserves precedence and all argument/field order, including struct spreads.
-spec expression_order_test() -> ok.
expression_order_test() ->
    Sum = xls_dslx:binary('+', xls_dslx:ref("a"), xls_dslx:ref("b")),
    ?assertEqual(<<"((a + b) * c)">>, text(xls_dslx:binary('*', Sum, xls_dslx:ref("c")))),
    Choice = xls_dslx:binary('&&', xls_dslx:ref("ready"),
        xls_dslx:unary('!', xls_dslx:ref("failed"))),
    Pair = xls_dslx:binary('++', xls_dslx:literal("u8", 3), xls_dslx:literal("u8", 4)),
    Value = xls_dslx:construct("Result", [
        {"sum", xls_dslx:call("sum", [Sum, "c"])},
        {"ready", Choice}, {"pair", Pair}], xls_dslx:ref("previous")),
    ?assertEqual(<<"Result {\n"
        "  sum: sum((a + b), c),\n"
        "  ready: (ready && !(failed)),\n"
        "  pair: (u8:3 ++ u8:4),\n"
        "  ..previous\n"
        "}">>, text(Value)).

%% Branch-local bindings stay inside their selected branch, before its tuple result.
-spec scoped_selection_test() -> ok.
scoped_selection_test() ->
    Selected = xls_dslx:block([xls_dslx:bind("next", xls_dslx:call("step", ["old"]))],
        xls_dslx:tuple([xls_dslx:ref("next"), "false"])),
    Other = xls_dslx:match(xls_dslx:ref("kind"), [
        {xls_dslx:literal("u1", 0), xls_dslx:tuple(["old", "false"])},
        {"_", xls_dslx:tuple(["old", "true"])}]),
    Tree = xls_dslx:choose(xls_dslx:ref("take"), Selected, Other),
    ?assertMatch({xls_dslx, choose, _, {xls_dslx, block, [{xls_dslx, bind, "next", _}], _},
        {xls_dslx, match, _, [_, _]}}, Tree),
    ?assertEqual(<<"if take {\n  let next = step(old);\n  (next, false)\n} else {\n  match kind {\n    u1:0 => (old, false),\n    _ => (old, true),\n  }\n}">>, text(Tree)).

%% Text remains opaque; only the enclosing operation supplies grouping.
-spec opaque_operand_test() -> ok.
opaque_operand_test() ->
    ?assertEqual(<<"((a + b) * c)">>,
        text(xls_dslx:binary('*', "a + b", xls_dslx:ref("c")))).

%% Untyped integers remain width-directed leaves; floats and compile-time types cannot become runtime text.
-spec source_value_boundary_test() -> ok.
source_value_boundary_test() ->
    ?assertEqual(<<"-256">>, text({static, integer, -256})),
    ?assertError({untyped_float_literal, 1.5, {use, hls_float, literal, 2}},
        text({static, float, 1.5})),
    ?assertError(function_clause, xls_clause_lower:print({phantom, type, hls_nums:u8()})).

%% Freeze rendering only for these small syntax examples, never generated actor RTL.
-spec text(xls_dslx:value()) -> binary().
text(Value) -> iolist_to_binary(xls_dslx:render(Value)).
