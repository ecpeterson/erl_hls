-module(hls_protocol_mixed).
-moduledoc "Composes source-bound BEAM/native placement and DSLX bridges for hls_source_build. Derives retained hls_protocol_mixed_schema crossings; runtime packing and provider checks belong to hls_protocol_mixed_codec, while host admission, retirement and progress remain separate obligations.".

%% Mixed placement and retained views.
-export([plan/1, descriptor/1, transport/1]).

%% Bridge bundle emission.
-export([emit/1, write/2]).
-export_type([plan/0, descriptor/0, result/0, output/0, host_actor/0]).

%% Host bindings and target selection are complete before the native bridge can render.
-record(plan, {bridge :: hls_protocol_bridge:plan(), descriptor :: descriptor()}).
-doc "One ordinary BEAM actor's checked source identity, capacity, startup records and unique output recipients.".
-type host_actor() :: #{
    id := hls_protocol_topology:id(),
    module := module(),
    capacity := pos_integer(),
    outputs := #{atom() => hls_protocol_topology:destination()},
    startup := [tuple()],
    schemas := hls_host_codec:catalog(),
    output_schemas := #{atom() => [atom()]}
}.

%% Source actor indices stay global when host and native subsets are separated.
-type indexed_actor() :: {non_neg_integer(), hls_protocol_topology:actor()}.
%% Startup order is source-declared and independent of host placement.
-type startup() :: #{target := hls_protocol_topology:id(), delivery := cast, messages := [tuple()]}.

%% Logical targets map to global native indices or unchanged external stream identities.
-type targets() :: #{
    hls_protocol_topology:destination() =>
        {actor, non_neg_integer()} | {external, hls_protocol_topology:id()}
}.
%% The mixed session uses the bridge's checked return addresses.
-type endpoints() :: #{
    host := hls_source_config:endpoint(), control := hls_source_config:endpoint()
}.
%% Planning retains host ownership and crossing codecs before attachment is possible.
-type mixed_interface() :: #{
    host_actors := [non_neg_integer()], links := [hls_protocol_mixed_schema:link()]
}.
%% Emission binds the same host crossings to the native bridge's exact hardware identity.
-type attached_interface() :: #{
    host_actors := [non_neg_integer()],
    links := [hls_protocol_mixed_schema:link()],
    identity := binary()
}.

-doc "A complete checked mixed composition with source-bound host actors and native bridge. Retain unchanged in process; record schemas are source-bound while provider implementations may be updated compatibly. It contains no runtime session or device admission.".
-opaque plan() :: #plan{}.

-doc "Checked host actors, targets, crossing codecs and the static native bridge. The bridge and mixed attachment identities are added only by emission.".
-type descriptor() :: #{
    actors := #{non_neg_integer() => host_actor()},
    targets := targets(),
    mixed := mixed_interface(),
    application := hls_protocol_application_schema:application(),
    device := board,
    binding := endpoints(),
    bridge := hls_protocol_bridge:descriptor(),
    eligible := false
}.

-doc "The emitted mixed deployment with native attachment identity; source host actors, target ownership and codecs remain unchanged.".
-type result() :: #{
    actors := #{non_neg_integer() => host_actor()},
    targets := targets(),
    mixed := attached_interface(),
    application := hls_protocol_application_schema:application(),
    device := board,
    binding := endpoints(),
    bridge := hls_protocol_bridge:bridge(),
    eligible := false
}.

-doc "Generated native bridge files and the final mixed runtime deployment.".
-type output() :: hls_generated_files:output(result()).

-doc "Builds one framed native partition using hls_protocol_bridge's configuration; complementary actors run in BEAM. Requires one recipient per BEAM output, no BEAM-to-BEAM links, rectangle control and explicit activation. Writes mixed.etf for hls_protocol_mixed_stream and the usual bridge artifacts. Loaded codecs are checked against fresh source declarations. Generation failures create no output; I/O failures retain partial output; no mailbox replacement, progress, timing or device admission is granted.".
-spec write(hls_source_config:mixed() | file:filename() | plan(), file:filename()) -> result().
write(Config, Directory) ->
    hls_generated_files:write(emit(Config), Directory).

-doc "Checks a trusted mixed config or config filename without rendering hardware. Binds fresh source codecs, complementary host actors, unique output targets and native crossing classes before returning the complete plan. Trusted source constructors may have effects; retained record schemas are independent of later actor-module reloads; providers must preserve each descriptor's encoding contract.".
-spec plan(hls_source_config:mixed() | file:filename()) -> plan().
plan(Config) when is_map(Config) ->
    Build = hls_protocol_transport:plan(Config),
    #{
        whole_control := Control,
        bundle := Bundle = #{
            topology := #{actors := Actors, routes := Routes, startup := Startup},
            modules := Modules
        }
    } =
        hls_protocol_transport:descriptor(Build),
    BridgePlan = hls_protocol_bridge:plan(
        Build,
        maps:with([host, service, control, activation, inspection], Config)
    ),
    Bridge =
        #{native_indices := Native, links := Links, host := Host, service := Service} =
        hls_protocol_bridge:descriptor(BridgePlan),
    {NativeActors, HostPlacements} = lists:partition(
        fun({Index, _}) -> lists:member(Index, Native) end,
        lists:enumerate(0, Actors)
    ),
    HostIds = [Id || {_, #{id := Id}} <- HostPlacements],
    Owners = maps:from_list([{Id, board} || #{id := Id} <- Actors]),
    Application =
        #{partition := #{actors := BoundActors}} =
        hls_protocol_application_binding:bind(Bundle, Control, Owners, #{board => Host}),
    ByIndex = maps:from_list([{Index, Actor} || Actor = #{index := Index} <- BoundActors]),
    HostActors = maps:from_list([
        {Index, host_actor(maps:get(Index, ByIndex), Routes, Startup, Modules, HostIds)}
     || {Index, _} <- HostPlacements
    ]),
    Targets = targets(NativeActors, HostActors),
    MixedLinks = [link_descriptor(Link, ByIndex) || Link <- Links],
    Mixed = #{host_actors => lists:sort(maps:keys(HostActors)), links => MixedLinks},
    Descriptor = #{
        actors => HostActors,
        targets => Targets,
        mixed => Mixed,
        application => Application,
        device => board,
        binding => #{host => Host, control => Service},
        bridge => Bridge,
        eligible => false
    },
    #plan{bridge = BridgePlan, descriptor = Descriptor};
plan(Filename) ->
    plan(hls_source_config:read(Filename)).

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
    #{
        files => hls_generated_files:merge([
            BridgeFiles,
            #{"mixed.etf" => term_to_binary(Deployment, [deterministic])}
        ]),
        result => Deployment
    };
emit(Config) ->
    emit(plan(Config)).

%% Bind one host actor to its exact mailbox, ordered startup messages and checked output routes.
-spec host_actor(
    hls_protocol_application_schema:actor(),
    [hls_protocol_topology:route()],
    [startup()],
    #{module() => hls_local_actor:source() | hls_local_actor:artifact()},
    [hls_protocol_topology:id()]
) -> host_actor().
host_actor(
    #{id := Id, module := Module, schemas := Schemas, output_schemas := OutputSchemas},
    Routes,
    Startup,
    Modules,
    HostIds
) ->
    #{program := Program} = maps:get(Module, Modules),
    #{capacity := Capacity} = xls_actor_program:spec(Program),
    Outputs = host_outputs(Id, Module, Routes, HostIds),
    Messages = lists:append([
        Batch
     || #{target := Target, messages := Batch} <- Startup, Target =:= Id
    ]),
    #{
        id => Id,
        module => Module,
        capacity => Capacity,
        outputs => Outputs,
        startup => Messages,
        schemas => Schemas,
        output_schemas => OutputSchemas
    }.

%% Retain source port names while checking the supported single-recipient host routing model.
-spec host_outputs(
    hls_protocol_topology:id(),
    module(),
    [hls_protocol_topology:route()],
    [hls_protocol_topology:id()]
) -> #{atom() => hls_protocol_topology:destination()}.
host_outputs(Id, Module, Routes, HostIds) ->
    maps:from_list([
        {Port, host_destination(Id, Module, Port, Recipients, HostIds)}
     || #{source := {From, Port}, recipients := Recipients} <- Routes, From =:= Id
    ]).

%% Host routing addresses native actors by global index and preserves external stream identities.
-spec targets([indexed_actor()], #{non_neg_integer() => host_actor()}) -> targets().
targets(Native, HostActors) ->
    NativeTargets = maps:from_list([{{actor, Id}, {actor, Index}} || {Index, #{id := Id}} <- Native]),
    Destinations = lists:append([
        maps:values(Outputs)
     || #{outputs := Outputs} <- maps:values(HostActors)
    ]),
    ExternalTargets = maps:from_list([
        {Destination, Destination}
     || Destination = {external, _} <- Destinations
    ]),
    maps:merge(NativeTargets, ExternalTargets).

%% A BEAM output has one crossing or external recipient; host-to-host routing is unsupported.
-spec host_destination(
    hls_protocol_topology:id(),
    module(),
    atom(),
    [hls_protocol_topology:destination()],
    [hls_protocol_topology:id()]
) -> hls_protocol_topology:destination().
host_destination(Id, Module, Port, [Destination], HostIds) ->
    case Destination of
        {actor, To} ->
            case lists:member(To, HostIds) of
                false ->
                    Destination;
                true ->
                    hls_diagnostic:raise(
                        mixed,
                        unsupported_host_route,
                        <<"Mixed builds do not route messages between BEAM actors; place one endpoint in hardware.">>,
                        #{
                            actor => Id,
                            module => Module,
                            port => Port,
                            destination => Destination,
                            capability => beam_to_beam
                        }
                    )
            end;
        {external, _} ->
            Destination
    end;
host_destination(Id, Module, Port, Recipients, _) ->
    hls_diagnostic:raise(
        mixed,
        unsupported_host_fanout,
        <<"Each BEAM output in a mixed build must have exactly one recipient.">>,
        #{actor => Id, module => Module, port => Port, recipients => Recipients}
    ).

%% The bridge's destination codecs, not the sender's operation numbering, define crossing frames.
-spec link_descriptor(
    hls_protocol_partition:crossing(),
    #{non_neg_integer() => hls_protocol_application_schema:actor()}
) -> hls_protocol_mixed_schema:link().
link_descriptor(
    Link = #{
        source_index := Source,
        destination_index := Destination,
        direction := Direction,
        classes := Classes
    },
    Actors
) ->
    #{module := SourceModule, schemas := SourceSchemas} = maps:get(Source, Actors),
    #{module := DestinationModule, schemas := DestinationSchemas} = maps:get(Destination, Actors),
    Link#{
        direction :=
            case Direction of
                incoming -> to_rtl;
                outgoing -> to_beam
            end,
        source_module => SourceModule,
        destination_module => DestinationModule,
        classes := [bind_class(Class, SourceSchemas, DestinationSchemas) || Class <- Classes]
    }.

%% Source and destination share payload shape while the crossing owns its destination selector.
-spec bind_class(
    hls_protocol_partition:class(),
    hls_host_codec:catalog(),
    hls_host_codec:catalog()
) -> hls_protocol_mixed_schema:class().
bind_class(Class = #{channel := #{port := Port, tag := Tag}}, SourceSchemas, DestinationSchemas) ->
    #{codec := SourceRecord, width := Width} = maps:get(Tag, SourceSchemas),
    #{codec := DestinationRecord, width := Width} = maps:get(Tag, DestinationSchemas),
    Class#{
        port => Port,
        tag => Tag,
        message_bits => Width,
        source_record => SourceRecord,
        destination_record => DestinationRecord
    }.
