-module(xls_source_map_tests).
-moduledoc "Source association through transparent syntax wrappers and final DSLX formatting, including erased blank lines and byte columns.".
-include_lib("eunit/include/eunit.hrl").

%% Indentation changes generated coordinates, never the bytes produced by the ordinary renderer.
-spec indentation_and_nested_ranges_test() -> ok.
indentation_and_nested_ranges_test() ->
    Outer = location(<<"actor.erl">>, 12),
    Inner = location(<<"include/actions.hrl">>, 7),
    Plain = ["header\n", xls_dslx:indent(["\n", <<"xy\n\nz">>, "\n"], 2)],
    Annotated = xls_dslx:source(Outer, ["header\n",
        xls_dslx:indent(["\n", xls_dslx:source(Inner, <<"xy\n\nz">>), "\n"], 2)]),
    {Bytes, Ranges} = xls_dslx:render_mapped(Annotated),
    ?assertEqual(<<"header\n  xy\n  z\n">>, Bytes),
    ?assertEqual(xls_dslx:render(Plain), Bytes),
    ?assertEqual([
        #{start => [1, 1], 'end' => [4, 1], source => Outer},
        #{start => [2, 3], 'end' => [3, 4], source => Inner}], Ranges).

%% Empty scopes do not leak into nearby generated tokens, and columns count UTF-8 bytes.
-spec byte_columns_and_erased_scopes_test() -> ok.
byte_columns_and_erased_scopes_test() ->
    Source = location(<<"actor.erl">>, 3),
    {Bytes, Ranges} = xls_dslx:render_mapped([
        <<16#CE, 16#BB>>, xls_dslx:source(Source, "abc"),
        xls_dslx:indent(xls_dslx:source(Source, "\n\n"), 2),
        xls_dslx:source(Source, [])]),
    ?assertEqual(<<16#CE, 16#BB, "abc">>, Bytes),
    ?assertEqual([#{start => [1, 3], 'end' => [1, 6], source => Source}], Ranges).

%% Source metadata cannot affect the syntax classification used by precedence and branch grouping.
-spec source_wrappers_preserve_grouping_test() -> ok.
source_wrappers_preserve_grouping_test() ->
    Source = location(<<"actor.erl">>, 4),
    Values = [xls_dslx:ref("x"), "a + b", xls_dslx:call("f", ["x"]),
        xls_dslx:binary('+', xls_dslx:ref("a"), xls_dslx:ref("b")),
        xls_dslx:block([xls_dslx:bind("v", "x")], "v"),
        xls_dslx:choose("take", "a", "b"),
        xls_dslx:match("tag", [{"_", "x"}])],
    Contexts = [fun(V) -> xls_dslx:field(V, "field") end,
        fun(V) -> xls_dslx:binary('+', V, "y") end,
        fun(V) -> xls_dslx:choose("take", V, "other") end],
    lists:foreach(fun(Value) ->
        lists:foreach(fun(Context) ->
            ?assertEqual(xls_dslx:render(Context(Value)),
                xls_dslx:render(Context(xls_dslx:source(Source, Value))))
        end, Contexts)
    end, Values).

%% Existing Erlang annotations carry includes and generated nodes remain deliberately unmapped.
-spec annotations_and_validation_test() -> ok.
annotations_and_validation_test() ->
    Anno = erl_anno:set_file("include/actions.hrl", erl_anno:new(8)),
    Value = xls_dslx:ref("value"),
    ?assertEqual(xls_dslx:source(location(<<"include/actions.hrl">>, 8), Value),
        xls_source_map:at(Anno, Value)),
    lists:foreach(fun(A) -> ?assertEqual(Value, xls_source_map:at(A, Value)) end,
        [0, undefined, erl_anno:new(8), erl_anno:set_generated(true, Anno)]),
    Bad = #{file => <<"actor.erl">>, line => 0},
    ?assertError({invalid_source_location, Bad}, xls_dslx:validate(xls_dslx:source(Bad, Value))).

%% Locations use the same shape emitted by preprocessed Erlang source preparation.
-spec location(binary(), pos_integer()) -> xls_source_map:location().
location(File, Line) -> #{file => File, line => Line}.
