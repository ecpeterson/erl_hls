-module(xls_literal_types_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% A declared helper type does not grant permission to wrap, round or coerce.
-spec literal_range_test_() -> [term()].
literal_range_test_() ->
    [?_assertException(error, {xls_literal_type, _, _, _, _}, prepare(Type, Value))
        || {Type, Value} <- [
            {"hls_nums:u8()", "256"}, {"hls_nums:u8()", "-1"},
            {"hls_nums:sN(5)", "-17"}, {"hls_nums:sN(5)", "16"},
            {"boolean()", "0"}, {"hls_bool:bool()", "1"}
        ]].

%% Infer from an argument contract, rather than asserting private IR spelling.
-spec prepare(string(), string()) -> {[hls_source:form()], [map()]}.
prepare(Type, Value) ->
    Sources = ["-module(literal_range).", "-hls_data(unused).", "-hls_tags([]).",
        "root() -> identity(" ++ Value ++ ").",
        "-spec identity(" ++ Type ++ ") -> " ++ Type ++ ".", "identity(X) -> X."],
    Forms = [begin
        {ok, Tokens, _} = erl_scan:string(Source),
        {ok, Form} = erl_parse:parse_form(Tokens), Form
    end || Source <- Sources],
    xls_helpers:prepare(Forms, [{root, 0}]).

%% Field widths constrain literals in construction and updates, including padding.
-spec record_literal_range_test_() -> [term()].
record_literal_range_test_() ->
    [?_assertException(error, {xls_literal_type, _, _, _, _},
        prepare_record(Type, Value, Update))
        || Update <- [false, true], {Type, Value} <- [
            {"hls_nums:u8()", "256"}, {"hls_nums:u8()", "-1"},
            {"hls_nums:sN(5)", "-17"}, {"hls_nums:sN(5)", "16"},
            {"hls_bool:bool()", "1"},
            {"hls_bits:padded(hls_nums:uN(3), 32)", "8"}
        ]].

%% A record field is a consumer even without a helper signature.
-spec prepare_record(string(), string(), boolean()) -> {[hls_source:form()], [map()]}.
prepare_record(Type, Value, Update) ->
    Constructor = case Update of true -> "Cell#cell"; false -> "#cell" end,
    Sources = ["-module(record_range).", "-hls_data(cell).", "-hls_tags([]).",
        "-record(cell, {value = hls_type:zero() :: " ++ Type ++ "}).",
        "root(Cell) -> Value = " ++ Value ++ ", " ++ Constructor ++ "{value = Value}."],
    Forms = [begin
        {ok, Tokens, _} = erl_scan:string(Source),
        {ok, Form} = erl_parse:parse_form(Tokens), Form
    end || Source <- Sources],
    xls_helpers:prepare(Forms, [{root, 1}]).

%% A helper argument receives its type after the complete static calculation.
-spec static_helper_argument_test_() -> [term()].
static_helper_argument_test_() ->
    [?_test(begin
        {Forms, _Helpers} = prepare(Type, Expression),
        assert_typed_integer(hls_source:find_function(Forms, root, 0), Target, Value)
    end) || {Type, Target, Expression, Value} <- static_boundaries()].

%% The helper result contract must not narrow an otherwise untyped intermediate.
-spec static_helper_result_test_() -> [term()].
static_helper_result_test_() ->
    [?_test(begin
        {_Forms, [#{clauses := Clauses}]} = prepare_result(Type, Expression),
        assert_typed_integer(Clauses, Target, Value)
    end) || {Type, Target, Expression, Value} <- static_boundaries()].

%% Constructors and updates share the field boundary without typing operands early.
-spec static_record_field_test_() -> [term()].
static_record_field_test_() ->
    [?_test(begin
        {Forms, _Helpers} = prepare_record(Type, Expression, Update),
        assert_typed_integer(hls_source:find_function(Forms, root, 1), Target, Value)
    end) || Update <- [false, true],
        {Type, Target, Expression, Value} <- static_boundaries()].

%% Final range checks apply to mathematical expression results, not only literal tokens.
-spec static_expression_range_test_() -> [term()].
static_expression_range_test_() ->
    [?_assertException(error, {xls_literal_type, _, Value, _, _}, Consumer(Type, Expression))
        || Consumer <- [fun prepare/2, fun prepare_result/2,
            fun(Type, Expression) -> prepare_record(Type, Expression, false) end,
            fun(Type, Expression) -> prepare_record(Type, Expression, true) end],
        {Type, Expression, Value} <- [
            {"hls_nums:u8()", "(1 bsl 8) - 0", 256},
            {"hls_nums:s16()", "(1 bsl 15) + 0", 32768},
            {"hls_nums:s8()", "0 - ((1 bsl 7) + 1)", -129}
        ]].

%% A later helper contract cannot force a wider static alias into its result width.
-spec static_alias_helper_argument_test_() -> [term()].
static_alias_helper_argument_test_() ->
    [?_test(begin
        {Forms, _Helpers} = prepare_body(Type, Body),
        assert_typed_integer(hls_source:find_function(Forms, root, 0), Target, Value)
    end) || {Type, Target, Body, Value} <- [
        {"hls_nums:u8()", <<"u8">>, "A = 256, B = A - 1, identity(B)", 255},
        {"hls_nums:s16()", <<"s16">>, "N = 32768, identity(-N)", -32768}
    ]].

%% The signed result fits even though the bound positive magnitude does not.
-spec static_alias_helper_result_test() -> ok.
static_alias_helper_result_test() ->
    {_Forms, [#{clauses := Clauses}]} = prepare_result("hls_nums:s16()", "N = 32768, -N"),
    assert_typed_integer(Clauses, <<"s16">>, -32768).

%% Record consumers must preserve the same alias semantics as helper contracts.
-spec static_alias_record_field_test_() -> [term()].
static_alias_record_field_test_() ->
    [?_test(begin
        {Forms, _Helpers} = prepare_record_body(Type, Prefix, Field, Update),
        assert_typed_integer(hls_source:find_function(Forms, root, 1), Target, Value)
    end) || Update <- [false, true], {Type, Target, Prefix, Field, Value} <- [
        {"hls_nums:u8()", <<"u8">>, "A = 256, B = A - 1, ", "B", 255},
        {"hls_nums:s16()", <<"s16">>, "N = 32768, ", "-N", -32768}
    ]].

%% Both final values fit; their positive intermediate exceeds the consuming type.
-spec static_boundaries() -> [{string(), binary(), string(), integer()}].
static_boundaries() ->
    [{"hls_nums:s16()", <<"s16">>, "0 - (1 bsl 15)", -32768},
     {"hls_nums:u8()", <<"u8">>, "(1 bsl 8) - 1", 255}].

%% Prepare a caller with preceding local bindings and one typed identity consumer.
-spec prepare_body(string(), string()) -> {[hls_source:form()], [map()]}.
prepare_body(Type, Body) ->
    prepare_sources(["-module(literal_alias).", "-hls_data(unused).", "-hls_tags([]).",
        "root() -> " ++ Body ++ ".",
        "-spec identity(" ++ Type ++ ") -> " ++ Type ++ ".", "identity(X) -> X."],
        [{root, 0}]).

%% A zero-argument helper places the type boundary at its returned expression.
-spec prepare_result(string(), string()) -> {[hls_source:form()], [map()]}.
prepare_result(Type, Expression) ->
    prepare_sources(["-module(literal_result).", "-hls_data(unused).", "-hls_tags([]).",
        "root() -> value().", "-spec value() -> " ++ Type ++ ".",
        "value() -> " ++ Expression ++ "."], [{root, 0}]).

%% Keep a record field as the only type consumer of preceding constant aliases.
-spec prepare_record_body(string(), string(), string(), boolean()) ->
    {[hls_source:form()], [map()]}.
prepare_record_body(Type, Prefix, Field, Update) ->
    Constructor = case Update of true -> "Cell#cell"; false -> "#cell" end,
    prepare_sources(["-module(record_alias).", "-hls_data(cell).", "-hls_tags([]).",
        "-record(cell, {value = hls_type:zero() :: " ++ Type ++ "}).",
        "root(Cell) -> " ++ Prefix ++ Constructor ++ "{value = " ++ Field ++ "}."],
        [{root, 1}]).

%% Use the real helper preparation and its record/literal passes on parsed source.
-spec prepare_sources([string()], [{atom(), arity()}]) -> {[hls_source:form()], [map()]}.
prepare_sources(Sources, Roots) ->
    Forms = [begin
        {ok, Tokens, _} = erl_scan:string(Source),
        {ok, Form} = erl_parse:parse_form(Tokens), Form
    end || Source <- Sources],
    xls_helpers:prepare(Forms, Roots).

%% Check the annotated consumer value, not rendered arithmetic or temporary names.
-spec assert_typed_integer(term(), binary(), integer()) -> ok.
assert_typed_integer(Source, Type, Value) ->
    ?assertEqual([{Type, Value}], typed_integers(Source)).

%% Static source aliases may remain, but no intermediate may acquire a narrow type.
-spec typed_integers(term()) -> [{binary(), integer()}].
typed_integers({xls_typed_integer, _, Type, Value}) -> [{iolist_to_binary(Type), Value}];
typed_integers(Tuple) when is_tuple(Tuple) -> typed_integers(tuple_to_list(Tuple));
typed_integers(List) when is_list(List) -> lists:append([typed_integers(Item) || Item <- List]);
typed_integers(_) -> [].
