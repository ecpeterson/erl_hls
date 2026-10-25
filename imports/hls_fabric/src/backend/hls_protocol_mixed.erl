-module(hls_protocol_mixed).
-moduledoc "Fresh source-bound BEAM/native placement using the shared DSLX bridge. Host admission, transport retirement and application progress are separate obligations.".
-export([plan/1, descriptor/1, transport/1, emit/1, write/2, encode/3, decode/3]).
-export_type([plan/0, descriptor/0, result/0, output/0, host_actor/0, link/0, class/0]).

%% Host bindings and target selection are complete before the native bridge can render.
-record(plan, {bridge :: hls_protocol_bridge:plan(), descriptor :: descriptor()}).
-doc "One ordinary BEAM actor's checked source identity, capacity, startup records and unique output recipients.".
-type host_actor() :: #{id := hls_protocol_topology:id(), module := module(), capacity := pos_integer(),
    outputs := #{atom() => hls_protocol_topology:destination()}, startup := [tuple()]}.

-doc "A crossing class bound to the destination codec and the loaded Erlang record used by the host bridge.".
-type class() :: #{slot := non_neg_integer(), channel := hls_protocol_capture:binding(),
    codec := hls_protocol_codec:plan(), port := atom(), tag := atom(), message_bits := non_neg_integer()}.

-doc "The checked fabric crossing with host-facing direction, loaded source/destination modules and record codecs. Logical link indices and capture layout remain those of the native bridge.".
-type link() :: #{index := non_neg_integer(), source_index := non_neg_integer(),
    destination_index := non_neg_integer(), output_index := non_neg_integer(),
    output := hls_protocol_source:output(), shape := non_neg_integer(), widths := [pos_integer()],
    slots := pos_integer(), payload_bits := pos_integer(), input_bits := pos_integer(),
    index_bits := pos_integer(), pair := hls_protocol_inbox:pair(),
    direction := to_rtl | to_beam, classes := [class()],
    source_module := module(), destination_module := module()}.

%% Standalone host codec calls need no physical channel; retained crossing classes supply it.
-type codec_class() :: #{slot := byte(), codec := hls_protocol_codec:plan(),
    port := atom(), tag := atom(), message_bits := non_neg_integer(),
    channel => hls_protocol_capture:binding()}.
%% Standalone encoding can retain routing addresses without a physical fabric/capture layout.
-type encoder_link() :: #{source_module := module(), destination_module => module(),
    classes := [codec_class()], index => non_neg_integer(), source_index => non_neg_integer(),
    destination_index => non_neg_integer(), direction => to_rtl | to_beam}.
%% Standalone decoding needs the destination codec and may retain the matching source/routing data.
-type decoder_link() :: #{destination_module := module(), source_module => module(),
    classes := [codec_class()], index => non_neg_integer(), source_index => non_neg_integer(),
    destination_index => non_neg_integer(), direction => to_rtl | to_beam}.

%% Logical targets map to global native indices or unchanged external stream identities.
-type targets() :: #{hls_protocol_topology:destination() =>
    {actor, non_neg_integer()} | {external, hls_protocol_topology:id()}}.
%% The mixed session uses the bridge's checked return addresses.
-type endpoints() :: #{host := hls_source_config:endpoint(), control := hls_source_config:endpoint()}.
%% Planning retains host ownership and crossing codecs before attachment is possible.
-type mixed_interface() :: #{host_actors := [non_neg_integer()], links := [link()]}.
%% Emission binds the same host crossings to the native bridge's exact hardware identity.
-type attached_interface() :: #{host_actors := [non_neg_integer()], links := [link()], identity := binary()}.

-doc "A complete checked mixed composition with source-bound host actors and native bridge. Retain unchanged in process with its source codecs loaded; it contains no runtime session or device admission.".
-opaque plan() :: #plan{}.

-doc "Checked host actors, targets, crossing codecs and the static native bridge. The bridge and mixed attachment identities are added only by emission.".
-type descriptor() :: #{actors := #{non_neg_integer() => host_actor()}, targets := targets(),
    mixed := mixed_interface(), application := hls_protocol_application_binding:application(),
    device := board, binding := endpoints(), bridge := hls_protocol_bridge:descriptor(), eligible := false}.

-doc "The emitted mixed deployment with native attachment identity; source host actors, target ownership and codecs remain unchanged.".
-type result() :: #{actors := #{non_neg_integer() => host_actor()}, targets := targets(),
    mixed := attached_interface(), application := hls_protocol_application_binding:application(),
    device := board, binding := endpoints(), bridge := hls_protocol_bridge:bridge(), eligible := false}.

-doc "Generated native bridge files and the final mixed runtime deployment.".
-type output() :: hls_generated_files:output(result()).

-doc "Builds one framed native partition using hls_protocol_bridge's configuration; complementary actors run in BEAM. Requires one recipient per BEAM output, no BEAM-to-BEAM links, rectangle control and explicit activation. Writes mixed.etf for hls_protocol_mixed_stream and the usual bridge artifacts. Loaded codecs are checked against fresh source declarations. Generation failures create no output; I/O failures retain partial output; no mailbox replacement, progress, timing or device admission is granted.".
-spec write(hls_source_config:mixed() | file:filename() | plan(), file:filename()) -> result().
write(Config, Directory) ->
    hls_generated_files:write(emit(Config), Directory).

-doc "Checks a trusted mixed config or config filename without rendering hardware. Binds fresh source codecs, complementary host actors, unique output targets and native crossing classes before returning the complete plan. Trusted source constructors may have effects; keep loaded host codecs unchanged through emission and runtime use.".
-spec plan(hls_source_config:mixed() | file:filename()) -> plan().
plan(Config) when is_map(Config) ->
    Build = hls_protocol_transport:plan(Config),
    #{whole_control := Control,
      bundle := Bundle = #{topology := #{actors := Actors, routes := Routes, startup := Startup}, modules := Modules}} =
        hls_protocol_transport:descriptor(Build),
    BridgePlan = hls_protocol_bridge:plan(Build,
        maps:with([host, service, control, activation, inspection], Config)),
    Bridge = #{native_indices := Native, links := Links, host := Host, service := Service} =
        hls_protocol_bridge:descriptor(BridgePlan),
    HostIds=[Id||{I,#{id:=Id}}<-lists:enumerate(0,Actors),not lists:member(I,Native)],
    Application=hls_protocol_application_binding:bind(Bundle,Control,maps:from_list([{Id,board}||#{id:=Id}<-Actors]),#{board=>Host}),
    HostActors=maps:from_list([begin
        Outputs=maps:from_list([begin
            Destination = host_destination(Id, Module, Port, Recipients, HostIds),
            {Port, Destination}
        end||#{source:={From,Port},recipients:=Recipients}<-Routes,From=:=Id]),
        #{program:=Program}=maps:get(Module,Modules),
        #{capacity:=Capacity}=xls_actor_program:spec(Program),
        Messages=lists:append([Ms||#{target:=Target,messages:=Ms}<-Startup,Target=:=Id]),
        {I,#{id=>Id,module=>Module,capacity=>Capacity,outputs=>Outputs,startup=>Messages}}
    end||{I,#{id:=Id,module:=Module}}<-lists:enumerate(0,Actors),not lists:member(I,Native)]),
    ExternalKeys=lists:usort([D||#{outputs:=O}<-maps:values(HostActors),D={external,_}<-maps:values(O)]),
    Targets=maps:merge(maps:from_list([{{actor,Id},{actor,I}}||{I,#{id:=Id}}<-lists:enumerate(0,Actors),lists:member(I,Native)]),
        maps:from_list([{K,K}||K<-ExternalKeys])),
    MixedLinks = [link_descriptor(Link, Actors) || Link <- Links],
    Mixed=#{host_actors=>lists:sort(maps:keys(HostActors)),links=>MixedLinks},
    Descriptor=#{actors=>HostActors,targets=>Targets,mixed=>Mixed,application=>Application,device=>board,
        binding=>#{host=>Host,control=>Service},bridge=>Bridge,eligible=>false},
    #plan{bridge = BridgePlan, descriptor = Descriptor};
plan(Filename) -> plan(hls_source_config:read(Filename)).

-doc "Returns source-checked host actors, routes, codecs and the static native bridge. No attachment identities or emitted support hashes are present; treat this view as read-only.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{descriptor = Descriptor}) -> Descriptor.

-doc "Returns the retained transport placement for source, topology and receiver-layout inspection. Reuses the checked snapshot without recompiling or rendering; retain it unchanged.".
-spec transport(plan()) -> hls_protocol_transport:build().
transport(#plan{bridge = Build}) -> hls_protocol_bridge:transport(Build).

-doc "Renders a checked mixed plan, or plans a trusted config map/filename before rendering. Returns relative files and the final runtime deployment without writing output. Retained plans need no source rereads or host-binding checks; templates and support libraries are read at emission.".
-spec emit(hls_source_config:mixed() | file:filename() | plan()) -> output().
emit(#plan{bridge = BridgePlan, descriptor = Descriptor = #{mixed := Mixed}}) ->
    #{files := BridgeFiles, result := #{bridge := Bridge = #{identity := Identity}}} =
        hls_protocol_bridge:emit(BridgePlan),
    Deployment = Descriptor#{bridge := Bridge, mixed := Mixed#{identity => Identity}},
    #{files => hls_generated_files:merge([BridgeFiles,
        #{"mixed.etf" => term_to_binary(Deployment, [deterministic])}]), result => Deployment};
emit(Config) -> emit(plan(Config)).

%% A BEAM output has one crossing or external recipient; host-to-host routing is unsupported.
-spec host_destination(hls_protocol_topology:id(), module(), atom(),
    [hls_protocol_topology:destination()], [hls_protocol_topology:id()]) -> hls_protocol_topology:destination().
host_destination(Id, Module, Port, [Destination], HostIds) ->
    case Destination of
        {actor, To} ->
            case lists:member(To, HostIds) of
                false -> Destination;
                true -> hls_diagnostic:raise(mixed, unsupported_host_route,
                    <<"Mixed builds do not route messages between BEAM actors; place one endpoint in hardware.">>,
                    #{actor => Id, module => Module, port => Port, destination => Destination,
                      capability => beam_to_beam})
            end;
        {external, _} -> Destination
    end;
host_destination(Id, Module, Port, Recipients, _) ->
    hls_diagnostic:raise(mixed, unsupported_host_fanout,
        <<"Each BEAM output in a mixed build must have exactly one recipient.">>,
        #{actor => Id, module => Module, port => Port, recipients => Recipients}).

%% The bridge's destination codecs, not the sender's operation numbering, define crossing frames.
-spec link_descriptor(hls_protocol_partition:crossing(), [hls_protocol_topology:actor()]) -> link().
link_descriptor(Link=#{source_index:=S,destination_index:=D,direction:=Direction,classes:=Classes},Actors) ->
    #{module:=SM}=lists:nth(S+1,Actors),#{module:=DM}=lists:nth(D+1,Actors),
    Link#{direction:=case Direction of incoming->to_rtl;outgoing->to_beam end,
        source_module=>SM,destination_module=>DM,
        classes:=[C#{port=>Port,tag=>Tag,message_bits=>DM:pack_width(Tag)}
            ||C=#{channel:=#{port:=Port,tag:=Tag}}<-Classes]}.

-doc "Encodes an ordinary source output for exactly one crossing class. Uses the destination operation selector and checks omitted constants, reserved bits and padding. Sender PID authentication, queue capacity and sequence reservation belong to the owner.".
-spec encode(link() | encoder_link(), atom(), tuple()) ->
    {byte(), non_neg_integer()}.
encode(#{source_module:=Module,classes:=Classes},Port,Message) ->
    Tag=element(1,Message),
    [#{slot:=Slot,codec:=Codec=#{value:=Value},message_bits:=Width}]=
        [C||C=#{port:=P,tag:=T}<-Classes,P=:=Port,T=:=Tag],
    Packed=Module:pack(Message),Width=bit_size(Packed),
    Payload=binary:decode_unsigned(hls_codec:pad_to(Packed,96),little),
    Frame=(Value band 16#ffffffff) bor (Payload bsl 32),
    {ok,_}=hls_protocol_codec:encode(Codec,Frame),{Slot,Frame}.

-doc "Checks a canonical crossing frame and decodes its bound destination record, including a packed round trip. Caller authenticates the link/session and must acknowledge only after actual destination admission; failure is never permission to replay.".
-spec decode(link() | decoder_link(), byte(), non_neg_integer()) -> tuple().
decode(#{destination_module:=Module,classes:=Classes},Slot,Frame) ->
    [#{tag:=Tag,codec:=Codec,message_bits:=Width}]=[C||C=#{slot:=I}<-Classes,I=:=Slot],
    {ok,_}=hls_protocol_codec:encode(Codec,Frame),
    <<Packed:Width/bitstring,_/bitstring>> = <<(Frame bsr 32):96/little>>,
    {Message,<<>>}=Module:unpack(Tag,Packed),Packed=Module:pack(Message),Message.
