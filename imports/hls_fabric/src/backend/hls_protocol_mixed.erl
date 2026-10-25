-module(hls_protocol_mixed).
-moduledoc "Fresh source-bound BEAM/native placement using the shared DSLX bridge. Host admission, transport retirement and application progress are separate obligations.".
-export([plan/1, descriptor/1, transport/1, emit/1, write/2, encode/2, encode/3, decode/3]).
-export_type([plan/0, descriptor/0, result/0, output/0, host_actor/0, link/0, class/0,
    codec_class/0, encoder_link/0, decoder_link/0]).

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

-doc "One host codec class, optionally retaining its physical channel binding. Constants and selectors are checked by its codec plan.".
-type codec_class() :: #{slot := byte(), codec := hls_protocol_codec:plan(),
    port := atom(), tag := atom(), message_bits := non_neg_integer(),
    channel => hls_protocol_capture:binding()}.
-doc "The source module and crossing classes required to encode a host record; optional routing fields retain its placement.".
-type encoder_link() :: #{source_module := module(), destination_module => module(),
    classes := [codec_class()], index => non_neg_integer(), source_index => non_neg_integer(),
    destination_index => non_neg_integer(), direction => to_rtl | to_beam}.
-doc "The destination module and crossing classes required to decode a host frame; optional routing fields retain its placement.".
-type decoder_link() :: #{destination_module := module(), source_module => module(),
    classes := [codec_class()], index => non_neg_integer(), source_index => non_neg_integer(),
    destination_index => non_neg_integer(), direction => to_rtl | to_beam}.

%% Source actor indices stay global when host and native subsets are separated.
-type indexed_actor() :: {non_neg_integer(), hls_protocol_topology:actor()}.
%% Startup order is source-declared and independent of host placement.
-type startup() :: #{target := hls_protocol_topology:id(), delivery := cast, messages := [tuple()]}.

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
    {NativeActors, HostPlacements} = lists:partition(fun({Index, _}) -> lists:member(Index, Native) end,
        lists:enumerate(0, Actors)),
    HostIds = [Id || {_, #{id := Id}} <- HostPlacements],
    Owners = maps:from_list([{Id, board} || #{id := Id} <- Actors]),
    Application = hls_protocol_application_binding:bind(Bundle, Control, Owners, #{board => Host}),
    HostActors = maps:from_list([{Index, host_actor(Actor, Routes, Startup, Modules, HostIds)}
        || {Index, Actor} <- HostPlacements]),
    Targets = targets(NativeActors, HostActors),
    MixedLinks = [link_descriptor(Link, Actors) || Link <- Links],
    Mixed = #{host_actors => lists:sort(maps:keys(HostActors)), links => MixedLinks},
    Descriptor = #{actors => HostActors, targets => Targets, mixed => Mixed, application => Application,
        device => board, binding => #{host => Host, control => Service}, bridge => Bridge, eligible => false},
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

%% Bind one host actor to its exact mailbox, ordered startup messages and checked output routes.
-spec host_actor(hls_protocol_topology:actor(), [hls_protocol_topology:route()], [startup()],
    #{module() => hls_local_actor:source() | hls_local_actor:artifact()},
    [hls_protocol_topology:id()]) -> host_actor().
host_actor(#{id := Id, module := Module}, Routes, Startup, Modules, HostIds) ->
    #{program := Program} = maps:get(Module, Modules),
    #{capacity := Capacity} = xls_actor_program:spec(Program),
    Outputs = host_outputs(Id, Module, Routes, HostIds),
    Messages = lists:append([Batch || #{target := Target, messages := Batch} <- Startup, Target =:= Id]),
    #{id => Id, module => Module, capacity => Capacity, outputs => Outputs, startup => Messages}.

%% Retain source port names while checking the supported single-recipient host routing model.
-spec host_outputs(hls_protocol_topology:id(), module(), [hls_protocol_topology:route()],
    [hls_protocol_topology:id()]) -> #{atom() => hls_protocol_topology:destination()}.
host_outputs(Id, Module, Routes, HostIds) ->
    maps:from_list([{Port, host_destination(Id, Module, Port, Recipients, HostIds)}
        || #{source := {From, Port}, recipients := Recipients} <- Routes, From =:= Id]).

%% Host routing addresses native actors by global index and preserves external stream identities.
-spec targets([indexed_actor()], #{non_neg_integer() => host_actor()}) -> targets().
targets(Native, HostActors) ->
    NativeTargets = maps:from_list([{{actor, Id}, {actor, Index}} || {Index, #{id := Id}} <- Native]),
    Destinations = lists:append([maps:values(Outputs) || #{outputs := Outputs} <- maps:values(HostActors)]),
    ExternalTargets = maps:from_list([{Destination, Destination} || Destination = {external, _} <- Destinations]),
    maps:merge(NativeTargets, ExternalTargets).

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
link_descriptor(Link = #{source_index := Source, destination_index := Destination,
        direction := Direction, classes := Classes}, Actors) ->
    #{module := SourceModule} = lists:nth(Source + 1, Actors),
    #{module := DestinationModule} = lists:nth(Destination + 1, Actors),
    Link#{direction := case Direction of incoming -> to_rtl; outgoing -> to_beam end,
        source_module => SourceModule, destination_module => DestinationModule,
        classes := [Class#{port => Port, tag => Tag, message_bits => DestinationModule:pack_width(Tag)}
            || Class = #{channel := #{port := Port, tag := Tag}} <- Classes]}.

-doc "Selects exactly one canonical source-bound crossing for an ordinary record without a port hint. Packs the record once, then checks same-tag classes including omitted constants. Rejects malformed records, missing or ambiguous classes; source packer errors propagate unchanged. Sender authentication and queue admission belong to the owner.".
-spec encode(link() | encoder_link(), tuple()) -> {byte(), non_neg_integer()}.
encode(#{source_module := Module, classes := Classes}, Message) when is_tuple(Message), tuple_size(Message) > 0 ->
    Tag = element(1, Message),
    Matching = [Class || Class = #{tag := Name} <- Classes, Name =:= Tag],
    case Matching of
        [] -> error({no_protocol_class, Tag});
        _ ->
            Packed = Module:pack(Message),
            Candidates = lists:usort(lists:append([canonical_candidate(Class, Packed) || Class <- Matching])),
            case Candidates of
                [Candidate] -> Candidate;
                [] -> error({no_protocol_class, Tag});
                _ -> error({ambiguous_protocol_classes, Tag, [Slot || {Slot, _} <- Candidates]})
            end
    end;
encode(_, Message) -> error({invalid_protocol_message, Message}).

%% Only the codec's deliberate canonical-frame rejection excludes a class; internal errors propagate.
-spec canonical_candidate(class() | codec_class(), bitstring()) -> [{byte(), non_neg_integer()}].
canonical_candidate(Class = #{slot := Slot, codec := Codec}, Packed) ->
    Frame = ordinary_frame(Class, Packed),
    case hls_protocol_codec:encode(Codec, Frame) of
        {ok, _} -> [{Slot, Frame}];
        {error, invalid_frame} -> []
    end.

-doc "Encodes an ordinary source output for exactly one crossing class. Uses the destination operation selector and checks omitted constants, reserved bits and padding. Sender PID authentication, queue capacity and sequence reservation belong to the owner.".
-spec encode(link() | encoder_link(), atom(), tuple()) -> {byte(), non_neg_integer()}.
encode(#{source_module := Module, classes := Classes}, Port, Message) ->
    Tag = element(1, Message),
    [Class = #{slot := Slot, codec := Codec}] =
        [C || C = #{port := P, tag := T} <- Classes, P =:= Port, T =:= Tag],
    Frame = ordinary_frame(Class, Module:pack(Message)),
    {ok, _} = hls_protocol_codec:encode(Codec, Frame),
    {Slot, Frame}.

%% The destination fixes the ordinary header while the source contributes the exact record bitstream.
-spec ordinary_frame(class() | codec_class(), bitstring()) -> non_neg_integer().
ordinary_frame(#{codec := #{value := Value}, message_bits := Width}, Packed) ->
    Width = bit_size(Packed),
    Payload = binary:decode_unsigned(hls_codec:pad_to(Packed, 96), little),
    (Value band 16#ffffffff) bor (Payload bsl 32).

-doc "Checks a canonical crossing frame and decodes its bound destination record, including a packed round trip. Caller authenticates the link/session and must acknowledge only after actual destination admission; failure is never permission to replay.".
-spec decode(link() | decoder_link(), byte(), non_neg_integer()) -> tuple().
decode(#{destination_module := Module, classes := Classes}, Slot, Frame) ->
    [#{tag := Tag, codec := Codec, message_bits := Width}] = [C || C = #{slot := I} <- Classes, I =:= Slot],
    {ok, _} = hls_protocol_codec:encode(Codec, Frame),
    <<Packed:Width/bitstring, _/bitstring>> = <<(Frame bsr 32):96/little>>,
    {Message, <<>>} = Module:unpack(Tag, Packed),
    Packed = Module:pack(Message),
    Message.
