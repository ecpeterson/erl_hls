-module(xls_source_map_tests).
-moduledoc "Source association through transparent syntax wrappers and final DSLX formatting, including erased blank lines and byte columns.".
-include_lib("eunit/include/eunit.hrl").

%% Indentation changes annotation placement without changing the bytes of any code line.
-spec indentation_and_nested_origins_test() -> ok.
indentation_and_nested_origins_test() ->
    Outer = location(<<"actor.erl">>, 12),
    Inner = location(<<"include/actions.hrl">>, 7),
    Plain = ["header\n", xls_dslx:indent(["\n", <<"xy\n\nz">>, "\n"], 2)],
    Annotated = xls_dslx:source(Outer, ["header\n",
        xls_dslx:indent(["\n", xls_dslx:source(Inner, <<"xy\n\nz">>), "\n"], 2)]),
    ?assertEqual(<<"header\n  xy\n  z\n">>, xls_dslx:render(Annotated)),
    ?assertEqual(xls_dslx:render(Plain), xls_dslx:render(Annotated)),
    ?assertEqual(iolist_to_binary([
        "header", padding(74), "// @erl \"actor.erl\":12\n",
        "  xy", padding(76), "// @erl \"include/actions.hrl\":7\n",
        "  z", padding(77), "// @erl \"include/actions.hrl\":7\n"
    ]), xls_dslx:render_annotated(Annotated)).

%% Empty scopes do not leak into nearby generated tokens, and columns count UTF-8 bytes.
-spec byte_columns_and_erased_scopes_test() -> ok.
byte_columns_and_erased_scopes_test() ->
    Source = location(<<"actor.erl">>, 3),
    Document = [
        <<16#CE, 16#BB>>, xls_dslx:source(Source, "abc"),
        xls_dslx:indent(xls_dslx:source(Source, "\n\n"), 2),
        xls_dslx:source(Source, [])],
    Bytes = <<16#CE, 16#BB, "abc">>,
    ?assertEqual(Bytes, xls_dslx:render(Document)),
    ?assertEqual(iolist_to_binary([Bytes, padding(75), "// @erl 3:6 \"actor.erl\":3"]),
        xls_dslx:render_annotated(Document)).

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

%% Final output appends readable comments while ordinary rendering and trailing-newline status remain unchanged.
-spec simple_annotation_and_long_line_test() -> ok.
simple_annotation_and_long_line_test() ->
    Source = location(<<"actor.erl">>, 23),
    Code = <<"let x = u8:1;">>,
    Annotated = xls_dslx:source(Source, Code),
    ?assertEqual(Code, xls_dslx:render(Annotated)),
    Expected = <<Code/binary, (padding(80 - byte_size(Code)))/binary, "// @erl \"actor.erl\":23">>,
    ?assertEqual(Expected, xls_dslx:render_annotated(Annotated)),
    ?assertEqual(<<Expected/binary, "\n">>, xls_dslx:render_annotated([Annotated, "\n"])),
    Long = binary:copy(<<"x">>, 100),
    ?assertEqual(<<Long/binary, "  // @erl \"actor.erl\":23">>,
        xls_dslx:render_annotated(xls_dslx:source(Source, Long))).

%% An existing source-line hint remains in its original comment, with no fake second comment delimiter.
-spec existing_comment_annotation_test() -> ok.
existing_comment_annotation_test() ->
    Source = location(<<"actor.erl">>, 23),
    Code = <<"let x = u8:1; // L23">>,
    Expected = <<Code/binary, (padding(83 - byte_size(Code)))/binary, "@erl \"actor.erl\":23\n">>,
    ?assertEqual(Expected, xls_dslx:render_annotated(xls_dslx:source(Source, [Code, "\n"]))),
    CommentOnly = <<"  // L23\n">>,
    ?assertEqual(CommentOnly, xls_dslx:render_annotated(xls_dslx:source(Source, CommentOnly))).

%% Narrow inner ownership overrides a broad fallback, and disjoint owners retain precise code columns.
-spec nested_origins_and_continuations_test() -> ok.
nested_origins_and_continuations_test() ->
    Outer = location(<<"actor.erl">>, 23),
    Inner = location(<<"include/helper.hrl">>, 14),
    Code = <<"let a = b;">>,
    Document = xls_dslx:source(Outer, ["let a = ", xls_dslx:source(Inner, "b"), ";"]),
    Expected = [Code, padding(80 - byte_size(Code)), "// @erl 1:8 \"actor.erl\":23\n",
        padding(80), "// @erl+ 9:10 \"include/helper.hrl\":14\n",
        padding(80), "// @erl+ 10:11 \"actor.erl\":23"],
    ?assertEqual(iolist_to_binary(Expected), xls_dslx:render_annotated(Document)),
    WithComment = xls_dslx:source(Outer, ["let a = ", xls_dslx:source(Inner, "b"), "; // L23"]),
    [First, Second, Third] = binary:split(xls_dslx:render_annotated(WithComment), <<"\n">>, [global]),
    ?assertMatch({83, _}, binary:match(First, <<"@erl ">>)),
    ?assertMatch({83, _}, binary:match(Second, <<"@erl+ ">>)),
    ?assertMatch({83, _}, binary:match(Third, <<"@erl+ ">>)).

%% Unmapped code forces explicit ranges; UTF-8 prefixes count bytes rather than characters.
-spec partial_ranges_and_escaped_files_test() -> ok.
partial_ranges_and_escaped_files_test() ->
    Source = location(<<"a\"b\\c.erl">>, 3),
    Code = <<16#CE, 16#BB, " x;">>,
    Document = [<<16#CE, 16#BB, " ">>, xls_dslx:source(Source, "x"), ";"],
    ?assertEqual(iolist_to_binary([Code, padding(80 - byte_size(Code)),
        "// @erl 4:5 \"a\\\"b\\\\c.erl\":3"]), xls_dslx:render_annotated(Document)).

%% Equal-sized conflicting scopes cannot guess an origin, including when a broader fallback exists.
-spec ambiguous_ranges_remain_unmapped_test() -> ok.
ambiguous_ranges_remain_unmapped_test() ->
    A = location(<<"a.erl">>, 1),
    B = location(<<"b.erl">>, 2),
    Ambiguous = xls_dslx:source(A, xls_dslx:source(B, "x")),
    ?assertEqual(<<"x">>, xls_dslx:render_annotated(Ambiguous)),
    Document = xls_dslx:source(A, ["let x = ", Ambiguous, ";"]),
    Text = xls_dslx:render_annotated(Document),
    ?assertNotEqual(nomatch, binary:match(Text, <<"@erl 1:8 \"a.erl\":1">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"@erl+ 10:11 \"a.erl\":1">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"9:10">>)).

%% Marker-looking text in literals is ordinary code, and apostrophes inside identifiers are not quotes.
-spec literal_and_identifier_comment_boundaries_test() -> ok.
literal_and_identifier_comment_boundaries_test() ->
    Source = location(<<"actor.erl">>, 8),
    Lines = [<<"let s = \"// @erl fake \\\"quoted\\\"\";">>,
        <<"let s = `// @erl fake`;">>,
        <<"let state'' = '/' + '\\\''; // existing">>,
        <<"'label: for (x, a) in u32:0..u32:1 { a }(u32:0)">>],
    lists:foreach(fun(Code) ->
        Text = xls_dslx:render_annotated(xls_dslx:source(Source, Code)),
        ?assertEqual(Code, binary:part(Text, 0, byte_size(Code))),
        ?assertNotEqual(nomatch, binary:match(Text, <<"@erl \"actor.erl\":8">>))
    end, Lines).

%% A physical line inside a multiline literal cannot accept a comment without changing its value.
-spec multiline_literals_are_not_modified_test() -> ok.
multiline_literals_are_not_modified_test() ->
    Source = location(<<"actor.erl">>, 9),
    lists:foreach(fun(Quote) ->
        First = <<"let s = ", Quote, "text">>,
        Middle = <<"// @erl this is string content">>,
        Last = <<"end", Quote, ";">>,
        Original = [First, "\n", Middle, "\n", Last],
        [ActualFirst, ActualMiddle, ActualLast] = binary:split(
            xls_dslx:render_annotated(xls_dslx:source(Source, Original)), <<"\n">>, [global]),
        ?assertEqual(First, ActualFirst),
        ?assertEqual(Middle, ActualMiddle),
        ?assertEqual(Last, binary:part(ActualLast, 0, byte_size(Last))),
        ?assertNotEqual(nomatch, binary:match(ActualLast, <<"// @erl \"actor.erl\":9">>))
    end, [$", $`]).

%% Expected alignment uses spaces only and never pads the unannotated code itself.
-spec padding(non_neg_integer()) -> binary().
padding(Count) -> binary:copy(<<" ">>, Count).
