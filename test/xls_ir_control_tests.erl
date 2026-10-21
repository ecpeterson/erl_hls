-module(xls_ir_control_tests).
-moduledoc "Parser and domain boundaries for generic control cancellation; actual circuit equality is checked separately.".
-include_lib("eunit/include/eunit.hrl").

%% Refuse reversing subtraction, preserve all metadata, and leave unknown work alone.
-spec cancellation_boundaries_test() -> ok.
cancellation_boundaries_test() ->
    {Same, []} = xls_ir_control:rewrite(ir(<<"sub">>, <<"b, a">>, <<"a">>)),
    ?assertEqual(ir(<<"sub">>, <<"b, a">>, <<"a">>), Same),
    {Bytes, [#{width := 32, remaining := <<"b">>}]} =
        xls_ir_control:rewrite(ir(<<"add">>, <<"b, a">>, <<"a">>)),
    ?assertNotEqual(nomatch, binary:match(Bytes, <<"ret result: bits[1] = eq(b, hls_control_zero_5, id=4, pos=[(0,1,2)])">>)),
    Original = ir(<<"and">>, <<"b, a">>, <<"a">>),
    ?assertEqual({Original, []}, xls_ir_control:rewrite(Original)),
    ok.

%% A package-level name collision or multiple function scope must never be guessed.
-spec scope_rejected_test() -> ok.
scope_rejected_test() ->
    I = ir(<<"xor">>, <<"a, b">>, <<"a">>),
    ?assertException(error, {badmatch, _}, xls_ir_control:rewrite(<<I/binary, I/binary>>)),
    ?assertException(error, {badmatch, _}, xls_ir_control:rewrite(<<"// hls_control_zero_
", I/binary>>)),
    ok.

%% Tiny valid single-function packages exercise syntax without application identities.
-spec ir(binary(), binary(), binary()) -> binary().
ir(Op, Args, Common) ->
    iolist_to_binary(["package test
file_number 0 \"test.x\"
top fn sample(a: bits[32] id=1, b: bits[32] id=2) -> bits[1] {
",
        "  value: bits[32] = ", Op, "(", Args, ", id=3)
",
        "  ret result: bits[1] = eq(value, ", Common, ", id=4, pos=[(0,1,2)])
}
"]).

%% Non-function scopes must not share a node-name table with a function.
-spec other_scope_rejected_test() -> ok.
other_scope_rejected_test() ->
    I = ir(<<"add">>, <<"a, b">>, <<"a">>),
    [?assertException(error, {badmatch, _}, xls_ir_control:rewrite(<<I/binary, Scope/binary>>))
        || Scope <- [<<"proc other() {\n}\n">>, <<"block other() {\n}\n">>]],
    ok.

%% Same-node arithmetic and symmetric comparisons retain an exact structural audit.
-spec symmetric_operands_test() -> ok.
symmetric_operands_test() ->
    [begin
        Source = ir(Op, Args, <<"a">>),
        {_, [#{operation := Op, common := <<"a">>, remaining := <<"b">>}]} =
            xls_ir_control:rewrite(Source),
        Reversed = binary:replace(Source, <<"eq(value, a,">>, <<"ne(a, value,">>),
        {_, [#{operation := Op}]} = xls_ir_control:rewrite(Reversed)
    end || Op <- [<<"add">>, <<"xor">>], Args <- [<<"a, b">>, <<"b, a">>]],
    {_, [#{remaining := <<"a">>}]} = xls_ir_control:rewrite(ir(<<"add">>, <<"a, a">>, <<"a">>)),
    ok.
