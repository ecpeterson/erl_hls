-module(hls_protocol_codec).
-moduledoc "Runtime conversion between ordinary frames and compact captures using retained, checked permutations. hls_protocol_codec_plan derives the layout; these codecs perform no source analysis or hardware rendering.".

%% Runtime data conversion and its retained wire descriptor.
-export([encode/2, decode/2]).
-export_type([plan/0]).

-doc "Checked compact-to-ordinary frame wiring. Mask/value fix all omitted bits; frame_positions lists each retained stream bit in compact order.".
-type plan() :: #{frame_layout := hls_frame_layout:layout(), mask := non_neg_integer(), value := non_neg_integer(),
    frame_positions := [non_neg_integer()], payload_bits := non_neg_integer(), physical_width := pos_integer(),
    operation := 0 .. ((1 bsl 8) - 1)}.

-doc "Projects a canonical ordinary frame, rejecting a wrong operation, header, padding or omitted constant field. Runtime receipt guards and generation matching are separate checks. The integer frame uses the layout retained in the codec.".
-spec encode(plan(), non_neg_integer()) -> {ok, non_neg_integer()} | {error, invalid_frame}.
encode(#{frame_layout := FrameLayout, mask := Mask, value := Value, frame_positions := Positions}, Frame)
        when Frame >= 0 ->
    case Frame < (1 bsl hls_frame_layout:frame_bits(FrameLayout)) andalso Frame band Mask =:= Value of
        true ->
            {ok, lists:foldl(fun({I, J}, Bits) -> Bits bor (((Frame bsr J) band 1) bsl I) end,
                0, lists:enumerate(0, Positions))};
        false -> {error, invalid_frame}
    end;
encode(_, _) -> {error, invalid_frame}.

-doc "Restores the exact ordinary frame from a canonical compact payload. A constant-only channel uses a zero-valued dummy wire; nonzero dummy or excess payload bits are rejected. This does not validate semantic payload values.".
-spec decode(plan(), non_neg_integer()) -> non_neg_integer().
decode(#{value := Value, frame_positions := Positions, payload_bits := Width}, Payload)
        when Payload >= 0, Payload < (1 bsl Width) ->
    lists:foldl(fun({I, J}, Frame) -> Frame bor (((Payload bsr I) band 1) bsl J) end,
        Value, lists:enumerate(0, Positions));
decode(_, _) -> error(invalid_capture_payload).
