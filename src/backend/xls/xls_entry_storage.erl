-module(xls_entry_storage).
-moduledoc false.
-export([identity/0, origin/2, plan/2, width/1, encode/2, decode/2]).

%% Provenance is used only to establish equality of already evaluated fields.
%% Fresh identities deliberately distinguish unsupported expressions and scopes.
-type origin() :: zero | {value, reference()} | {constant, integer() | float() | atom()} |
    {record, atom() | {value, atom()}, origin(), #{atom() => origin()}} |
    {field, origin(), atom() | {value, atom()}, atom()}.
%% A layout stores each distinct field once and reconstructs ordered messages.
%% TODO(XLS sum types): native variants could replace the selector/raw-bit envelope;
%% retain field sharing, bounded alternatives and ordered message reconstruction.
-type plan() :: #{bits := non_neg_integer(), stores := [map()], effects := [map()]}.

-doc "Creates a distinct identity for one evaluated value; identities never enter generated code.".
-spec identity() -> origin().
identity() -> {value, make_ref()}.

-doc "Tracks immutable aliases, record fields and literals; other expressions receive distinct identities.".
-spec origin(term(), map()) -> origin().
origin({var, _, Name}, Bindings) ->
    case maps:find(Name, Bindings) of
        {ok, {value, Value}} -> Value;
        {ok, {record, _Tag, Value}} -> Value;
        _ -> identity()
    end;
origin({xls_typed_integer, _, _Type, Value}, _Bindings) -> {constant, Value};
origin({integer, _, Value}, _Bindings) -> {constant, Value};
origin({float, _, Value}, _Bindings) -> {constant, Value};
origin({atom, _, Value}, _Bindings) -> {constant, Value};
origin({op, _, '-', {integer, _, Value}}, _Bindings) -> {constant, -Value};
origin({record, _, Tag, Fields}, Bindings) ->
    {record, Tag, zero, fields(Fields, Bindings)};
origin({record, _, Base, Tag, Fields}, Bindings) ->
    {record, Tag, origin(Base, Bindings), fields(Fields, Bindings)};
origin({record_field, _, Base, Tag, {atom, _, Name}}, Bindings) ->
    field(origin(Base, Bindings), Tag, Name);
origin(_Expression, _Bindings) -> identity().

%% Record updates retain the identity of every untouched field.
-spec fields([tuple()], map()) -> map().
fields(Fields, Bindings) -> maps:from_list([
    {Name, origin(Value, Bindings)} || {record_field, _, {atom, _, Name}, Value} <- Fields]).

%% An omitted constructor field is the validated type-directed zero default.
-spec field(origin(), term(), atom()) -> origin().
field({record, Tag, Base, Fields}, Tag, Name) ->
    case maps:find(Name, Fields) of
        {ok, Value} -> Value;
        error -> field(Base, Tag, Name)
    end;
field(zero, _Tag, _Name) -> zero;
field(Base, Tag, Name) -> {field, Base, Tag, Name}.

-doc "Plans lossless storage for evaluated messages using their resolved record declarations.".
-spec plan([map()], [hls_source:record_declaration()]) -> plan().
plan(Actions, Records) ->
    Index = maps:from_list([{Name, Fs} || {attribute, _, record, {Name, Fs}} <- Records]),
    {Effects, {Bits, _Seen, Stores}} = lists:mapfoldl(
        fun({N, Action = #{tag := Tag}}, State) ->
            Root = maps:get(origin, Action, identity()),
            {Fields, Next} = lists:mapfoldl(fun({typed_record_field, F, T}, Acc) ->
                Name = xls_parse:record_field_name(F),
                Type = hls_type:descriptor(T),
                pack_field(N, Name, Type, field(Root, Tag, Name), Acc)
            end, State, maps:get(Tag, Index)),
            {(maps:without([origin], Action))#{fields => Fields}, Next}
        end, {0, #{}, []}, lists:enumerate(0, Actions)),
    #{bits => Bits, stores => lists:reverse(Stores), effects => Effects}.

%% Type participates in the key: equal source values may use different encodings.
-spec pack_field(non_neg_integer(), atom(), hls_type:descriptor(), origin(), tuple()) -> {map(), tuple()}.
pack_field(Index, Name, Type, Origin, {Offset, Seen, Stores} = State) ->
    Field = #{name => Name, type => Type},
    case constant(Origin, Type) of
        {ok, Value} -> {Field#{constant => Value}, State};
        error ->
            Key = {Type, Origin},
            case maps:find(Key, Seen) of
                {ok, Existing} -> {Field#{offset => Existing}, State};
                error ->
                    Store = Field#{index => Index, offset => Offset},
                    {Field#{offset => Offset},
                        {Offset + hls_type:width(Type), Seen#{Key => Offset}, [Store | Stores]}}
            end
    end.

%% Constants are serialized by the same host codec used by the public ABI.
-spec constant(origin(), hls_type:descriptor()) -> {ok, bitstring()} | error.
constant(zero, Type) -> {ok, hls_type:pack(hls_type:zero(Type), Type)};
constant({constant, Value}, Type) ->
    try {ok, hls_type:pack(Value, Type)} catch error:_ -> error end;
constant(_Origin, _Type) -> error.

-doc "Returns the number of stored payload bits, excluding the layout selector.".
-spec width(plan()) -> non_neg_integer().
width(#{bits := Bits}) -> Bits.

-doc "Packs selected evaluated fields without reevaluating any message expression.".
-spec encode(plan(), pos_integer()) -> iodata().
encode(#{stores := Stores}, Width) ->
    lists:foldl(fun(#{index := Index, name := Name, type := Type, offset := Offset}, Acc) ->
        Value = ["evaluated.2.", integer_to_list(Index), ".1.", atom_to_list(Name)],
        ["bit_slice_update(", Acc, ", u32:", integer_to_list(Offset), ", ",
            hls_type:dslx_to_bits(Type, Value), ")"]
    end, ["zero!<bits[", integer_to_list(Width), "]>()"], Stores).

-doc "Reconstructs one ordered message and its original routed output port.".
-spec decode(map(), non_neg_integer()) -> iodata().
decode(#{tag := Tag, port := Port, fields := Fields}, Index) ->
    ["      u8:", integer_to_list(Index), " => Egress {\n",
        "        port: OutputPort::", xls_names:enum_member(Port), ",\n",
        "        frame: axis::pack(Tag::", xls_names:enum_member(Tag), " as u8,\n",
        "          hls_bits::frame_payload(bits_from_", xls_names:record_codec(Tag), "(",
        xls_names:record_type(Tag), " {\n",
        [["            ", atom_to_list(maps:get(name, F)), ": ", decode_field(F), ",\n"] || F <- Fields],
        "          }))),\n      },\n"].

%% Stored values retain the type codec's exact bit layout, including nested records.
-spec decode_field(map()) -> iodata().
decode_field(#{type := Type, constant := Bits}) ->
    Width = bit_size(Bits),
    Raw = case Width of 0 -> 0; _ -> <<Value:Width>> = Bits, Value end,
    hls_type:dslx_from_bits(Type, ["hls_bits::from_stream(uN[", integer_to_list(Width),
        "]:", integer_to_list(Raw), ")"]);
decode_field(#{type := Type, offset := Offset}) ->
    hls_type:dslx_from_bits(Type, ["effects.payloads[", integer_to_list(Offset), ":",
        integer_to_list(Offset + hls_type:width(Type)), "]"]).
