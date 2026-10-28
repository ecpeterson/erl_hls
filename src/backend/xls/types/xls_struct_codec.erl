-module(xls_struct_codec).
-moduledoc "Generic typed DSLX struct and codec rendering over hls_type field descriptors. xls_record_codegen uses physical-stream packing; generated machine/progress layouts can choose least-significant-field packing. hls_field_layout owns field offsets; xls_type supplies compiler conversions. This renderer owns neither source records nor storage policy.".
%% Render the declaration and both directions of that same codec.
-export([declaration/2, decoder/3, encoder/3]).

-doc "Emits a public struct using provider value types. TypeName and field names must be valid compiler-owned DSLX identifiers; referenced types must already be declared or imported.".
-spec declaration(string(), hls_field_layout:layout()) -> xls_dslx:value().
declaration(TypeName, #{fields := Fields}) ->
    [
        "pub struct ",
        TypeName,
        " {\n",
        [
            ["  ", atom_to_list(Name), " : ", xls_type:print_type(Type), ",\n"]
         || #{name := Name, type := Type} <- Fields
        ],
        "}\n"
    ].

-doc "Emits a public decoder named CodecName. Stream inputs may include trailing frame padding and must be at least the layout width; lsb inputs have exactly that width. Provider decoders retain their own padding policy.".
-spec decoder(string(), string(), hls_field_layout:layout()) -> xls_dslx:value().
decoder(TypeName, CodecName, #{encoding := Encoding, width := Width, fields := Fields}) ->
    {Parameters, RawWidth, Prelude} =
        case Encoding of
            stream -> {"<N: u32>", "N", "  let stream = hls_bits::to_stream(raw);\n"};
            lsb -> {[], n(Width), []}
        end,
    [
        "pub fn ",
        CodecName,
        Parameters,
        "(raw: bits[",
        RawWidth,
        "]) -> ",
        TypeName,
        " {\n",
        Prelude,
        "  ",
        TypeName,
        " {\n",
        [
            [
                "    ",
                atom_to_list(Name),
                ": ",
                xls_type:dslx_from_bits(Type, field_bits(Encoding, Field)),
                ",\n"
            ]
         || Field = #{name := Name, type := Type} <- Fields
        ],
        "  }\n}\n"
    ].

-doc "Emits a public encoder named CodecName. Every field uses its provider's serialized representation; stream encoding preserves Erlang field order and lsb encoding places the first field at the low bits.".
-spec encoder(string(), string(), hls_field_layout:layout()) -> xls_dslx:value().
encoder(TypeName, CodecName, #{encoding := Encoding, width := Width, fields := Fields}) ->
    [
        "pub fn ",
        CodecName,
        "(s: ",
        TypeName,
        ") -> bits[",
        n(Width),
        "] {\n  ",
        packed_fields(Encoding, Fields),
        "\n}\n"
    ].

%% Convert only the selected field's physical stream before invoking its provider.
-spec field_bits(hls_field_layout:encoding(), hls_field_layout:field()) -> iodata().
field_bits(stream, #{prefix := Prefix, width := Width}) ->
    [
        "hls_bits::from_stream(stream[N - u32:",
        n(Prefix + Width),
        "+:bits[",
        n(Width),
        "]])"
    ];
field_bits(lsb, #{prefix := Prefix, width := Width}) ->
    ["raw[", n(Prefix), "+:bits[", n(Width), "]]"].

%% The empty concatenation remains a legal zero-width value in either policy.
-spec packed_fields(hls_field_layout:encoding(), [hls_field_layout:field()]) -> xls_dslx:value().
packed_fields(stream, Fields) ->
    Values = [["hls_bits::to_stream(", packed_field(Field), ")"] || Field <- Fields],
    ["hls_bits::from_stream(", lists:join(" ++ ", Values ++ ["zero!<bits[0]>()"]), ")"];
packed_fields(lsb, []) ->
    "zero!<bits[0]>()";
packed_fields(lsb, Fields) ->
    lists:join(" ++ ", [["(", packed_field(Field), ")"] || Field <- lists:reverse(Fields)]).

%% Compiler conversion belongs to xls_type, including custom fragments and padding.
-spec packed_field(hls_field_layout:field()) -> xls_dslx:value().
packed_field(#{name := Name, type := Type}) ->
    xls_type:dslx_to_bits(Type, ["s.", atom_to_list(Name)]).

%% Widths and prefixes are static decimal DSLX constants.
-spec n(non_neg_integer()) -> string().
n(Value) -> integer_to_list(Value).
