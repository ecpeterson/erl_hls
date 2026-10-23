-module(hls_protocol_mixed).
-moduledoc "Fresh source-bound BEAM/native placement using the shared DSLX bridge. Host admission, transport retirement and application progress are separate obligations.".
-export([write/2,encode/3,decode/3]).

-doc "Builds one framed native partition using hls_protocol_bridge's configuration; complementary actors run in BEAM. Requires one recipient per BEAM output, no BEAM-to-BEAM links, rectangle control and explicit activation. Writes mixed.etf for hls_protocol_mixed_stream and the usual bridge artifacts. Loaded codecs are checked against fresh source declarations. Partial output is retained on failure; no mailbox replacement, progress, timing or device admission is granted.".
-spec write(map(),file:filename()) -> map().
write(Config,Directory) ->
    _=hls_protocol_bridge:write(Config,Directory),
    Bridge=#{native_indices:=Native,links:=Links,identity:=Identity,host:=Host,service:=Service}=read(filename:join(Directory,"bridge.etf")),
    #{bundle:=Bundle=#{topology:=#{actors:=Actors,routes:=Routes,startup:=Startup},modules:=Modules}}=read(filename:join(Directory,"transport.etf")),
    HostIds=[Id||{I,#{id:=Id}}<-lists:enumerate(0,Actors),not lists:member(I,Native)],
    Application=hls_protocol_application_binding:bind(Bundle,maps:from_list([{Id,board}||#{id:=Id}<-Actors]),#{board=>Host}),
    HostActors=maps:from_list([begin
        Outputs=maps:from_list([begin
            [Destination]=Recipients,
            case Destination of {actor,To}->false=lists:member(To,HostIds);{external,_}->ok end,
            {Port,Destination}
        end||#{source:={From,Port},recipients:=Recipients}<-Routes,From=:=Id]),
        #{spec:=#{capacity:=Capacity}}=maps:get(Module,Modules),
        Messages=lists:append([Ms||#{target:=Target,messages:=Ms}<-Startup,Target=:=Id]),
        {I,#{id=>Id,module=>Module,capacity=>Capacity,outputs=>Outputs,startup=>Messages}}
    end||{I,#{id:=Id,module:=Module}}<-lists:enumerate(0,Actors),not lists:member(I,Native)]),
    ExternalKeys=lists:usort([D||#{outputs:=O}<-maps:values(HostActors),D={external,_}<-maps:values(O)]),
    Targets=maps:merge(maps:from_list([{{actor,Id},{actor,I}}||{I,#{id:=Id}}<-lists:enumerate(0,Actors),lists:member(I,Native)]),
        maps:from_list([{K,K}||K<-ExternalKeys])),
    Mixed=#{host_actors=>lists:sort(maps:keys(HostActors)),identity=>Identity,links=>[link_descriptor(L,Actors)||L<-Links]},
    Plan=#{actors=>HostActors,targets=>Targets,mixed=>Mixed,application=>Application,device=>board,
        binding=>#{host=>Host,control=>Service},ingress=>hls_protocol_ingress:plan(Bundle),bridge=>Bridge,eligible=>false},
    ok=file:write_file(filename:join(Directory,"mixed.etf"),term_to_binary(Plan,[deterministic]),[exclusive]),Plan.

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

%% Only artifacts created in this fresh build are decoded; never network-supplied terms.
-spec read(file:filename()) -> map().
read(Path)->{ok,Bytes}=file:read_file(Path),binary_to_term(Bytes).
