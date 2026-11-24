-module(hls_frame_layout).
-moduledoc """
Canonical ordinary actor-frame schema shared by source admission, generated support and host codecs. Build callers select a checked payload capacity; hls_compile uses xls_frame_layout:config/1 to publish it. Physical streams retain provider packing order, while numeric frames use the existing little-endian conversion. Debug and bridge envelopes choose separate layouts.
""".
%% Layout construction and field queries.
-export([
    new/1,
    default/0,
    payload_words/1,
    payload_bits/1,
    frame_bits/1,
    word_bits/0,
    header_bits/0,
    header_fields/0,
    header_offset/1,
    descriptor/1,
    bounds/4
]).

%% Canonical host framing and capacity checks.
-export([
    check_payload/2,
    pack_header/1,
    unpack_header/1,
    pack/3,
    unpack/2,
    pack_integer/3,
    unpack_integer/2
]).

%% Shared type contracts.
-export_type([words/0, layout/0, descriptor/0, header/0, header_input/0]).

-doc "Ordinary payload capacity in complete transport words; the header length is eight bits.".
-type words() :: 1..((1 bsl 8) - 1).

-doc "Checked ordinary-frame capacity. Construct with new/1 or default/0 and use accessors.".
-opaque layout() :: #{payload_words := words()}.

-doc "Serializable identity of a selected canonical actor-frame layout; widths include serialized padding.".
-type descriptor() :: #{
    name := canonical_actor_v1,
    header_bits := pos_integer(),
    payload_words := words(),
    payload_bits := pos_integer(),
    frame_bits := pos_integer(),
    parameterized := true
}.

-doc "Canonical header fields in physical byte order. Payload length counts complete 32-bit words.".
-type header() :: #{
    payload_words := hls_nums:u8(),
    txid := hls_nums:u8(),
    flags := hls_nums:u8(),
    op := hls_nums:u8()
}.

-doc "Header fields accepted by payload packing; any supplied payload length is replaced by the derived word count.".
-type header_input() :: #{
    op := hls_nums:u8(),
    txid := hls_nums:u8(),
    flags := hls_nums:u8(),
    payload_words => hls_nums:u8()
}.

-doc "Validates a public capacity option; rejects nonintegers and capacities outside 1..255 words.".
-spec new(term()) -> layout().
new(Words) when is_integer(Words), Words >= 1, Words < (1 bsl 8) ->
    #{payload_words => Words};
new(Words) ->
    hls_diagnostic:raise(
        frame_layout,
        invalid_frame_payload_words,
        <<"Ordinary frame payload capacity must be an integer from 1 to 255 words">>,
        #{option => frame_payload_words, value => Words, min => 1, max => 255}
    ).

-doc "Returns the established three-word ordinary actor capacity.".
-spec default() -> layout().
default() -> new(3).

-doc "Returns the checked maximum ordinary payload word count.".
-spec payload_words(layout()) -> words().
payload_words(#{payload_words := Words}) -> Words.

-doc "Returns the transport word width, independent of payload capacity.".
-spec word_bits() -> 32.
word_bits() -> 32.

-doc "Returns serialized payload storage width, including unused capacity.".
-spec payload_bits(layout()) -> pos_integer().
payload_bits(Layout) -> payload_words(Layout) * word_bits().

-doc "Returns the complete fixed-width ordinary frame representation.".
-spec frame_bits(layout()) -> pos_integer().
frame_bits(Layout) -> header_bits() + payload_bits(Layout).

-doc "Returns the ordered typed header fields, from the lowest numeric byte to the highest.".
-spec header_fields() -> hls_record:fields().
header_fields() -> [{Name, hls_nums:u8()} || Name <- [payload_words, txid, flags, op]].

%% The record provider supplies the same physical host stream as the DSLX lsb schema.
-spec header_type() -> hls_type:descriptor().
header_type() -> {hls_type, hls_record, header, header_fields()}.

-doc "Returns the serialized header width derived from its typed fields.".
-spec header_bits() -> pos_integer().
header_bits() -> hls_type:width(header_type()).

-doc "Returns one header field's numeric least-significant-bit offset; rejects unknown names.".
-spec header_offset(payload_words | txid | flags | op) -> non_neg_integer().
header_offset(Name) ->
    #{fields := Fields} = hls_field_layout:layout(header_fields(), lsb),
    [Offset] = [Prefix || #{name := Field, prefix := Prefix} <- Fields, Field =:= Name],
    Offset.

-doc "Returns the selected layout's serializable profile without exposing its internal representation.".
-spec descriptor(layout()) -> descriptor().
descriptor(Layout) ->
    #{
        name => canonical_actor_v1,
        header_bits => header_bits(),
        payload_words => payload_words(Layout),
        payload_bits => payload_bits(Layout),
        frame_bits => frame_bits(Layout),
        parameterized => true
    }.

-doc "Checks a serialized payload width and returns its rounded transport length. Empty payloads use zero words; over-capacity payloads fail before truncation.".
-spec check_payload(layout(), non_neg_integer()) -> hls_nums:u8().
check_payload(Layout, Bits) when Bits >= 0 ->
    Capacity = payload_bits(Layout),
    case Bits =< Capacity of
        true -> (Bits + word_bits() - 1) div word_bits();
        false -> error({frame_payload_too_wide, Bits, Capacity})
    end.

-doc "Packs the four checked header bytes using the shared record provider; every field must fit u8.".
-spec pack_header(header()) -> binary().
pack_header(#{payload_words := Words, txid := Txid, flags := Flags, op := Op}) ->
    hls_type:pack({header, Words, Txid, Flags, Op}, header_type()).

-doc "Decodes exactly one canonical header stream; rejects other widths.".
-spec unpack_header(binary()) -> header().
unpack_header(Packed) ->
    {{header, Words, Txid, Flags, Op}, <<>>} = hls_type:unpack(Packed, header_type()),
    #{payload_words => Words, txid => Txid, flags => Flags, op => Op}.

-doc "Packs a checked payload to the layout's complete physical stream. An operation byte supplies zero transaction/flag fields; a header map preserves them. Payload length is derived, replacing any supplied length; all unused bits are zero.".
-spec pack(layout(), hls_nums:u8() | header_input(), bitstring()) -> binary().
pack(Layout, Op, Payload) when is_integer(Op) ->
    pack(Layout, #{op => Op, txid => 0, flags => 0}, Payload);
pack(Layout, Header, Payload) ->
    Words = check_payload(Layout, bit_size(Payload)),
    PackedHeader = pack_header(Header#{payload_words => Words}),
    PackedPayload = hls_codec:pad_to(Payload, payload_bits(Layout)),
    <<PackedHeader/binary, PackedPayload/bitstring>>.

-doc "Decodes exactly one complete physical frame, validating the declared length against the selected capacity. Returns only the declared word-aligned payload; nonzero unused storage bits are rejected.".
-spec unpack(layout(), binary()) -> {header(), binary()}.
unpack(Layout, Packed) ->
    Width = frame_bits(Layout),
    Width = bit_size(Packed),
    HeaderBits = header_bits(),
    <<RawHeader:HeaderBits/bitstring, Payload/binary>> = Packed,
    Header = #{payload_words := Words} = unpack_header(RawHeader),
    _ = check_payload(Layout, Words * word_bits()),
    Bytes = Words * word_bits() div 8,
    <<Actual:Bytes/binary, Padding/binary>> = Payload,
    case hls_codec:unsigned(Padding) of
        0 -> ok;
        _ -> error(nonzero_frame_padding)
    end,
    {Header, Actual}.

-doc "Returns axis::bits_from_frame's numeric representation of pack/3 with the same capacity and field checks.".
-spec pack_integer(layout(), hls_nums:u8() | header_input(), bitstring()) -> non_neg_integer().
pack_integer(Layout, Header, Payload) -> hls_codec:unsigned(pack(Layout, Header, Payload)).

-doc "Decodes a nonnegative numeric frame fitting the selected fixed width, with the same length checks as unpack/2.".
-spec unpack_integer(layout(), non_neg_integer()) -> {header(), binary()}.
unpack_integer(Layout, Frame) ->
    Width = frame_bits(Layout),
    Checked = hls_codec:checked_integer(Frame, Width, unsigned),
    unpack(Layout, <<Checked:Width/little>>).

-doc "Constructs an ordinary emitted-frame numeric mask/value from equal-length physical payload streams. Header and zero padding are known; unknown value bits are cleared. This is a conditional value bound, not receiver acceptance.".
-spec bounds(layout(), hls_nums:u8(), bitstring(), bitstring()) ->
    #{mask := non_neg_integer(), value := non_neg_integer()}.
bounds(Layout, Op, MaskStream, ValueStream) ->
    Width = bit_size(MaskStream),
    Width = bit_size(ValueStream),
    _ = check_payload(Layout, Width),
    Padding = payload_bits(Layout) - Width,
    MaskHeader = pack_header(#{payload_words => 255, txid => 255, flags => 255, op => 255}),
    Mask = hls_codec:unsigned(
        <<MaskHeader/binary, MaskStream/bitstring, ((1 bsl Padding) - 1):Padding>>
    ),
    Value = pack_integer(Layout, Op, ValueStream),
    #{mask => Mask, value => Value band Mask}.
