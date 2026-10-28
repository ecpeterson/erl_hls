-module(xls_entry_storage).
-moduledoc "Plans lossless packed storage for already evaluated entry-effect fields. xls_statem_entry records conservative value provenance; xls_statem_lower and xls_actor_codegen use the resulting layouts to encode and reconstruct ordered messages. Sharing and known bits never authorize removing source evaluation or its failures.".
%% Track evaluated field identity during entry normalization.
-export([identity/0, origin/2]).
%% Plan and inspect the retained effect representation.
-export([plan/2, width/1]).
%% Lower effect storage and reconstruction to deferred DSLX.
-export([encode/2, decode/2]).

%% Provenance establishes equality and fixed bits of already evaluated fields.
%% Fresh identities deliberately distinguish unsupported expressions and scopes.
-type origin() ::
    zero
    | {value, reference()}
    | {constant, integer() | float() | atom()}
    | {record, atom() | {value, atom()}, origin(), #{atom() => origin()}}
    | {field, origin(), atom() | {value, atom()}, atom()}
    | {known, reference(), xls_known_bits:bound()}.
%% A layout stores each distinct field once and reconstructs ordered messages.
%% TODO(XLS sum types): native variants could replace the selector/raw-bit envelope;
%% retain field sharing, bounded alternatives and ordered message reconstruction.
-type plan() :: #{bits := non_neg_integer(), stores := [map()], effects := [map()]}.

-doc "Creates a distinct identity for one evaluated value; identities never enter generated code.".
-spec identity() -> origin().
identity() -> {value, make_ref()}.

-doc "Tracks aliases, fields, literals and integer bitwise facts. Unsupported expressions receive distinct identities; no evaluation may be erased from this provenance.".
-spec origin(term(), map()) -> origin().
origin({var, _, Name}, Bindings) ->
    case maps:find(Name, Bindings) of
        {ok, {value, Value}} -> Value;
        {ok, {record, _Tag, Value}} -> Value;
        _ -> identity()
    end;
origin({xls_typed_integer, _, _Type, Value}, _Bindings) ->
    {constant, Value};
origin({integer, _, Value}, _Bindings) ->
    {constant, Value};
origin({float, _, Value}, _Bindings) ->
    {constant, Value};
origin({atom, _, Value}, _Bindings) ->
    {constant, Value};
origin({op, _, '-', {integer, _, Value}}, _Bindings) ->
    {constant, -Value};
origin({op, _, 'bnot', Operand}, Bindings) ->
    {known, make_ref(), xls_known_bits:invert(known(origin(Operand, Bindings)))};
origin({op, _, Op, Left, Right}, Bindings) when Op =:= 'band'; Op =:= 'bor'; Op =:= 'bxor' ->
    {known, make_ref(),
        xls_known_bits:combine(
            Op,
            known(origin(Left, Bindings)),
            known(origin(Right, Bindings))
        )};
origin({record, _, Tag, Fields}, Bindings) ->
    {record, Tag, zero, fields(Fields, Bindings)};
origin({record, _, Base, Tag, Fields}, Bindings) ->
    {record, Tag, origin(Base, Bindings), fields(Fields, Bindings)};
origin({record_field, _, Base, Tag, {atom, _, Name}}, Bindings) ->
    field(origin(Base, Bindings), Tag, Name);
origin(_Expression, _Bindings) ->
    identity().

%% Only integer facts participate in bitwise reasoning; other origins stay opaque.
-spec known(origin()) -> xls_known_bits:bound().
known(zero) -> xls_known_bits:literal(0);
known({constant, Value}) when is_integer(Value) -> xls_known_bits:literal(Value);
known({known, _Identity, Bound}) -> Bound;
known(_Origin) -> xls_known_bits:unknown().

%% Record updates retain the identity of every untouched field.
-spec fields([tuple()], map()) -> map().
fields(Fields, Bindings) ->
    maps:from_list([
        {Name, origin(Value, Bindings)}
     || {record_field, _, {atom, _, Name}, Value} <- Fields
    ]).

%% An omitted constructor field is the validated type-directed zero default.
-spec field(origin(), term(), atom()) -> origin().
field({record, Tag, Base, Fields}, Tag, Name) ->
    case maps:find(Name, Fields) of
        {ok, Value} -> Value;
        error -> field(Base, Tag, Name)
    end;
field(zero, _Tag, _Name) ->
    zero;
field(Base, Tag, Name) ->
    {field, Base, Tag, Name}.

-doc "Plans lossless storage for evaluated messages using their resolved record declarations.".
-spec plan([map()], [hls_source:record_declaration()]) -> plan().
plan(Actions, Records) ->
    Index = maps:from_list([{Name, Fs} || {attribute, _, record, {Name, Fs}} <- Records]),
    {Effects, {Bits, _Seen, Stores}} = lists:mapfoldl(
        fun({N, Action = #{tag := Tag}}, State) ->
            Root = maps:get(origin, Action, identity()),
            {Fields, Next} = lists:mapfoldl(
                fun({typed_record_field, F, T}, Acc) ->
                    Name = hls_records:field_name(F),
                    Type = hls_type:descriptor(T),
                    pack_field(N, Name, Type, field(Root, Tag, Name), Acc)
                end,
                State,
                maps:get(Tag, Index)
            ),
            {(maps:without([origin], Action))#{fields => Fields}, Next}
        end,
        {0, #{}, []},
        lists:enumerate(0, Actions)
    ),
    #{bits => Bits, stores => lists:reverse(Stores), effects => Effects}.

%% Type participates in the key: equal source values may use different encodings.
-spec pack_field(non_neg_integer(), atom(), hls_type:descriptor(), origin(), tuple()) ->
    {map(), tuple()}.
pack_field(Index, Name, Type, Origin, {Offset, Seen, Stores} = State) ->
    Field = maps:merge(#{name => Name, type => Type}, representation(Origin, Type)),
    Bits = stored_width(Field),
    case Bits of
        0 ->
            {Field, State};
        _ ->
            Key = {Type, Origin},
            case maps:find(Key, Seen) of
                {ok, Existing} ->
                    {Field#{offset => Existing}, State};
                error ->
                    Store = Field#{index => Index, offset => Offset},
                    {
                        Field#{offset => Offset},
                        {Offset + Bits, Seen#{Key => Offset}, [Store | Stores]}
                    }
            end
    end.

%% Numeric masks apply only to built-in integers; other codecs retain whole fields.
-spec representation(origin(), hls_type:descriptor()) -> map().
representation(Origin, Type) ->
    case constant(Origin, Type) of
        {ok, Value} ->
            #{constant => Value};
        error ->
            case xls_known_bits:for_type(known(Origin), Type) of
                #{mask := 0} ->
                    #{};
                Bound = #{mask := Mask} ->
                    #{known => Bound, slices => slices(Mask, hls_type:width(Type), 0)}
            end
    end.

%% Coalesce contiguous unknown bits into static wiring slices, low bits first.
-spec slices(non_neg_integer(), non_neg_integer(), non_neg_integer()) ->
    [{non_neg_integer(), pos_integer()}].
slices(_Mask, Width, Width) ->
    [];
slices(Mask, Width, Start) when (Mask bsr Start) band 1 =:= 1 ->
    slices(Mask, Width, Start + 1);
slices(Mask, Width, Start) ->
    End = slice_end(Mask, Width, Start + 1),
    [{Start, End - Start} | slices(Mask, Width, End)].

%% Stop at the first fixed bit or the field boundary.
-spec slice_end(non_neg_integer(), non_neg_integer(), non_neg_integer()) -> non_neg_integer().
slice_end(_Mask, Width, Width) -> Width;
slice_end(Mask, Width, Bit) when (Mask bsr Bit) band 1 =:= 0 -> slice_end(Mask, Width, Bit + 1);
slice_end(_Mask, _Width, Bit) -> Bit.

%% Reconstructed constants need no payload; partially known fields store only slices.
-spec stored_width(map()) -> non_neg_integer().
stored_width(#{constant := _}) -> 0;
stored_width(#{slices := Slices}) -> lists:sum([Size || {_, Size} <- Slices]);
stored_width(#{type := Type}) -> hls_type:width(Type).

%% Constants are serialized by the same host codec used by the public ABI.
-spec constant(origin(), hls_type:descriptor()) -> {ok, bitstring()} | error.
constant(zero, Type) ->
    {ok, hls_type:pack(hls_type:zero(Type), Type)};
constant({constant, Value}, Type) ->
    try
        {ok, hls_type:pack(Value, Type)}
    catch
        error:_ -> error
    end;
constant(_Origin, _Type) ->
    error.

-doc "Returns the number of stored payload bits, excluding the layout selector.".
-spec width(plan()) -> non_neg_integer().
width(#{bits := Bits}) -> Bits.

-doc "Builds packed selected-field wiring without rendering or reevaluating any message expression.".
-spec encode(plan(), pos_integer()) -> xls_dslx:expr().
encode(#{stores := Stores}, Width) ->
    lists:foldl(
        fun(Store = #{index := Index, name := Name, type := Type, offset := Offset}, Acc) ->
            Actions = xls_dslx:field(xls_dslx:ref("evaluated"), 2),
            Message = xls_dslx:field(xls_dslx:field(Actions, Index), 1),
            Value = xls_dslx:field(Message, atom_to_list(Name)),
            Raw = hls_type:dslx_to_bits(Type, Value),
            case Store of
                #{slices := Slices} ->
                    {Packed, _} = lists:foldl(
                        fun({Start, Size}, {Bits, At}) ->
                            {pack_update(Bits, At, xls_dslx:slice(Raw, Start, Size)), At + Size}
                        end,
                        {Acc, Offset},
                        Slices
                    ),
                    Packed;
                _ ->
                    pack_update(Acc, Offset, Raw)
            end
        end,
        xls_dslx:call("zero!<bits[" ++ integer_to_list(Width) ++ "]>", []),
        Stores
    ).

%% Offsets retain the same numeric low-bit-first packing order as decode/2.
-spec pack_update(xls_dslx:expr(), non_neg_integer(), xls_clause_lower:printable()) ->
    xls_dslx:expr().
pack_update(Value, Offset, Bits) ->
    xls_dslx:call("bit_slice_update", [Value, xls_dslx:literal("u32", Offset), Bits]).

-doc "Reconstructs one ordered message and its original routed output port.".
-spec decode(map(), non_neg_integer()) -> xls_dslx:value().
decode(#{tag := Tag, port := Port, fields := Fields}, Index) ->
    [
        "      u8:",
        integer_to_list(Index),
        " => Egress {\n",
        "        port: OutputPort::",
        xls_names:enum_member(Port),
        ",\n",
        "        frame: axis::pack(Tag::",
        xls_names:enum_member(Tag),
        " as u8,\n",
        "          hls_bits::frame_payload(bits_from_",
        xls_names:record_codec(Tag),
        "(",
        xls_names:record_type(Tag),
        " {\n",
        [
            ["            ", atom_to_list(maps:get(name, F)), ": ", decode_field(F), ",\n"]
         || F <- Fields
        ],
        "          }))),\n      },\n"
    ].

%% Stored values retain the type codec's exact bit layout, including nested records.
-spec decode_field(map()) -> xls_dslx:value().
decode_field(#{type := Type, constant := Bits}) ->
    Width = bit_size(Bits),
    Raw =
        case Width of
            0 ->
                0;
            _ ->
                <<Value:Width>> = Bits,
                Value
        end,
    hls_type:dslx_from_bits(Type, [
        "hls_bits::from_stream(uN[",
        integer_to_list(Width),
        "]:",
        integer_to_list(Raw),
        ")"
    ]);
decode_field(#{type := Type, known := #{value := Value}, slices := Slices} = Field) ->
    Zero = ["uN[", integer_to_list(hls_type:width(Type)), "]:", integer_to_list(Value)],
    {Raw, _} = lists:foldl(
        fun({Start, Size}, {Bits, At}) ->
            {update(Bits, Start, slice("effects.payloads", At, Size)), At + Size}
        end,
        {Zero, maps:get(offset, Field, 0)},
        Slices
    ),
    hls_type:dslx_from_bits(Type, ["(", Raw, ")"]);
decode_field(#{type := Type, offset := Offset}) ->
    hls_type:dslx_from_bits(Type, [
        "effects.payloads[",
        integer_to_list(Offset),
        ":",
        integer_to_list(Offset + hls_type:width(Type)),
        "]"
    ]).

%% Static slices and updates express wiring without variable shifts or selectors.
-spec slice(xls_dslx:value(), non_neg_integer(), pos_integer()) -> xls_dslx:value().
slice(Value, Start, Size) ->
    [Value, "[", integer_to_list(Start), ":", integer_to_list(Start + Size), "]"].

%% Offsets are compile-time constants in the packed payload's numeric bit order.
-spec update(xls_dslx:value(), non_neg_integer(), xls_dslx:value()) -> xls_dslx:value().
update(Value, Offset, Bits) ->
    ["bit_slice_update(", Value, ", u32:", integer_to_list(Offset), ", ", Bits, ")"].
