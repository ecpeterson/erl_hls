-module(hls_protocol_envelope).
-moduledoc """
Host framing helpers and xls_protocol_envelope share these canonical packet/rectangle field schemas. Session owners retain semantic admission; the XLS module alone emits hardware syntax.

Runtime wire schemas and packing for fixed packet and rectangle envelopes. Semantic admission, sessions and ownership remain with callers; xls_protocol_envelope separately renders these same schemas.
""".
%% The schema is shared with hardware rendering; these operations perform no lowering.
%% Canonical wire field layouts.
-export([fields/1]).
%% Host packet and rectangle packing.
-export([pack_packet/1, unpack_packet/1, pack_rectangle/2]).

-doc "Returns byte-aligned unsigned fields in low-byte-first wire order. The same order feeds hls_record host packing and least-significant-field DSLX packing; packet and rectangle retain their fixed transport ABIs.".
-spec fields(packet | rectangle) -> hls_record:fields().
fields(packet) ->
    [
        {frame, hls_nums:uN(128)},
        {slot, hls_nums:u8()},
        {link, hls_nums:u16()},
        {sequence, hls_nums:u32()},
        {session, hls_nums:u64()},
        {kind, hls_nums:u8()}
    ];
fields(rectangle) ->
    [
        {x0, hls_nums:u16()},
        {y0, hls_nums:u16()},
        {x1, hls_nums:u16()},
        {y1, hls_nums:u16()},
        {target, hls_nums:u32()},
        {header, hls_nums:u32()},
        {payload, hls_nums:uN(96)}
    ].

-doc "Packs all packet fields, rejecting missing fields and unsigned overflow. Extra map keys are ignored. Kind, nonzero session, sequence exhaustion and ACK payload checks belong to the bridge owner.".
-spec pack_packet(map()) -> binary().
pack_packet(Packet) -> pack(packet, Packet).

-doc "Unpacks exactly one packet, rejecting short or trailing input. Returns every schema field without interpreting kind, session, sequence or payload validity.".
-spec unpack_packet(binary()) -> map().
unpack_packet(Bytes) ->
    Fields = fields(packet),
    {Record, <<>>} = hls_record:unpack(Bytes, packet, Fields),
    maps:from_list(lists:zip([Name || {Name, _} <- Fields], tl(tuple_to_list(Record)))).

-doc "Packs the full rectangle schema and sends only Words payload words, including zero words when requested. Rejects missing or overflowing fields and lengths beyond the schema payload. The caller checks bounds, target, header meaning and canonical source padding.".
-spec pack_rectangle(map(), non_neg_integer()) -> binary().
pack_rectangle(Command, Words) when Words >= 0 ->
    Fields = fields(rectangle),
    {payload, PayloadType} = lists:last(Fields),
    PayloadBits = hls_type:width(PayloadType),
    true = Words * 32 =< PayloadBits,
    PrefixBytes = (hls_record:width(rectangle, Fields) - PayloadBits) div 8,
    binary:part(pack(rectangle, Command), 0, PrefixBytes + Words * 4).

%% Host records serialize each numeric field through its existing little-endian provider.
-spec pack(packet | rectangle, map()) -> binary().
pack(Name, Values) ->
    Fields = fields(Name),
    Record = list_to_tuple([Name | [maps:get(Field, Values) || {Field, _} <- Fields]]),
    hls_record:pack(Record, Name, Fields).
