-module(xls_type).
-moduledoc "Compiler dispatch for source operations and descriptor rendering. Built-in runtime providers have explicit compiler companions; application providers retain their own optional callbacks. hls_type owns host codecs and descriptors, while this module owns all dependence on clause IR and DSLX syntax.".

%% Resolve source providers and lower their operations.
-export([provider/1, transpile/4]).
%% Render descriptor value types and compose their wire conversions.
-export([print_type/1, dslx_codec/1, dslx_from_bits/2, dslx_to_bits/2]).
-export_type([result/0, codec/0]).

-doc "A lowered value, updated evaluation state, or a value/failure pair tagged with its source failure kind.".
-type result() ::
    xls_clause_lower:ir()
    | xls_clause_lower:clause_state()
    | {fallible, atom(), xls_clause_lower:ir()}.
-doc "A bit cast or composable from-bits/to-bits renderers; padding follows the host provider's encoding.".
-type codec() ::
    bit_cast
    | {fun((xls_dslx:value()) -> xls_dslx:value()), fun((xls_dslx:value()) -> xls_dslx:value())}.

-doc "Lowers one source call. Fallible expressions produce a value/failure pair; the compiler records source location and propagates the first selected failure.".
-callback transpile(atom(), [xls_clause_lower:ir()], xls_clause_lower:clause_state()) -> result().
-doc "Renders the descriptor's DSLX value type, whose wire width is owned by the runtime provider.".
-callback print_type(atom(), [hls_type:arg()]) -> xls_dslx:value().
-doc "Declares companion DSLX imports. XLS resolves their transitive dependencies on its import path.".
-callback dslx_imports() -> [atom()].
-doc "Declares imports for the sorted names actually used; this form takes precedence over dslx_imports/0.".
-callback dslx_imports([atom()]) -> [atom()].
-doc "Renders non-cast wire conversions, composing nested padding exactly as the host codec does. Omission selects bit casts.".
-callback dslx_codec(atom(), [hls_type:arg()]) -> codec().
-optional_callbacks([transpile/3, print_type/2, dslx_imports/0, dslx_imports/1, dslx_codec/2]).

-doc "Returns the built-in compiler companion or the custom provider itself. Custom callbacks require no registration and are consulted only during compilation.".
-spec provider(module()) -> module().
provider(hls_bits) -> xls_provider_bits;
provider(hls_bool) -> xls_provider_bool;
provider(hls_fixed) -> xls_provider_fixed;
provider(hls_float) -> xls_provider_float;
provider(hls_gs) -> xls_provider_gs;
provider(hls_lists) -> xls_provider_lists;
provider(hls_nums) -> xls_provider_nums;
provider(hls_prng) -> xls_provider_prng;
provider(hls_record) -> xls_provider_record;
provider(hls_serial) -> xls_provider_serial;
provider(hls_type) -> xls_provider_type;
provider(hls_vec) -> xls_provider_vec;
provider(Module) -> Module.

-doc "Lowers a source call through its compiler provider without changing the source module recorded in descriptors.".
-spec transpile(module(), atom(), [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    result().
transpile(Module, Name, Arguments, State) ->
    Provider = provider(Module),
    Provider:transpile(Name, Arguments, State).

-doc "Renders the descriptor's DSLX value type through its compiler provider.".
-spec print_type(hls_type:descriptor()) -> xls_dslx:value().
print_type({hls_type, Module, Name, Args}) ->
    Provider = provider(Module),
    Provider:print_type(Name, Args).

-doc "Returns the compiler provider's wire converters, defaulting to ordinary bit casts.".
-spec dslx_codec(hls_type:descriptor()) -> codec().
dslx_codec({hls_type, Module, Name, Args}) ->
    Provider = provider(Module),
    _ = code:ensure_loaded(Provider),
    case erlang:function_exported(Provider, dslx_codec, 2) of
        true -> Provider:dslx_codec(Name, Args);
        false -> bit_cast
    end.

-doc "Renders wire bits as a DSLX value using the provider's padding policy.".
-spec dslx_from_bits(hls_type:descriptor(), xls_dslx:value()) -> xls_dslx:value().
dslx_from_bits(Type, Bits) ->
    case dslx_codec(Type) of
        bit_cast -> [Bits, " as ", print_type(Type)];
        {Decode, _Encode} -> Decode(Bits)
    end.

-doc "Renders a DSLX value as serialized bits, including provider-defined padding.".
-spec dslx_to_bits(hls_type:descriptor(), xls_dslx:value()) -> xls_dslx:value().
dslx_to_bits(Type, Value) ->
    case dslx_codec(Type) of
        bit_cast -> [Value, " as bits[", integer_to_list(hls_type:width(Type)), "]"];
        {_Decode, Encode} -> Encode(Value)
    end.
