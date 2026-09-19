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
