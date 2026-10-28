-module(xls_provider_bits).
-moduledoc "Compiler companion for hls_bits. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([print_type/2, dslx_imports/0, dslx_codec/2, transpile/3]).

-spec print_type(atom(), [hls_type:arg()]) -> xls_dslx:value().
-doc "Renders the provider value type; nested descriptors use compiler dispatch.".
%% A one-tuple distinguishes streams from integers without adding hardware.
print_type(bits, [Width]) -> ["(bits[", integer_to_list(Width), "],)"];
print_type(padded, [Type, _Width]) -> xls_type:print_type(Type).

-spec dslx_imports() -> [atom()].
-doc "Declares the DSLX support modules needed by the selected operations and types.".
dslx_imports() -> [hls_bits].

-spec dslx_codec(atom(), [hls_type:arg()]) -> xls_type:codec().
-doc "Converts wire bits and DSLX values using the provider encoding, including nested padding.".
dslx_codec(bits, [_Width]) ->
    {fun(Bits) -> ["(hls_bits::to_stream(", Bits, "),)"] end, fun(Value) ->
        ["hls_bits::from_stream((", Value, ").0)"]
    end};
dslx_codec(padded, [Type, Width]) ->
    SubWidth = hls_type:width(Type),
    {
        fun(Bits) ->
            xls_type:dslx_from_bits(
                Type,
                [
                    "hls_bits::from_stream(hls_bits::to_stream(",
                    Bits,
                    ")[",
                    integer_to_list(Width - SubWidth),
                    ":])"
                ]
            )
        end,
        fun(Value) ->
            [
                "hls_bits::pad<u32:",
                integer_to_list(SubWidth),
                ", u32:",
                integer_to_list(Width),
                ">(",
                xls_type:dslx_to_bits(Type, Value),
                ")"
            ]
        end
    }.

-doc "Creates compile-time bitstream and padded-type descriptors from static widths.".
-spec transpile(bits | padded, [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_clause_lower:clause_state().
transpile(bits, [{static, integer, Width}], State) ->
    xls_clause_lower:reference(State, {phantom, type, hls_bits:bits(Width)});
transpile(padded, [{phantom, type, Type}, {static, integer, Width}], State) ->
    xls_clause_lower:reference(State, {phantom, type, hls_bits:padded(Type, Width)}).
