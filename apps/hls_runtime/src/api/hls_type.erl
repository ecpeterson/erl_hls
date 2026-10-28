-module(hls_type).
-moduledoc """
Runtime type-provider contract and descriptors shared by actor source and retained host codecs. Dispatches widths, normalization and packing to the named provider; the provider owns its stable encoding and arithmetic semantics. Compiler rendering and operation lowering use xls_type in the compiler application.
""".
%% Application defaults and explicit type assertion.
-export([zero/0, zero/1, as/2]).

%% Descriptor analysis and host codecs.
-export([
    descriptor/1, providers/1, width/1, value_width/1, normalize/2, pack/2, pack_exact/2, unpack/2
]).
%% Shared type contracts.
-export_type([descriptor/0, arg/0]).

%%%
%%% Structure for shared type descriptors
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
-doc "A literal, nested type, or named record field supplied to a type constructor.".
-type arg() :: integer() | atom() | descriptor() | {atom(), descriptor()}.

%%%
%%% hls_type behavior
%%%

-doc """
Packs a value into a bitstring of exactly the bit width returned by `width/2`.
Each provider defines its accepted domain and normalization policy. Every
successful pack must unpack completely and repack to identical bits; repeated
normalization must preserve the decoded value. Reject invalid shapes and values
outside that domain. These are codec laws, not arithmetic equivalence laws.
An existing constructor and arguments name a stable encoding contract across
code upgrades. Incompatible encodings require a distinct constructor name or
version argument; provider availability and width checks cannot establish
semantic compatibility.
""".
-callback pack(Value :: any(), atom(), [any()]) -> bitstring().

-doc """
Unpacks a value previously processed by pack/2.  This is usually a sub-call of
an `hls_gs` instance's `unpack/2`.
""".
-callback unpack(Packed :: bitstring(), atom(), [any()]) -> {Value :: any(), Rest :: bitstring()}.

-doc "Builds an empty Erlang instance of this type.".
-callback zero(TypeName :: atom(), Args :: [arg()]) -> any().

-doc "Serialized bit width, including padding; pack/3 must return this many bits.".
-callback width(Name :: atom(), Args :: [any()]) -> integer().

-doc "Logical value width, excluding wire padding. Defaults to width/2.".
-callback value_width(Name :: atom(), Args :: [arg()]) -> non_neg_integer().
-optional_callbacks([value_width/2]).

%%%
%%% Descriptor-level versions which dispatch on Module
%%%

-doc "Returns the sorted unique providers named by a descriptor and its nested arguments, including internal record fields. This structural inventory does not invoke provider callbacks or inspect helper implementations.".
-spec providers(descriptor()) -> [module()].
providers(Type = #hls_type{}) -> lists:usort(provider_modules(Type)).

%% Descriptor arguments contain literals, nested types or named record fields.
-spec provider_modules(arg() | [arg()]) -> [module()].
provider_modules(#hls_type{module = Module, args = Args}) ->
    [Module | provider_modules(Args)];
provider_modules({_Field, Type}) ->
    provider_modules(Type);
provider_modules(Args) when is_list(Args) ->
    lists:append([provider_modules(Arg) || Arg <- Args]);
provider_modules(_Literal) ->
    [].

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
        _Invalid ->
            error({invalid_packed_value, Descriptor})
    end.

-doc """
Returns the host value obtained by packing and unpacking at the declared type.
This exposes wire rounding without introducing a new live-value representation.
It works recursively for collections and is a host-only operation. Numeric
integer providers reject overflow; serial counter providers normalize by wrapping.
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

%%%
%%%
%%%

-spec descriptor(erl_parse:abstract_type()) -> arg().
-doc "Converts a remote type expression or literal parameter to its provider descriptor or value.".
descriptor({remote_type, _1, [{atom, _2, Module}, {atom, _3, Name}, Args]}) ->
    {hls_type, Module, Name, [descriptor(Arg) || Arg <- Args]};
descriptor({hls_record_type, _Line, Descriptor}) ->
    Descriptor;
descriptor({integer, _1, Integer}) ->
    Integer;
descriptor({atom, _1, Atom}) ->
    Atom.
