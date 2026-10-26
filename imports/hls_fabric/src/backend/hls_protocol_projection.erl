-module(hls_protocol_projection).
-moduledoc "Projects ordinary entry snapshots into statically bound messages using only constants and bit wiring. Unsupported type codecs are rejected, not approximated.".
-export([plan/1, frame/2, frame/3, evaluate/2]).
-export_type([bit/0]).

-doc "A constant bit or one numeric bit of the already evaluated ordinary entry payload.".
-type bit() :: 0 | 1 | {payload, non_neg_integer()}.

-doc "Plans every ordinary entry layout and effect from the compiler's storage metadata. Keeps layout/index correlations and output port numbering. Accepts integer, boolean, recursively composed records and custom full-width bit-cast codecs with no unused representation bits. Custom codecs still require comparison against the ordinary generated decoder before protocol admission. This establishes projection structure, not source eligibility, payload lifetime or delivery order.".
-spec plan(map()) -> map().
plan(#{entries:=Entries,message_names:=Messages,output_names:=Ports,frame_layout:=FrameLayout}) ->
    Layouts=lists:append([Ls||#{layouts:=Ls}<-Entries]),
    Ids=[L||#{layout:=L}<-Layouts],true=length(Ids)=:=length(lists:usort(Ids)),
    Rows=[#{layout=>L,index=>I,port=>P,tag=>T,frame=>frame(E,Messages,FrameLayout),
        port_number=>number(P,Ports,0)} || #{layout:=L,storage:=#{effects:=Es}}<-Layouts,
        {I,E=#{port:=P,tag:=T}}<-lists:enumerate(0,Es)],
    Width=lists:max([1|[B||#{storage:=#{bits:=B}}<-Layouts]]),
    true=lists:all(fun(#{frame:=Bits})->lists:all(fun
        ({payload,J})->J<Width;(_)->true end,Bits) end,Rows),
    #{frame_layout=>FrameLayout,payload_width=>Width,rows=>Rows,layouts=>Ids,invalid_layout_or_index=>zero}.

-doc "Returns an ordinary actor frame projection with the default canonical capacity. Use frame/3 when the enclosing compiler program selects a different layout.".
-spec frame(map(),[atom()]) -> [bit()].
frame(Effect, Messages) -> frame(Effect, Messages, hls_frame_layout:default()).

-doc "Returns the complete selected canonical frame in numeric low-bit-first order. Field constants use physical bitstrings; dynamic fields retain compiler storage offsets and known-bit slices. Rejects messages exceeding the layout or codecs with custom conversion or padding; capture width remains independent of frame capacity.".
-spec frame(map(), [atom()], hls_frame_layout:layout()) -> [bit()].
frame(#{tag:=Tag,fields:=Fields},Messages,FrameLayout) ->
    Stream=lists:append([field(F)||F<-Fields]),N=length(Stream),
    PayloadBits=hls_frame_layout:payload_bits(FrameLayout),
    Words=hls_frame_layout:check_payload(FrameLayout,N),
    Header=hls_codec:unsigned(hls_frame_layout:pack_header(#{op=>number(Tag,Messages,3),flags=>0,txid=>0,
        payload_words=>Words})),
    Padded=Stream++lists:duplicate(PayloadBits-N,0),
    integer_bits(Header,hls_frame_layout:header_bits())++
        [lists:nth(hls_codec:stream_bit_index(PayloadBits,J)+1,Padded)||J<-lists:seq(0,PayloadBits-1)].

-doc "Evaluates a planned low-bit-first projection for diagnostics and host-codec comparisons. Payload is a nonnegative numeric ordinary entry snapshot; bits outside referenced positions are irrelevant.".
-spec evaluate([bit()],non_neg_integer()) -> non_neg_integer().
evaluate(Bits,Payload) when Payload>=0 ->
    lists:foldl(fun({I,B},N)->N bor (value(B,Payload) bsl I) end,0,lists:enumerate(0,Bits)).

%% Ordinary storage is numeric, while record field concatenation follows physical stream order.
-spec field(map()) -> [bit()].
field(F=#{type:=Type}) ->
    ok=wire_type(Type),Width=hls_type:width(Type),
    case F of
        #{constant:=Bits}->Width=bit_size(Bits),[B||<<B:1>><=Bits];
        _->Raw=raw(F,Width),[lists:nth(hls_codec:stream_bit_index(Width,J)+1,Raw)||J<-lists:seq(0,Width-1)]
    end.

%% Integer slices are packed low-first by the ordinary compiler; every omitted bit is fixed.
-spec raw(map(),non_neg_integer()) -> [bit()].
raw(#{known:=#{mask:=Mask,value:=Value},slices:=Slices}=F,Width) ->
    {Dynamic,_}=lists:foldl(fun({Start,Size},{Acc,At})->
        true=Start>=0 andalso Size>0 andalso Start+Size=<Width,
        {Acc++[{Start+J,{payload,At+J}}||J<-lists:seq(0,Size-1)],At+Size}
    end,{[],maps:get(offset,F,0)},Slices),
    Keys=[J||{J,_}<-Dynamic],true=length(Keys)=:=length(lists:usort(Keys)),
    Unknown=[J||J<-lists:seq(0,Width-1),(Mask bsr J) band 1=:=0],
    true=lists:sort(Keys)=:=Unknown,ByBit=maps:from_list(Dynamic),
    [maps:get(J,ByBit,(Value bsr J) band 1)||J<-lists:seq(0,Width-1)];
raw(#{offset:=At},Width) -> [{payload,At+J}||J<-lists:seq(0,Width-1)].

%% The ordinary ABI must be a full-width cast; arbitrary conversion or padding cannot become wiring.
-spec wire_type(hls_type:descriptor()) -> ok.
wire_type({hls_type,hls_nums,Name,_}) when Name=:=u8;Name=:=u16;Name=:=u32;Name=:=u64;
        Name=:=s8;Name=:=s16;Name=:=s32;Name=:=s64;Name=:=uN;Name=:=sN -> ok;
wire_type({hls_type,hls_bool,bool,[]}) -> ok;
wire_type({hls_type,hls_record,_,Fields}) -> lists:foreach(fun({_,T})->wire_type(T) end,Fields);
wire_type(Type) ->
    Width=hls_type:width(Type),
    case hls_type:dslx_codec(Type)=:=bit_cast andalso Width>0
            andalso hls_type:value_width(Type)=:=Width of
        true->ok;
        false->error({unsupported_protocol_codec,Type})
    end.

%% Header, port and known-field constants use numeric low-bit-first order.
-spec integer_bits(non_neg_integer(),non_neg_integer()) -> [0|1].
integer_bits(Value,Width) -> [(Value bsr I) band 1||I<-lists:seq(0,Width-1)].

%% A missing or duplicate symbol is an inconsistent source interface, never an implicit route.
-spec number(atom(),[atom()],non_neg_integer()) -> non_neg_integer().
number(Name,Names,Start) -> [N]=[I||{I,K}<-lists:enumerate(Start,Names),K=:=Name],N.

%% Host evaluation shares only the explicit wiring plan, not the ordinary codec implementation.
-spec value(bit(),non_neg_integer()) -> 0|1.
value({payload,J},Payload) -> (Payload bsr J) band 1;
value(B,_) -> B.
