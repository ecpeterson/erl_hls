-module(xls_short_circuit_dslx).
-export([to_dslx/0]).

%% Compare the result and match-failure flag, including failures from a
%% selected RHS. A Boolean result alone would miss erroneous callback failure.
to_dslx() ->
    {ok, Forms} = epp:parse_file("test/xls_short_circuit_fixture.erl", [], []),
    ["import hls_failure;\n",
        [function(Name, Clause) || {function, _, Name, 3, [Clause]} <- Forms]].

function(Name, Clause) ->
    {Body, Result} = xls_parse:branch_from_clause(
        Clause, ["left", "right", "extra"], state,
        fun(Reference) -> ["(false, ", Reference, ")"] end,
        "(true, false)", #{}),
    Function = atom_to_list(Name),
    [
        "fn ", Function, "(left: bool, right: bool, extra: bool) -> (bool, bool) {\n",
        xls_parse:print([Body, Result]), "\n}\n",
        "#[test]\nfn ", Function, "_matches_beam() {\n",
        [assertion(Name, [Left, Right, Extra])
            || Left <- [false, true], Right <- [false, true],
               Extra <- [false, true]],
        "}\n"
    ].

assertion(Name, Arguments) ->
    {Failed, Value} = try apply(xls_short_circuit_fixture, Name, Arguments) of
        Result -> {false, Result}
    catch
        error:{badmatch, _} -> {true, false}
    end,
    [Left, Right, Extra] = Arguments,
    io_lib:format("  assert_eq(~s(~p, ~p, ~p), (~p, ~p));\n",
        [Name, Left, Right, Extra, Failed, Value]).
