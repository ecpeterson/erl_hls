-module(hls_record).
-moduledoc """
Record type provider used by hls_type and hls_record_codec after hls_records resolves ordered field descriptors. Delegates each field to its own provider for host packing; it neither reads actor source nor assigns message selectors.
""".

%% hls_type record-provider callbacks.
-export([zero/2, width/2, value_width/2, pack/3, unpack/3]).
%% Shared type contracts.
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
pack(Value, Name, Fields) when
    is_tuple(Value),
    tuple_size(Value) =:= length(Fields) + 1,
    element(1, Value) =:= Name
->
    list_to_bitstring([
        hls_type:pack(V, T)
     || {V, {_, T}} <-
            lists:zip(tl(tuple_to_list(Value)), Fields)
    ]);
pack(Value, Name, _Fields) ->
    error({invalid_hls_record_value, Name, Value}).

-doc "Decodes the declared fields and restores the Erlang record tag.".
-spec unpack(bitstring(), atom(), fields()) -> {tuple(), bitstring()}.
unpack(Bits, Name, Fields) ->
    {Values, Rest} = lists:mapfoldl(
        fun({_, T}, Remaining) ->
            hls_type:unpack(Remaining, T)
        end,
        Bits,
        Fields
    ),
    {list_to_tuple([Name | Values]), Rest}.
