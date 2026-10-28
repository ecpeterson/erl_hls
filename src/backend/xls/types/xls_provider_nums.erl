-module(xls_provider_nums).
-moduledoc "Compiler companion for hls_nums. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([transpile/3, print_type/2, dslx_imports/1, dslx_codec/2]).

-doc "Lowers numeric type constructors and explicit fixed-width wrapping. Parameterized widths must be static.".
-spec transpile(atom(), [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_clause_lower:ir() | xls_clause_lower:clause_state().
transpile(wrap, [{phantom, type, Type = {hls_type, hls_nums, Name, _}}, Value], State) ->
    _ = hls_nums:signedness(Name),
    wrap_expression(Type, Value, State);
transpile(Type, [{static, integer, Width}], State) when Type =:= uN; Type =:= sN ->
    xls_clause_lower:reference(
        State,
        {phantom, type, hls_nums:Type(Width)}
    );
transpile(Type, [], State) ->
    xls_clause_lower:reference(State, {phantom, type, hls_nums:Type()}).

%% Normalize literals before emitting a typed constant; dynamic values keep explicit cast semantics.
-spec wrap_expression(
    hls_type:descriptor(), xls_clause_lower:ir(), xls_clause_lower:clause_state()
) -> xls_clause_lower:ir().
%% A literal has no source width from which to cast. Normalize it before giving
%% it the target type so an out-of-range literal never reaches the DSLX parser.
wrap_expression(Type, {static, integer, Value}, _State) ->
    [xls_type:print_type(Type), ":", integer_to_list(hls_nums:wrap(Type, Value))];
wrap_expression(Type, Value, State) ->
    xls_type:transpile(hls_type, as, [{phantom, type, Type}, Value], State).

-spec print_type(atom(), [hls_type:arg()]) -> xls_dslx:value().
-doc "Renders the provider value type; nested descriptors use compiler dispatch.".
print_type(u8, []) ->
    "u8";
print_type(u16, []) ->
    "u16";
print_type(u32, []) ->
    "u32";
print_type(u64, []) ->
    "u64";
print_type(uN, Args) ->
    ["uN[", integer_to_list(hls_nums:value_width(uN, Args)), "]"];
print_type(sN, Args) ->
    ["sN[", integer_to_list(hls_nums:value_width(sN, Args)), "]"];
print_type(s8, []) ->
    "s8";
print_type(s16, []) ->
    "s16";
print_type(s32, []) ->
    "s32";
print_type(s64, []) ->
    "s64";
print_type(Type, []) when Type =:= float16; Type =:= float32; Type =:= float64 ->
    {E, F} = hls_float:format({hls_type, hls_nums, Type, []}),
    ["apfloat::APFloat<u32:", integer_to_list(E), ", u32:", integer_to_list(F), ">"].

-spec dslx_imports([atom()]) -> [atom()].
-doc "Declares the DSLX support modules needed by the selected operations and types.".
dslx_imports(Names) ->
    case
        lists:any(
            fun(Name) ->
                Name =:= float16 orelse Name =:= float32 orelse Name =:= float64
            end,
            Names
        )
    of
        true -> [apfloat];
        false -> []
    end.

-spec dslx_codec(atom(), [hls_type:arg()]) -> xls_type:codec().
-doc "Converts wire bits and DSLX values using the provider encoding, including nested padding.".
dslx_codec(Type, []) when Type =:= float16; Type =:= float32; Type =:= float64 ->
    {E, F} = hls_float:format({hls_type, hls_nums, Type, []}),
    {
        fun(Bits) ->
            [
                "apfloat::unflatten<u32:",
                integer_to_list(E),
                ", u32:",
                integer_to_list(F),
                ">(",
                Bits,
                ")"
            ]
        end,
        fun(Value) -> ["apfloat::flatten(", Value, ")"] end
    };
dslx_codec(_Type, _Args) ->
    bit_cast.
