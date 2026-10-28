-module(xls_provider_float).
-moduledoc "Compiler companion for hls_float. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([dslx_imports/0, transpile/3]).

-spec dslx_imports() -> [atom()].
-doc "Declares the DSLX support modules needed by the selected operations and types.".
dslx_imports() -> [apfloat, hls_float].

-spec transpile(atom(), [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_type:result().
-doc "Lowers supported source operations while preserving their host arithmetic and failure contract.".
transpile(literal, [{phantom, type, Type}, {static, Kind, Value}], _State) when
    Kind =:= float; Kind =:= integer
->
    {E, F} = hls_float:format(Type),
    Width = 1 + E + F,
    <<Bits:Width/little>> = hls_type:pack(Value, Type),
    [
        "apfloat::unflatten<u32:",
        integer_to_list(E),
        ", u32:",
        integer_to_list(F),
        ">(uN[",
        integer_to_list(Width),
        "]:",
        integer_to_list(Bits),
        ")"
    ];
transpile(literal, _Args, _State) ->
    error(nonconstant_float_literal);
transpile(Operation, [{phantom, type, Type}, X, Y], _State) when
    Operation =:= add;
    Operation =:= sub;
    Operation =:= mul;
    Operation =:= eq;
    Operation =:= lt
->
    {E, F} = hls_float:format(Type),
    {fallible, badarith, [
        "hls_float::",
        atom_to_list(Operation),
        "<u32:",
        integer_to_list(E),
        ", u32:",
        integer_to_list(F),
        ">(",
        X,
        ", ",
        Y,
        ")"
    ]}.
