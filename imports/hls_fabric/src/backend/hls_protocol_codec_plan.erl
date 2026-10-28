-module(hls_protocol_codec_plan).
-moduledoc "Derives checked compact-frame permutations from source-bound field layouts. Uses the compiler's canonical header and padding analysis; runtime conversion and DSLX rendering consume the same retained hls_protocol_codec descriptor.".

%% Build-time validation and layout derivation; no output files or hardware text.
-export([plan/2, plan/3]).

%% Callers may omit field names; physical offsets and typed widths determine the wiring.
-type field() :: #{type := hls_type:descriptor(), message_bit_offset := non_neg_integer(),
    constant := bitstring(), name => atom()} |
    #{type := hls_type:descriptor(), message_bit_offset := non_neg_integer(),
      capture_bit_offset := non_neg_integer(), name => atom()}.

%% Source/channel provenance is checked by the enclosing source build.
-type channel_layout() :: #{fields := [field()], message_bits := non_neg_integer(),
    payload_bits := non_neg_integer(), frame_layout => hls_frame_layout:layout(), atom() => term()}.

-doc "Builds a bit permutation for one capture channel and its ordinary operation byte. Header, padding and source-constant fields use the shared entry ABI; dynamic fields remain exact, including partial bytes. Compact bit zero is the first dynamic physical stream bit. Rejects inconsistent capture offsets, overlapping fields or payloads wider than the selected frame. The layout comes from the channel; standalone layouts without one use the default capacity. The caller must establish source/schema/route provenance before omitting fields.".
-spec plan(channel_layout(), byte()) -> hls_protocol_codec:plan().
plan(Channel, Op) -> plan(Channel, Op, maps:get(frame_layout, Channel, hls_frame_layout:default())).

-doc "Plans a compact codec with an explicit canonical frame layout. A channel carrying layout metadata must agree with it; header and padding constraints come from the compiler schema.".
-spec plan(channel_layout(), byte(), hls_frame_layout:layout()) -> hls_protocol_codec:plan().
plan(Channel = #{fields := Fields, message_bits := MessageBits, payload_bits := PayloadBits}, Op, FrameLayout)
        when Op >= 0, Op < 256 ->
    FrameLayout = maps:get(frame_layout, Channel, FrameLayout),
    {MessageBits, PayloadBits} = lists:foldl(fun check_field/2, {0, 0}, Fields),
    Bound = xls_message_bits:frame(Op, [bound(F) || F <- Fields], FrameLayout),
    Positions = lists:append([case maps:is_key(constant, F) of
        true -> [];
        false -> [hls_frame_layout:header_bits() +
            hls_codec:stream_bit_index(hls_frame_layout:payload_bits(FrameLayout), J)
            || J <- lists:seq(maps:get(message_bit_offset, F),
                maps:get(message_bit_offset, F) + hls_type:width(maps:get(type, F)) - 1)]
    end || F <- Fields]),
    PayloadBits = length(Positions),
    Dynamic = lists:foldl(fun(J, M) -> M bor (1 bsl J) end, 0, Positions),
    true = length(lists:usort(Positions)) =:= PayloadBits,
    true = (Dynamic bxor maps:get(mask, Bound)) =:= (1 bsl hls_frame_layout:frame_bits(FrameLayout)) - 1,
    Bound#{frame_layout => FrameLayout, frame_positions => Positions, payload_bits => PayloadBits,
        physical_width => max(1, PayloadBits), operation => Op}.

%% Source stream offsets are checked rather than trusting duplicated derived metadata.
-spec check_field(field(), {non_neg_integer(), non_neg_integer()}) ->
    {non_neg_integer(), non_neg_integer()}.
check_field(F = #{type := Type, message_bit_offset := Wire}, {Wire, At}) ->
    Width = hls_type:width(Type),
    case maps:find(constant, F) of
        {ok, Bits} -> Width = bit_size(Bits), {Wire + Width, At};
        error -> At = maps:get(capture_bit_offset, F), {Wire + Width, At + Width}
    end.

%% Reuse the compiler's canonical header/padding algebra instead of hand-coding that ABI.
-spec bound(field()) ->
    #{type := hls_type:descriptor(), domain := unknown | {values, [bitstring()]}}.
bound(F = #{type := Type}) ->
    Domain = case maps:find(constant, F) of
        {ok, Bits} -> {values, [Bits]};
        error -> unknown
    end,
    #{type => Type, domain => Domain}.
