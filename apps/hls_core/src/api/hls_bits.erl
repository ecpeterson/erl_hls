-module(hls_bits).
-moduledoc """
Fixed-size bitstrings and explicit wire padding. bits(Width) carries a native
Erlang bitstring in stream order. padded(Type, Width) reserves Width bits
without changing the host value or XLS type. Packing appends zero padding
bits; decoding ignores them. Collections preserve padding per element.

Actor declarations construct these descriptors; hls_type dispatches their host codecs; compiler companions own XLS callbacks.
""".
-behavior(hls_type).
%% Application type constructors.
-export([bits/1, padded/2]).

%% hls_type provider callbacks.
-export([width/2, value_width/2, zero/2, pack/3, unpack/3]).
%% Shared type contracts.
-export_type([bits/1, padded/2]).

-type bits(_Width) :: bitstring().
-type padded(Value, _Width) :: Value.

-spec bits(non_neg_integer()) -> hls_type:descriptor().
bits(Width) when is_integer(Width), Width >= 0 ->
    {hls_type, ?MODULE, bits, [Width]}.

-spec padded(hls_type:descriptor(), non_neg_integer()) -> hls_type:descriptor().
padded(Type, Width) when is_integer(Width), Width >= 0 ->
    case Width >= hls_type:width(Type) of
        true -> {hls_type, ?MODULE, padded, [Type, Width]};
        false -> error({padding_too_narrow, Width, hls_type:width(Type)})
    end.

width(bits, [Width]) when is_integer(Width), Width >= 0 -> Width;
width(padded, [Type, Width]) ->
    _ = padded(Type, Width),
    Width.
value_width(bits, Args) -> width(bits, Args);
value_width(padded, [Type, _Width]) -> hls_type:value_width(Type).
zero(bits, [Width]) -> <<0:Width>>;
zero(padded, [Type, _Width]) -> hls_type:zero(Type).
pack(Value, bits, [Width]) ->
    case is_bitstring(Value) andalso bit_size(Value) =:= Width of
        true -> Value;
        false -> error(badarg)
    end;
pack(Value, padded, [Type, Width]) ->
    hls_codec:pad_to(hls_type:pack(Value, Type), Width).
unpack(Packed, bits, [Width]) ->
    hls_codec:split(Packed, Width);
unpack(Packed, padded, [Type, Width]) ->
    {Slot, Rest} = hls_codec:split(Packed, Width),
    {Value, _Padding} = hls_type:unpack(Slot, Type),
    {Value, Rest}.
