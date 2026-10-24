-module(xls_struct_codec).
-moduledoc "Typed DSLX structs with explicit physical-stream or least-significant-field packing.".
-export([layout/2, declaration/2, decoder/3, encoder/3]).
-export_type([layout/0]).

%% Stream fields follow Erlang bitstring order; lsb fields occupy ascending numeric slices.
-type encoding() :: stream | lsb.

%% Prefix counts preceding declared bits; its interpretation depends on encoding.
-type field() :: #{name := atom(), type := hls_type:descriptor(),
    prefix := non_neg_integer(), width := non_neg_integer()}.

-doc "Ordered typed fields and their cumulative serialized widths. Prefix is a physical-stream offset for stream encoding and a numeric low-bit offset for lsb encoding.".
-type layout() :: #{encoding := encoding(), width := non_neg_integer(),
    fields := [field()]}.

-doc "Derives a layout from unique compiler-checked field names and provider descriptors. Zero-width fields remain present and do not advance the prefix.".
-spec layout(hls_record:fields(), encoding()) -> layout().
layout(Fields, Encoding) when Encoding =:= stream; Encoding =:= lsb ->
    {Slots, Width} = lists:mapfoldl(fun({Name, Type}, Prefix) ->
        Bits = hls_type:width(Type),
        {#{name => Name, type => Type, prefix => Prefix, width => Bits}, Prefix + Bits}
    end, 0, Fields),
    #{encoding => Encoding, width => Width, fields => Slots}.

-doc "Emits a public struct using provider value types. TypeName and field names must be valid compiler-owned DSLX identifiers; referenced types must already be declared or imported.".
-spec declaration(string(), layout()) -> iodata().
declaration(TypeName, #{fields := Fields}) ->
    ["pub struct ", TypeName, " {\n",
        [["  ", atom_to_list(Name), " : ", hls_type:print_type(Type), ",\n"]
            || #{name := Name, type := Type} <- Fields],
        "}\n"].

-doc "Emits a public decoder named CodecName. Stream inputs may include trailing frame padding and must be at least the layout width; lsb inputs have exactly that width. Provider decoders retain their own padding policy.".
-spec decoder(string(), string(), layout()) -> iodata().
decoder(TypeName, CodecName, #{encoding := Encoding, width := Width, fields := Fields}) ->
    {Parameters, RawWidth, Prelude} = case Encoding of
        stream -> {"<N: u32>", "N", "  let stream = hls_bits::to_stream(raw);\n"};
        lsb -> {[], n(Width), []}
    end,
    ["pub fn ", CodecName, Parameters, "(raw: bits[", RawWidth, "]) -> ", TypeName, " {\n",
        Prelude, "  ", TypeName, " {\n",
        [["    ", atom_to_list(Name), ": ",
            hls_type:dslx_from_bits(Type, field_bits(Encoding, Field)), ",\n"]
            || Field = #{name := Name, type := Type} <- Fields],
        "  }\n}\n"].

-doc "Emits a public encoder named CodecName. Every field uses its provider's serialized representation; stream encoding preserves Erlang field order and lsb encoding places the first field at the low bits.".
-spec encoder(string(), string(), layout()) -> iodata().
encoder(TypeName, CodecName, #{encoding := Encoding, width := Width, fields := Fields}) ->
    ["pub fn ", CodecName, "(s: ", TypeName, ") -> bits[", n(Width), "] {\n  ",
        packed_fields(Encoding, Fields), "\n}\n"].

%% Convert only the selected field's physical stream before invoking its provider.
-spec field_bits(encoding(), field()) -> iodata().
field_bits(stream, #{prefix := Prefix, width := Width}) ->
    ["hls_bits::from_stream(stream[N - u32:", n(Prefix + Width),
        "+:bits[", n(Width), "]])"];
field_bits(lsb, #{prefix := Prefix, width := Width}) ->
    ["raw[", n(Prefix), "+:bits[", n(Width), "]]"].

%% The empty concatenation remains a legal zero-width value in either policy.
-spec packed_fields(encoding(), [field()]) -> iodata().
packed_fields(stream, Fields) ->
    Values = [["hls_bits::to_stream(", packed_field(Field), ")"] || Field <- Fields],
    ["hls_bits::from_stream(", lists:join(" ++ ", Values ++ ["zero!<bits[0]>()"]), ")"];
packed_fields(lsb, []) -> "zero!<bits[0]>()";
packed_fields(lsb, Fields) ->
    lists:join(" ++ ", [["(", packed_field(Field), ")"] || Field <- lists:reverse(Fields)]).

%% Field conversion belongs to hls_type, including custom codecs and padding.
-spec packed_field(field()) -> iodata().
packed_field(#{name := Name, type := Type}) ->
    hls_type:dslx_to_bits(Type, ["s.", atom_to_list(Name)]).

%% Widths and prefixes are static decimal DSLX constants.
-spec n(non_neg_integer()) -> string().
n(Value) -> integer_to_list(Value).
