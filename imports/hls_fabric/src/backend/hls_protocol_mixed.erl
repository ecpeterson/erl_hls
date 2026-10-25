-module(hls_protocol_mixed).
-moduledoc "Fresh source-bound BEAM/native placement using the shared DSLX bridge. Host admission, transport retirement and application progress are separate obligations.".
-export([emit/1,write/2,encode/3,decode/3]).

-doc "Builds one framed native partition using hls_protocol_bridge's configuration; complementary actors run in BEAM. Requires one recipient per BEAM output, no BEAM-to-BEAM links, rectangle control and explicit activation. Writes mixed.etf for hls_protocol_mixed_stream and the usual bridge artifacts. Loaded codecs are checked against fresh source declarations. Generation failures create no output; I/O failures retain partial output; no mailbox replacement, progress, timing or device admission is granted.".
-spec write(map() | file:filename(), file:filename()) -> map().
write(Config, Directory) ->
    hls_generated_files:write(emit(Config), Directory).

-doc "Generates a mixed BEAM/native bundle without writing output, returning relative filenames with IO data and its deployment plan. Accepts a trusted source config map or a filename containing one map; source paths remain relative to the caller. Preparation loads sources and invokes trusted constructors. Template and support reads remain; loaded host codecs must stay available.".
-spec emit(map() | file:filename()) -> hls_generated_files:output().
emit(Config) when is_map(Config) ->
    Build = hls_protocol_transport:plan(Config),
    #{files := BridgeFiles, result := #{bridge := Bridge = #{native_indices := Native, links := Links, identity := Identity, host := Host, service := Service},
        transport := #{whole_control := Control, bundle := Bundle = #{topology := #{actors := Actors, routes := Routes, startup := Startup}, modules := Modules}}}} =
        hls_protocol_bridge:emit(Build,maps:with([host, service, control, activation, inspection],Config)),
    HostIds=[Id||{I,#{id:=Id}}<-lists:enumerate(0,Actors),not lists:member(I,Native)],
    Application=hls_protocol_application_binding:bind(Bundle,Control,maps:from_list([{Id,board}||#{id:=Id}<-Actors]),#{board=>Host}),
    HostActors=maps:from_list([begin
        Outputs=maps:from_list([begin
            [Destination]=Recipients,
            case Destination of {actor,To}->false=lists:member(To,HostIds);{external,_}->ok end,
            {Port,Destination}
        end||#{source:={From,Port},recipients:=Recipients}<-Routes,From=:=Id]),
        #{program:=Program}=maps:get(Module,Modules),
        #{capacity:=Capacity}=xls_actor_program:spec(Program),
        Messages=lists:append([Ms||#{target:=Target,messages:=Ms}<-Startup,Target=:=Id]),
        {I,#{id=>Id,module=>Module,capacity=>Capacity,outputs=>Outputs,startup=>Messages}}
    end||{I,#{id:=Id,module:=Module}}<-lists:enumerate(0,Actors),not lists:member(I,Native)]),
    ExternalKeys=lists:usort([D||#{outputs:=O}<-maps:values(HostActors),D={external,_}<-maps:values(O)]),
    Targets=maps:merge(maps:from_list([{{actor,Id},{actor,I}}||{I,#{id:=Id}}<-lists:enumerate(0,Actors),lists:member(I,Native)]),
        maps:from_list([{K,K}||K<-ExternalKeys])),
    Mixed=#{host_actors=>lists:sort(maps:keys(HostActors)),identity=>Identity,links=>[link_descriptor(L,Actors)||L<-Links]},
    Plan=#{actors=>HostActors,targets=>Targets,mixed=>Mixed,application=>Application,device=>board,
        binding=>#{host=>Host,control=>Service},bridge=>Bridge,eligible=>false},
    #{files => hls_generated_files:merge([BridgeFiles, #{"mixed.etf" => term_to_binary(Plan, [deterministic])}]),
      result => Plan};
emit(Filename) -> emit(hls_source_config:read(Filename)).

%% The bridge's destination codecs, not the sender's operation numbering, define crossing frames.
-spec link_descriptor(map(),[map()]) -> map().
link_descriptor(Link=#{source_index:=S,destination_index:=D,direction:=Direction,classes:=Classes},Actors) ->
    #{module:=SM}=lists:nth(S+1,Actors),#{module:=DM}=lists:nth(D+1,Actors),
    Link#{direction:=case Direction of incoming->to_rtl;outgoing->to_beam end,
        source_module=>SM,destination_module=>DM,
        classes:=[C#{port=>Port,tag=>Tag,message_bits=>DM:pack_width(Tag)}
            ||C=#{channel:=#{port:=Port,tag:=Tag}}<-Classes]}.

-doc "Encodes an ordinary source output for exactly one crossing class. Uses the destination operation selector and checks omitted constants, reserved bits and padding. Sender PID authentication, queue capacity and sequence reservation belong to the owner.".
-spec encode(map(),atom(),tuple()) -> {byte(),non_neg_integer()}.
encode(#{source_module:=Module,classes:=Classes},Port,Message) ->
    Tag=element(1,Message),
    [#{slot:=Slot,codec:=Codec=#{value:=Value},message_bits:=Width}]=
        [C||C=#{port:=P,tag:=T}<-Classes,P=:=Port,T=:=Tag],
    Packed=Module:pack(Message),Width=bit_size(Packed),
    Payload=binary:decode_unsigned(hls_codec:pad_to(Packed,96),little),
    Frame=(Value band 16#ffffffff) bor (Payload bsl 32),
    {ok,_}=hls_protocol_codec:encode(Codec,Frame),{Slot,Frame}.

-doc "Checks a canonical crossing frame and decodes its bound destination record, including a packed round trip. Caller authenticates the link/session and must acknowledge only after actual destination admission; failure is never permission to replay.".
-spec decode(map(),byte(),non_neg_integer()) -> tuple().
decode(#{destination_module:=Module,classes:=Classes},Slot,Frame) ->
    [#{tag:=Tag,codec:=Codec,message_bits:=Width}]=[C||C=#{slot:=I}<-Classes,I=:=Slot],
    {ok,_}=hls_protocol_codec:encode(Codec,Frame),
    <<Packed:Width/bitstring,_/bitstring>> = <<(Frame bsr 32):96/little>>,
    {Message,<<>>}=Module:unpack(Tag,Packed),Packed=Module:pack(Message),Message.
