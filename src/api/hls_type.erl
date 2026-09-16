-module(hls_type).
-moduledoc """
 
""".
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
    value_width/1,
    width/1,
    zero/0,
    zero/1
]).
-compile(export_all).

%%%
%%% Structure for XLS type descriptors
%%%

-record(hls_type, {
    module,
    name,
    args
}).
-doc "". 
-type descriptor() :: #hls_type{
    module :: module(),
    name :: atom(),
    args :: [arg()]
}.
-type arg() :: integer() | descriptor().

%%%
%%% hls_type behavior
%%%

-doc """
Packs a value into a binary of exactly the bit width returned by `width/2`.
Each provider defines its accepted domain and normalization policy. Every
successful pack must unpack completely and repack to identical bytes; repeated
normalization must preserve the decoded value. Reject invalid shapes and values
outside that domain. These are codec laws, not arithmetic equivalence laws.
""".
-callback pack(Value :: any(), atom(), [any()]) -> binary().

-doc """
Unpacks a value previously processed by pack/2.  This is usually a sub-call of
an `hls_gs` instance's `unpack/2`.
""".
-callback unpack(Packed :: binary(), atom(), [any()]) -> {Value :: any(), Rest :: binary()}.

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
-doc "". 
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

transpile(as, [{phantom, type, Descriptor}, Value], _State) ->
    ["(", Value, " as ", print_type(Descriptor), ")"];
transpile(Operation, _Args, _State) when Operation =:= normalize;
        Operation =:= pack_exact ->
    error({host_only_type_operation, Operation}).

-spec width(descriptor()) -> integer().
-doc "". 
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
Packs a host value, checking the provider's binary against its declared width.
Built-in integers reject overflow and fixed-size collections require exact
lengths. Floats round to the selected IEEE binary format and reject nonfinite
results. Generated record packers use this boundary for each field, including
fields in topology startup messages. See docs/numeric-contract.md.
""".
-spec pack(term(), descriptor()) -> binary().
pack(Value, Descriptor = #hls_type{module = Module, name = Name, args = Args}) ->
    Width = width(Descriptor),
    case Module:pack(Value, Name, Args) of
        Packed when is_binary(Packed), bit_size(Packed) =:= Width -> Packed;
        Packed when is_binary(Packed) ->
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
-spec pack_exact(term(), descriptor()) -> binary().
pack_exact(Value, Descriptor) ->
    Packed = pack(Value, Descriptor),
    case unpack(Packed, Descriptor) of
        {Value, <<>>} -> Packed;
        {_Normalized, <<>>} -> error({inexact_packing, Descriptor})
    end.

unpack(Binary, {hls_type, Module, Name, Args}) ->
    Module:unpack(Binary, Name, Args).

print_type({hls_type, Module, Name, Args}) ->
    Module:print_type(Name, Args).

dslx_codec(Type = {hls_type, Module, Name, Args}) ->
    _ = code:ensure_loaded(Module),
    Codec = case erlang:function_exported(Module, dslx_codec, 2) of
        true -> Module:dslx_codec(Name, Args);
        false -> bit_cast
    end,
    case Codec =:= bit_cast andalso value_width(Type) =/= width(Type) of
        true ->
            %% Scalars can cast through padding, but arrays cannot: padding
            %% belongs to each element, not to the flattened collection.
            {fun(Bits) -> [Bits, " as ", print_type(Type)] end,
             fun(Value) -> [Value, " as bits[", integer_to_list(width(Type)), "]"] end};
        false -> Codec
    end.

dslx_from_bits(Type, Bits) ->
    case dslx_codec(Type) of
        bit_cast -> [Bits, " as ", print_type(Type)];
        {Decode, _Encode} -> Decode(Bits)
    end.

dslx_to_bits(Type, Value) ->
    case dslx_codec(Type) of
        bit_cast -> [Value, " as bits[", integer_to_list(width(Type)), "]"];
        {_Decode, Encode} -> Encode(Value)
    end.

%%%
%%% 
%%%

-spec descriptor(erl_parse:af_abstract_type()) -> descriptor().
-doc "". 
descriptor({remote_type, _1, [{atom, _2, Module}, {atom, _3, Name}, Args]}) ->
    {hls_type, Module, Name, [descriptor(Arg) || Arg <- Args]};
descriptor({integer, _1, Integer}) ->
    Integer;
descriptor({atom, _1, Atom}) ->
    Atom.
