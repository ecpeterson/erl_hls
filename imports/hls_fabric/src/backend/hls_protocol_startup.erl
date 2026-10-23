-module(hls_protocol_startup).
-moduledoc "Encodes fixed topology startup records using the receiving actor's fresh ordinary schema. No source callback or state invariant supplies a value.".
-export([frames/2]).

-doc "Encodes startup records in declared sender order, including duplicates. Requires the receiving hls_local_actor artifact from the same fresh source build. Checks record identity/arity and exact host packing, then uses the ordinary 128-bit frame ABI (at most 96 payload bits). Supports built-in numeric/boolean codecs and full-width integer bit-cast providers; other codecs reject. Source callbacks still determine consume, postpone or failure. This is not a startup progress proof.".
-spec frames(hls_local_actor:artifact(), [tuple()]) -> [non_neg_integer()].
frames(#{spec := #{message_names := Names}, plan := #{records := Records}}, Messages) ->
    [frame(Message, Names, Records) || Message <- Messages].

%% Match the receiving module's tag enumeration and typed record field order exactly.
-spec frame(tuple(), [atom()], [term()]) -> non_neg_integer().
frame(Message, Names, Records) when is_tuple(Message), tuple_size(Message) > 0 ->
    [Tag | Values] = tuple_to_list(Message),
    case {[I || {I,T} <- lists:enumerate(3,Names), T =:= Tag],
          [Fs || {attribute,_,record,{T,Fs}} <- Records, T =:= Tag]} of
        {[Op], [Fields]} when length(Values) =:= length(Fields) ->
            Bound = [#{type => Type, domain => {values,[hls_type:pack_exact(V,Type)]}}
                || {V,Type} <- lists:zip(Values,[field_type(F) || F <- Fields])],
            #{mask := Mask, value := Value} = xls_message_bits:frame(Op,Bound),
            true = Mask =:= (1 bsl 128)-1, Value;
        _ -> error({invalid_startup_record, Message})
    end;
frame(Message, _, _) -> error({invalid_startup_record, Message}).

%% Admit only codecs with the established ordinary scalar wire representation.
-spec field_type(term()) -> hls_type:descriptor().
field_type({typed_record_field,_,Type}) ->
    Descriptor = hls_type:descriptor(Type),
    case Descriptor of
        {hls_type,P,_,_} when P =:= hls_nums; P =:= hls_bool -> Descriptor;
        _ -> wire_scalar(Descriptor)
    end.

%% A provider may validate values, but may not hide padding or custom wire transforms.
-spec wire_scalar(hls_type:descriptor()) -> hls_type:descriptor().
wire_scalar(Descriptor) ->
    Printed = iolist_to_binary(hls_type:print_type(Descriptor)),
    Width = hls_type:width(Descriptor),
    case {hls_type:dslx_codec(Descriptor), re:run(Printed,"^[us]([1-9][0-9]*)$",[{capture,[1],binary}])} of
        {bit_cast,{match,[Bits]}} when Width > 0, Width =< 96 ->
            case binary_to_integer(Bits) =:= Width andalso hls_type:value_width(Descriptor) =:= Width of
                true -> Descriptor;
                false -> error({unsupported_startup_codec, Descriptor})
            end;
        _ -> error({unsupported_startup_codec, Descriptor})
    end.
