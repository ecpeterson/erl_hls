-module(hls_bits).
-moduledoc """
Fixed-size bitstrings and explicit wire padding. bits(Width) carries a native
Erlang bitstring in stream order. padded(Type, Width) reserves Width bits
without changing the host value or XLS type. Packing appends zero padding
bits; decoding ignores them. Collections preserve padding per element.
""".
-behavior(hls_type).
-export([bits/1, padded/2, width/2, value_width/2, zero/2, pack/3, unpack/3,
    print_type/2, dslx_codec/2, dslx_imports/0, transpile/3]).
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
unpack(Packed, bits, [Width]) -> hls_codec:split(Packed, Width);
unpack(Packed, padded, [Type, Width]) ->
    {Slot, Rest} = hls_codec:split(Packed, Width),
    {Value, _Padding} = hls_type:unpack(Slot, Type),
    {Value, Rest}.
%% A one-tuple distinguishes streams from integers without adding hardware.
print_type(bits, [Width]) -> ["(bits[", integer_to_list(Width), "],)"];
print_type(padded, [Type, _Width]) -> hls_type:print_type(Type).
dslx_imports() -> [hls_bits].
dslx_codec(bits, [_Width]) ->
    {fun(Bits) -> ["(hls_bits::to_stream(", Bits, "),)"] end,
     fun(Value) -> ["hls_bits::from_stream((", Value, ").0)"] end};
dslx_codec(padded, [Type, Width]) ->
    SubWidth = hls_type:width(Type),
    {fun(Bits) -> hls_type:dslx_from_bits(Type,
        ["hls_bits::from_stream(hls_bits::to_stream(", Bits, ")[",
            integer_to_list(Width - SubWidth), ":])"])
     end,
     fun(Value) -> ["hls_bits::pad<u32:", integer_to_list(SubWidth), ", u32:",
        integer_to_list(Width), ">(", hls_type:dslx_to_bits(Type, Value), ")"] end}.
transpile(bits, [{static, integer, Width}], State) ->
    xls_parse:reference(State, {phantom, type, bits(Width)});
transpile(padded, [{phantom, type, Type}, {static, integer, Width}], State) ->
    xls_parse:reference(State, {phantom, type, padded(Type, Width)}).
