-module(xls_provider_fixed).
-moduledoc "Compiler companion for hls_fixed. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([print_type/2, dslx_imports/0, transpile/3]).

-spec print_type(atom(), [hls_type:arg()]) -> xls_dslx:value().
-doc "Renders the provider value type; nested descriptors use compiler dispatch.".
print_type(signed, [Width, _FractionBits]) -> xls_nums:signed_type(Width).

-spec dslx_imports() -> [atom()].
-doc "Declares the DSLX support modules needed by the selected operations and types.".
dslx_imports() -> [hls_fixed].

-doc "Lowers fixed-point descriptors, wrapping, saturation and ratio rounding. Type parameters and ratio denominators must be static.".
-spec transpile(
    signed | wrap | saturate | round_ratio,
    [xls_clause_lower:ir()],
    xls_clause_lower:clause_state()
) ->
    xls_clause_lower:ir() | xls_clause_lower:clause_state().
transpile(
    wrap,
    [
        {phantom, type, Type = {hls_type, hls_fixed, signed, _}},
        {static, integer, Value}
    ],
    _State
) ->
    [xls_type:print_type(Type), ":", integer_to_list(hls_fixed:wrap(Type, Value))];
transpile(wrap, [{phantom, type, Type = {hls_type, hls_fixed, signed, _}}, Value], State) ->
    xls_type:transpile(hls_type, as, [{phantom, type, Type}, Value], State);
transpile(signed, [{static, integer, Width}, {static, integer, FractionBits}], State) ->
    xls_clause_lower:reference(State, {phantom, type, hls_fixed:signed(Width, FractionBits)});
transpile(saturate, [{phantom, type, Type}, Value], _State) ->
    [
        "hls_fixed::saturate<u32:",
        integer_to_list(hls_type:width(Type)),
        ">(",
        Value,
        ")"
    ];
transpile(round_ratio, [Numerator, {static, integer, Denominator}], _State) when
    Denominator > 0, Denominator < (1 bsl 32)
->
    [
        "hls_fixed::round_ratio<u32:",
        integer_to_list(Denominator),
        ">(",
        Numerator,
        ")"
    ].
