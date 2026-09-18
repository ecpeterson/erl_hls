-module(hls_type).
-moduledoc "Typed host codecs and DSLX conversion through type-provider descriptors.".
-export([
    as/2,
    descriptor/1,
    dslx_codec/1,
    dslx_from_bits/2,
    dslx_to_bits/2,
    normalize/2,
    pack/2,
    pack_exact/2,
    print_type/1,
    unpack/2,
    transpile/3,
    value_width/1,
    width/1,
    zero/0,
    zero/1
]).
-export_type([descriptor/0, arg/0]).

%%%
%%% Structure for XLS type descriptors
%%%

-record(hls_type, {
    module,
    name,
    args
}).
-doc "A type provider, constructor name and its ordered parameters.".
-type descriptor() :: #hls_type{
    module :: module(),
    name :: atom(),
    args :: [arg()]
}.
-doc "A numeric, atom or nested type parameter supplied to a type constructor.".
-type arg() :: integer() | atom() | descriptor().

%%%
%%% hls_type behavior
%%%

-doc """
Packs a value into a bitstring of exactly the bit width returned by `width/2`.
Each provider defines its accepted domain and normalization policy. Every
successful pack must unpack completely and repack to identical bits; repeated
normalization must preserve the decoded value. Reject invalid shapes and values
outside that domain. These are codec laws, not arithmetic equivalence laws.
""".
-callback pack(Value :: any(), atom(), [any()]) -> bitstring().

-doc """
Unpacks a value previously processed by pack/2.  This is usually a sub-call of
an `hls_gs` instance's `unpack/2`.
""".
-callback unpack(Packed :: bitstring(), atom(), [any()]) -> {Value :: any(), Rest :: bitstring()}.

-doc """
Converts an Erlang call with XLS embodiments of its arguments to an equivalent
XLS expression. A `fallible` result renders `(value, failed: bool)`; the compiler
attaches the call's source location and propagates its registered failure kind.
""".
%% TODO: might need to supply clause state for anonymous variables
-callback transpile(FnName :: atom(), XLSArgs :: [xls_parse:ir()], State :: xls_parse:clause_state()) ->
    xls_parse:ir() | xls_parse:clause_state() |
    {fallible, atom(), xls_parse:ir()}.

-doc """
Declares the DSLX modules used by this provider's types and expressions.

The compiler discovers providers in include-expanded remote types and calls,
including nested type arguments, and emits each import once. Providers without
companions can omit this callback. Modules must be available on the DSLX import
path; their own transitive imports are resolved by XLS. The optional one-argument
form takes precedence and receives the sorted names used from the provider,
allowing types such as integers to avoid importing unrelated float companions.
""".
-callback dslx_imports() -> [atom()].
-doc "Declares imports for the provider names actually used in the source.".
-callback dslx_imports([atom()]) -> [atom()].

-doc """
Describes wire conversion for a type whose DSLX value cannot use a bit cast.
The two functions render from-bits and to-bits expressions respectively.
Collections compose their element codecs, including padding within each
element. Omission means ordinary bit casts; value_width/2 declares whether
such casts add or remove padding. Padding must match the host codec policy.
""".
-callback dslx_codec(atom(), [arg()]) -> bit_cast |
    {fun((xls_parse:printable()) -> xls_parse:printable()),
     fun((xls_parse:printable()) -> xls_parse:printable())}.
-optional_callbacks([dslx_imports/0, dslx_imports/1, dslx_codec/2]).

-doc "Builds an empty Erlang instance of this type.".
-callback zero(TypeName :: atom(), Args :: [arg()]) -> any().

-doc "Emits the corresponding XLS type for the Erlang type descriptor.".
-callback print_type(TypeName :: atom(), Args :: [any()]) -> xls_parse:printable().

-doc "Serialized bit width, including padding; pack/3 must return this many bits.".
-callback width(Name :: atom(), Args :: [any()]) -> integer().

-doc "Logical XLS value width, excluding wire padding. Defaults to width/2.".
-callback value_width(Name :: atom(), Args :: [arg()]) -> non_neg_integer().
-optional_callbacks([value_width/2]).

% -doc """
% in-XLS un/pack? or maybe transpiles to `as` but has no Erlang effect?
% """.
% -callback as(Descriptor :: [any()], InValue :: any()) -> OutValue :: any().

%%%
%%% Descriptor-level versions which dispatch on Module
%%%

-spec zero() -> no_return().
-doc """
Type-directed zero-value marker for translated record field defaults.

`hls_pack` replaces this call with `zero/1` using the field's type annotation.
Calling it outside a transformed record declaration is an error.
""".
zero() ->
    error(unexpanded_hls_zero).

-spec zero(descriptor()) -> any().
-doc "Returns the provider's zero value for the descriptor.".
zero(#hls_type{module = Module, name = Name, args = Args}) ->
    Module:zero(Name, Args).

-doc """
Ascribes an XLS type to a value whose Erlang representation is unchanged.

On the BEAM this returns `Value`. Translation emits a DSLX `as` expression,
which is useful when the surrounding expression does not determine the width
of an Erlang literal.
""".
-spec as(descriptor(), Value) -> Value.
as(_Descriptor, Value) ->
    Value.

-doc "Lowers a type ascription; rejects host-only normalization and exact-packing operations.".
-spec transpile(atom(), [xls_parse:ir()], xls_parse:clause_state()) -> xls_parse:ir().
transpile(as, [{phantom, type, Descriptor}, Value], _State) ->
    ["(", Value, " as ", print_type(Descriptor), ")"];
transpile(Operation, _Args, _State) when Operation =:= normalize;
        Operation =:= pack_exact ->
    error({host_only_type_operation, Operation}).

-spec width(descriptor()) -> integer().
-doc "Returns the serialized bit width, including padding.".
width(#hls_type{module = Module, name = Name, args = Args}) ->
    Module:width(Name, Args).

-doc "Returns the logical value width; width/1 returns the serialized width.".
-spec value_width(descriptor()) -> non_neg_integer().
value_width(#hls_type{module = Module, name = Name, args = Args}) ->
    _ = code:ensure_loaded(Module),
    case erlang:function_exported(Module, value_width, 2) of
        true -> Module:value_width(Name, Args);
        false -> Module:width(Name, Args)
    end.

-doc """
Packs a host value, checking the provider's bitstring against its declared width.
Built-in integers reject overflow and fixed-size collections require exact
lengths. Floats round to the selected IEEE binary format and reject nonfinite
results. Generated record packers use this boundary for each field, including
fields in topology startup messages. See docs/numeric-contract.md.
""".
-spec pack(term(), descriptor()) -> bitstring().
pack(Value, Descriptor = #hls_type{module = Module, name = Name, args = Args}) ->
    Width = width(Descriptor),
    case Module:pack(Value, Name, Args) of
        Packed when is_bitstring(Packed), bit_size(Packed) =:= Width -> Packed;
        Packed when is_bitstring(Packed) ->
            error({invalid_packed_width, Descriptor, Width, bit_size(Packed)});
        _Invalid -> error({invalid_packed_value, Descriptor})
    end.

-doc """
Returns the host value obtained by packing and unpacking at the declared type.
This exposes wire rounding without introducing a new live-value representation.
It works recursively for collections and is a host-only operation. Integer
overflow is still an error; use the numeric provider's wrap/2 to request wrapping.
""".
-spec normalize(descriptor(), term()) -> term().
normalize(Descriptor, Value) ->
    {Normalized, <<>>} = unpack(pack(Value, Descriptor), Descriptor),
    Normalized.

-doc """
Packs only if unpacking preserves the original Erlang term exactly (=:=).
This host-only check rejects float rounding and integer-to-float coercion,
including inside collections. Ordinary pack/2 follows the provider's policy.
""".
-spec pack_exact(term(), descriptor()) -> bitstring().
pack_exact(Value, Descriptor) ->
    Packed = pack(Value, Descriptor),
    case unpack(Packed, Descriptor) of
        {Value, <<>>} -> Packed;
        {_Normalized, <<>>} -> error({inexact_packing, Descriptor})
    end.

-doc "Decodes exactly one declared-width field and returns its value and remaining bits.".
-spec unpack(bitstring(), descriptor()) -> {term(), bitstring()}.
unpack(Packed, Type = {hls_type, Module, Name, Args}) ->
    {Field, Rest} = hls_codec:split(Packed, width(Type)),
    {Value, <<>>} = Module:unpack(Field, Name, Args),
    {Value, Rest}.

-doc "Renders the descriptor's DSLX value type.".
-spec print_type(descriptor()) -> xls_parse:printable().
print_type({hls_type, Module, Name, Args}) ->
    Module:print_type(Name, Args).

-doc "Returns the provider's from-bits/to-bits renderers, or bit_cast for ordinary value types.".
-spec dslx_codec(descriptor()) -> bit_cast | {fun((xls_parse:printable()) -> xls_parse:printable()), fun((xls_parse:printable()) -> xls_parse:printable())}.
dslx_codec({hls_type, Module, Name, Args}) ->
    _ = code:ensure_loaded(Module),
    case erlang:function_exported(Module, dslx_codec, 2) of
        true -> Module:dslx_codec(Name, Args);
        false -> bit_cast
    end.

-doc "Renders wire bits as a typed DSLX value using the provider's padding policy.".
-spec dslx_from_bits(descriptor(), xls_parse:printable()) -> xls_parse:printable().
dslx_from_bits(Type, Bits) ->
    case dslx_codec(Type) of
        bit_cast -> [Bits, " as ", print_type(Type)];
        {Decode, _Encode} -> Decode(Bits)
    end.

-doc "Renders a DSLX value as serialized bits, including the provider's padding.".
-spec dslx_to_bits(descriptor(), xls_parse:printable()) -> xls_parse:printable().
dslx_to_bits(Type, Value) ->
    case dslx_codec(Type) of
        bit_cast -> [Value, " as bits[", integer_to_list(width(Type)), "]"];
        {_Decode, Encode} -> Encode(Value)
    end.

%%%
%%%
%%%

-spec descriptor(erl_parse:abstract_type()) -> arg().
-doc "Converts a remote type expression or literal parameter to its provider descriptor or value.".
descriptor({remote_type, _1, [{atom, _2, Module}, {atom, _3, Name}, Args]}) ->
    {hls_type, Module, Name, [descriptor(Arg) || Arg <- Args]};
descriptor({integer, _1, Integer}) ->
    Integer;
descriptor({atom, _1, Atom}) ->
    Atom.
