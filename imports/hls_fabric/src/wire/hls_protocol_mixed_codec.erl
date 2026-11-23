-module(hls_protocol_mixed_codec).
-moduledoc """
The mixed stream checks retained providers here before registration; its queue uses the same module to select canonical record classes. hls_protocol_mixed owns build-time source/placement derivation.

Runtime validation and canonical frame codecs for retained BEAM/native crossings. No source compilation, topology derivation or hardware emission occurs here. Record descriptors use current compatible providers, independently of actor-module reloads.
""".

%% Pre-session availability and individual crossing encodings have no transport effects.
%% Pre-session provider checks.
-export([check/1]).
%% Crossing record conversion.
-export([encode/2, encode/3, decode/3]).

-doc "Checks current host, crossing and application codec availability and retained widths before startup admission or transport registration. The descriptor is trusted build output. These structural checks do not establish encoding compatibility or coordinate code upgrades; BEAM actor execution remains application-managed.".
-spec check(hls_protocol_mixed_schema:binding()) -> ok.
check(#{actors := Actors, mixed := #{links := Links}, application := Application}) ->
    maps:foreach(fun(_, #{schemas := Schemas}) -> hls_host_codec:check(Schemas) end, Actors),
    lists:foreach(
        fun(#{classes := Classes}) ->
            lists:foreach(
                fun(#{source_record := Source, destination_record := Destination}) ->
                    ok = hls_record_codec:check(Source),
                    ok = hls_record_codec:check(Destination)
                end,
                Classes
            )
        end,
        Links
    ),
    hls_partition_wire:check(Application).

-doc "Selects exactly one canonical source-bound crossing for an ordinary record without a port hint. Packs the record once, then checks same-tag classes including omitted constants. Rejects malformed records, missing or ambiguous classes; retained codec errors propagate unchanged. Sender authentication and queue admission belong to the owner.".
-spec encode(hls_protocol_mixed_schema:encoder_link(), tuple()) -> {byte(), non_neg_integer()}.
encode(#{classes := Classes}, Message) when is_tuple(Message), tuple_size(Message) > 0 ->
    Tag = element(1, Message),
    Matching = [Class || Class = #{tag := Name} <- Classes, Name =:= Tag],
    case Matching of
        [] ->
            error({no_protocol_class, Tag});
        [#{source_record := Record} | _] ->
            Packed = hls_record_codec:pack(Record, Message),
            Candidates = lists:usort(
                lists:append([canonical_candidate(Class, Packed) || Class <- Matching])
            ),
            case Candidates of
                [Candidate] -> Candidate;
                [] -> error({no_protocol_class, Tag});
                _ -> error({ambiguous_protocol_classes, Tag, [Slot || {Slot, _} <- Candidates]})
            end
    end;
encode(_, Message) ->
    error({invalid_protocol_message, Message}).

%% Only the codec's deliberate canonical-frame rejection excludes a class; internal errors propagate.
-spec canonical_candidate(hls_protocol_mixed_schema:class(), bitstring()) ->
    [{byte(), non_neg_integer()}].
canonical_candidate(Class = #{slot := Slot, codec := Codec}, Packed) ->
    Frame = ordinary_frame(Class, Packed),
    case hls_protocol_codec:encode(Codec, Frame) of
        {ok, _} -> [{Slot, Frame}];
        {error, invalid_frame} -> []
    end.

-doc "Encodes an ordinary source output for exactly one crossing class. Uses the destination operation selector and checks omitted constants, reserved bits and padding. Sender PID authentication, queue capacity and sequence reservation belong to the owner.".
-spec encode(hls_protocol_mixed_schema:encoder_link(), atom(), tuple()) ->
    {byte(), non_neg_integer()}.
encode(#{classes := Classes}, Port, Message) ->
    Tag = element(1, Message),
    [Class = #{slot := Slot, codec := Codec, source_record := Record}] =
        [C || C = #{port := P, tag := T} <- Classes, P =:= Port, T =:= Tag],
    Frame = ordinary_frame(Class, hls_record_codec:pack(Record, Message)),
    {ok, _} = hls_protocol_codec:encode(Codec, Frame),
    {Slot, Frame}.

%% The destination fixes the ordinary header while the source contributes the exact record bitstream.
-spec ordinary_frame(hls_protocol_mixed_schema:class(), bitstring()) -> non_neg_integer().
ordinary_frame(
    #{codec := #{value := Value, frame_layout := Layout}, message_bits := Width}, Packed
) ->
    Width = bit_size(Packed),
    hls_frame_layout:pack_integer(Layout, (Value bsr 24) band 255, Packed).

-doc "Checks a canonical crossing frame and decodes its bound destination record, including a packed round trip. Caller authenticates the link/session and must acknowledge only after actual destination admission; failure is never permission to replay.".
-spec decode(hls_protocol_mixed_schema:decoder_link(), byte(), non_neg_integer()) -> tuple().
decode(#{classes := Classes}, Slot, Frame) ->
    [#{destination_record := Record, codec := Codec, message_bits := Width}] =
        [C || C = #{slot := I} <- Classes, I =:= Slot],
    {ok, _} = hls_protocol_codec:encode(Codec, Frame),
    {_, Payload} = hls_frame_layout:unpack_integer(maps:get(frame_layout, Codec), Frame),
    <<Packed:Width/bitstring, _/bitstring>> = Payload,
    {Message, <<>>} = hls_record_codec:unpack(Record, Packed),
    Packed = hls_record_codec:pack(Record, Message),
    Message.
