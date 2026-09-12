-module(hls_numeric_dslx).
-export([to_dslx/0]).

%% Exercise the actual Erlang expression lowering, then compare XLS results
%% with the public BEAM conversion APIs. Arithmetic caveats live in the static
%% DSLX test fragment rather than in generated Erlang string literals.
to_dslx() ->
    Formats = [
        {"wrap_u8", "hls_nums:wrap(hls_nums:u8(), Value)", hls_nums:u8(),
            fun(Value) -> hls_nums:wrap(hls_nums:u8(), Value) end},
        {"wrap_s8", "hls_nums:wrap(hls_nums:s8(), Value)", hls_nums:s8(),
            fun(Value) -> hls_nums:wrap(hls_nums:s8(), Value) end},
        {"wrap_u24", "hls_nums:wrap(hls_nums:uN(24), Value)", hls_nums:uN(24),
            fun(Value) -> hls_nums:wrap(hls_nums:uN(24), Value) end},
        {"wrap_fixed", "hls_fixed:wrap(hls_fixed:signed(16, 8), Value)",
            hls_fixed:signed(16, 8),
            fun(Value) -> hls_fixed:wrap(hls_fixed:signed(16, 8), Value) end}
    ],
    Values = [-((1 bsl 100) + 129), -65537, -129, -1, 0, 127, 128,
        255, 256, 65536, (1 bsl 100) + 129],
    {ok, Semantics} = file:read_file("test_data/hls_numeric_semantics.inc.x"),
    [
        "import hls_failure;\nimport float32;\nimport float64;\nimport hfloat16;\n",
        [function(Name, "value: sN[128]", Type, "Value", Expression, ["value"])
            || {Name, Expression, Type, _Wrap} <- Formats],
        function("negative_literal", "", hls_nums:u8(), "",
            "hls_nums:wrap(hls_nums:u8(), -1)", []),
        function("large_literal", "", hls_nums:s8(), "",
            "hls_nums:wrap(hls_nums:s8(), 1267650600228229401496703205505)", []),
        function("fixed_literal", "", hls_fixed:signed(8, 4), "",
            "hls_fixed:wrap(hls_fixed:signed(8, 4), 128)", []),
        "#[test]\nfn wraps_match_beam() {\n",
        [io_lib:format("  assert_eq(~s(sN[128]:~p), ~s:~p);\n",
            [Name, Value, hls_type:print_type(Type), Wrap(Value)])
            || {Name, _Expression, Type, Wrap} <- Formats, Value <- Values],
        "  assert_eq(negative_literal(), u8:255);\n",
        "  assert_eq(large_literal(), s8:-127);\n",
        "  assert_eq(fixed_literal(), s8:-128);\n}\n",
        Semantics
    ].

function(Name, Parameters, Type, Arguments, Expression, References) ->
    {ok, Tokens, _} = erl_scan:string(lists:flatten(
        ["probe(", Arguments, ") -> ", Expression, "."])),
    {ok, {function, _, probe, _, [Clause]}} = erl_parse:parse_form(Tokens),
    Failure = ["fail!(\"unexpected_failure\", zero!<", hls_type:print_type(Type), ">())"],
    {Body, Result} = xls_parse:branch_from_clause(Clause, References, state,
        fun(Reference) -> Reference end, Failure, #{}),
    ["fn ", Name, "(", Parameters, ") -> ", hls_type:print_type(Type), " {\n",
        xls_parse:print([Body, Result]), "\n}\n"].
