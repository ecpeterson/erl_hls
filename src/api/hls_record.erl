-module(hls_record).
-moduledoc false.

-export([zero/2, width/2, value_width/2, pack/3, unpack/3, print_type/2, dslx_codec/2]).
-export_type([fields/0]).

-doc "Ordered field names and concrete types of an internal record value.".
-type fields() :: [{atom(), hls_type:descriptor()}].

-doc "Returns the record whose fields contain their type-directed zero values.".
-spec zero(atom(), fields()) -> tuple().
zero(Name, Fields) -> list_to_tuple([Name | [hls_type:zero(T) || {_, T} <- Fields]]).

-doc "Returns the serialized width, without a record tag.".
-spec width(atom(), fields()) -> non_neg_integer().
width(_Name, Fields) -> lists:sum([hls_type:width(T) || {_, T} <- Fields]).

-doc "Returns the logical width, excluding field padding and record tags.".
-spec value_width(atom(), fields()) -> non_neg_integer().
value_width(_Name, Fields) -> lists:sum([hls_type:value_width(T) || {_, T} <- Fields]).

-doc "Packs exactly the declared record shape in field order, without its tag.".
-spec pack(term(), atom(), fields()) -> bitstring().
pack(Value, Name, Fields) when is_tuple(Value), tuple_size(Value) =:= length(Fields) + 1,
        element(1, Value) =:= Name ->
    list_to_bitstring([hls_type:pack(V, T) || {V, {_, T}} <-
        lists:zip(tl(tuple_to_list(Value)), Fields)]);
pack(Value, Name, _Fields) -> error({invalid_hls_record_value, Name, Value}).

-doc "Decodes the declared fields and restores the Erlang record tag.".
-spec unpack(bitstring(), atom(), fields()) -> {tuple(), bitstring()}.
unpack(Bits, Name, Fields) ->
    {Values, Rest} = lists:mapfoldl(fun({_, T}, Remaining) ->
        hls_type:unpack(Remaining, T)
    end, Bits, Fields),
    {list_to_tuple([Name | Values]), Rest}.

-doc "Names the ordinary DSLX struct used for this record value.".
-spec print_type(atom(), fields()) -> string().
print_type(Name, _Fields) -> xls_names:record_type(Name).

-doc "Uses the record's generated field-wise codecs, preserving nested padding.".
-spec dslx_codec(atom(), fields()) ->
    {fun((xls_parse:printable()) -> iolist()), fun((xls_parse:printable()) -> iolist())}.
dslx_codec(Name, _Fields) ->
    Codec = xls_names:record_codec(Name),
    {fun(Bits) -> [Codec, "_from_bits(", Bits, ")"] end,
     fun(Value) -> ["bits_from_", Codec, "(", Value, ")"] end}.
