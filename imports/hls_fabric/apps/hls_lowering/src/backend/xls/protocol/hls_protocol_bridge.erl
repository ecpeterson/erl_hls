-module(hls_protocol_bridge).
-moduledoc "Composes one source partition with reset-owned framing, class credits and exact delivery acknowledgments. Deployment and mixed builders use its retained boundary; xls_protocol_bridge renders the hardware, while peers remain responsible for transport retirement and bounded routing.".

%% Checked bridge composition and views.
-export([plan/2, descriptor/1, transport/1]).

%% Target bundle emission and convenience writes.
-export([emit/1, emit/2, write/2, write/3]).
-export_type([plan/0, options/0, descriptor/0, bridge/0, manifest/0, credit/0, result/0, output/0]).

-doc "Framing endpoints and adapter selection for an already checked native placement. Activation remains explicit; inspection is unsupported.".
-type options() :: hls_source_config:bridge_options().

-doc "One incoming crossing class whose previous capture ownership determines its credit.".
-type credit() :: #{link := 0..((1 bsl 16) - 1), slot := byte()}.

%% Framing ownership is unchanged when emission adds attachment identity and support hashes.
%% erlfmt:ignore Map-type field fragments are not complete type expressions.
-define(INTERFACE_FIELDS,
    frame_layout := hls_frame_layout:layout(),
    host := 1 .. ((1 bsl 16) - 1),
    service := 1 .. ((1 bsl 16) - 1),
    links := [hls_protocol_partition:crossing()],
    control := rectangle,
    control_adapter := hls_protocol_control:hardware(),
    native_indices := [non_neg_integer()],
    actors := non_neg_integer(),
    externals := [xls_protocol_boundary:group()],
    incoming := [hls_protocol_partition:crossing()],
    outgoing := [hls_protocol_partition:crossing()],
    credits := [credit()],
    eligible := false
).

-doc "Checked framing endpoints, ownership, crossing classes and external groups before attachment identity exists.".
-type descriptor() :: #{?INTERFACE_FIELDS}.

-doc "The finalized host bridge descriptor, requiring its raw SHA-256 attachment identity and hashed support-library inventory.".
-type bridge() :: #{
    ?INTERFACE_FIELDS, identity := binary(), libraries := [xls_protocol_network:component()]
}.

-doc "The serialized hardware-facing bridge manifest, including compact crossing codecs and generated-input hashes.".
-type manifest() :: xls_protocol_bridge:manifest().

-doc "Bridge files paired with concrete final manifest, host bridge and transport descriptors.".
-type output() :: hls_generated_files:output(result()).

%% Static bridge ownership is checked before the boundary or its parents are emitted.
-record(plan, {boundary :: hls_protocol_boundary:plan(), interface :: descriptor()}).

-doc "A checked framed partition from plan/2. Retain unchanged in process with compatible provider type and encoding contracts. Build identity and library hashes are added only during emission; no device or progress admission is granted.".
-opaque plan() :: #plan{}.

-doc "The emitted bridge manifest, host bridge descriptor and source transport descriptor, all from the same role build.".
-type result() :: #{
    manifest := manifest(), bridge := bridge(), transport := hls_protocol_transport:descriptor()
}.

-doc "Freshly builds a native_actors source partition with an explicit control => rectangle adapter and explicit activation, plus host/service endpoints in 1..65535. Writes bridge.etf, a bound manifest, DSLX and a mechanical pin adapter. Supports nonempty incoming/outgoing cuts and external endpoints, at most 256 combined credit/data/external contenders. Each incoming class has one credit; each outgoing pair retains one unacknowledged delivery. Sequence 0xffffffff is reserved. Callers must serialize frames, acknowledge only after reserving destination capacity and completing its forwarding write and retire every old transport before coordinated reset and new nonzero sessions. Identity detects mismatched builds, not malicious peers. Inspection, CDC, automatic recovery, capacity/progress admission and native device qualification are absent. An unchanged composition plan may also be written directly. Generation failures create no output; I/O failures retain partial output.".
-spec write(hls_source_config:bridge() | file:filename() | plan(), file:filename()) -> manifest().
write(Config, Directory) ->
    #{manifest := Manifest} = hls_generated_files:write(emit(Config), Directory),
    Manifest.

-doc "Writes emit/2's planned bridge bundle to a fresh directory and returns its manifest/bridge/transport result. Generation precedes output creation; I/O failures retain partial output.".
-spec write(hls_protocol_transport:build(), options(), file:filename()) -> result().
write(Build, Options, Directory) ->
    hls_generated_files:write(emit(Build, Options), Directory).

-doc "Generates a bridge bundle from a trusted native_actors source config map or a filename containing one map. Source paths remain relative to the caller. Preparation loads sources and invokes trusted constructors; an unchanged plan/2 value skips preparation and layout checks. No output is written. Returns relative filenames with IO data and named manifest/bridge/transport descriptors.".
-spec emit(hls_source_config:bridge() | file:filename() | plan()) -> output().
emit(#plan{
    boundary = BoundaryPlan,
    interface = Interface = #{host := Host, service := Service, control_adapter := Hardware}
}) ->
    #{files := BoundaryFiles, result := #{boundary := Boundary, transport := Transport}} =
        hls_protocol_boundary:emit(BoundaryPlan),
    Libraries = [
        begin
            {ok, Bytes} = file:read_file(
                filename:join([code:priv_dir(hls_lowering), "xls/lib", File])
            ),
            #{file => File, sha256 => hls_generated_files:hash(Bytes)}
        end
     || File <-
            [<<"protocol_bridge.x">>, <<"protocol_framing.x">>, <<"protocol_envelope.x">>] ++
                maps:get(bridge_libraries, Hardware)
    ],
    Content = hls_protocol_identity:boundary(Transport, BoundaryFiles),
    Identity = crypto:hash(
        sha256,
        term_to_binary(
            {source_partition_bridge, 4, Host, Service, Hardware, Boundary, Content, Libraries}, [
                deterministic
            ]
        )
    ),
    Bridge = Interface#{identity => Identity, libraries => Libraries},
    #{files := BridgeFiles, result := Manifest} = xls_protocol_bridge:emit(
        Bridge, Boundary, BoundaryFiles
    ),
    #{
        files => hls_generated_files:merge([
            BoundaryFiles,
            BridgeFiles,
            #{"bridge.etf" => term_to_binary(Bridge, [deterministic])}
        ]),
        result => #{manifest => Manifest, bridge => Bridge, transport => Transport}
    };
emit(Config = #{native_actors := _}) ->
    emit(
        hls_protocol_transport:plan(Config),
        maps:with([host, service, control, activation, inspection], Config)
    );
emit(Filename) when is_list(Filename); is_binary(Filename) ->
    emit(hls_source_config:read(Filename)).

-doc "Checks a framed partition before rendering its network, boundary or bridge. Requires host/service endpoints in 1..65535, rectangle control and explicit activation. Checks boundary control ports, nonempty incoming/outgoing cuts and external endpoints, crossing indices/slots and the combined 256-contender budget. Options cannot change the source or placement. No templates or support libraries are read here; the transport owns checked source snapshots and receiver layouts.".
-spec plan(hls_protocol_transport:build(), options()) -> plan().
plan(Build, Config = #{host := Host, service := Service, control := _}) ->
    ok = endpoints(Host, Service),
    case maps:keys(maps:without([host, service, control, activation, inspection], Config)) of
        [] ->
            ok;
        Unknown ->
            hls_diagnostic:raise(
                bridge,
                unsupported_bridge_options,
                <<"Bridge options are host, service, control, activation and inspection.">>,
                #{options => lists:sort(Unknown)}
            )
    end,
    #{
        ingress := Control,
        fabric := Fabric = #{sources := Sources},
        bundle := #{topology := #{actors := Actors}}
    } = hls_protocol_transport:descriptor(Build),
    Cross = maps:get(crossings, Fabric, []),
    Hardware = hls_protocol_control:framed(Control, Config),
    ok = inspection(maps:get(inspection, Config, none)),
    BoundaryPlan = hls_protocol_boundary:plan(Build, (maps:with([inspection], Config))#{
        activation => explicit_start
    }),
    Boundary = #{externals := Externals} = hls_protocol_boundary:descriptor(BoundaryPlan),
    ok = hls_protocol_control:check_boundary(Hardware, Boundary),
    Incoming = [L || L = #{direction := incoming} <- Cross],
    Outgoing = [L || L = #{direction := outgoing} <- Cross],
    case
        [
            Kind
         || {Kind, Entries} <- [{incoming, Incoming}, {outgoing, Outgoing}, {external, Externals}],
            Entries =:= []
        ]
    of
        [] ->
            ok;
        Missing ->
            hls_diagnostic:raise(
                bridge,
                missing_bridge_paths,
                <<"A framed partition requires incoming and outgoing crossings and an external endpoint.">>,
                #{missing => Missing, native_actors => [I || #{index := I} <- Sources]}
            )
    end,
    lists:foreach(fun wire_limits/1, Cross),
    Credits = [
        #{link => I, slot => K}
     || #{index := I, classes := Cs} <- Incoming, #{slot := K} <- Cs
    ],
    Contenders = length(Credits) + length(Outgoing) + length(Externals),
    case Contenders =< 256 of
        true ->
            ok;
        false ->
            hls_diagnostic:raise(
                bridge,
                bridge_contender_limit,
                <<"Bridge credits, outgoing links and external streams exceed the framing arbiter limit.">>,
                #{
                    actual => Contenders,
                    maximum => 256,
                    credits => length(Credits),
                    outgoing => length(Outgoing),
                    externals => length(Externals)
                }
            )
    end,
    #plan{
        boundary = BoundaryPlan,
        interface = #{
            frame_layout => maps:get(frame_layout, Fabric),
            host => Host,
            service => Service,
            links => Cross,
            control => maps:get(kind, Hardware),
            control_adapter => Hardware,
            native_indices => [I || #{index := I} <- Sources],
            actors => length(Actors),
            externals => Externals,
            incoming => Incoming,
            outgoing => Outgoing,
            credits => Credits,
            eligible => false
        }
    }.

%% This older packet bridge has no inspection lane; never discard native debug ports.
-spec inspection(none | process) -> ok.
inspection(none) ->
    ok;
inspection(process) ->
    hls_diagnostic:raise(
        bridge,
        bridge_inspection_unavailable,
        <<"This framed bridge has no process-inspection lane; use explicit domain inspection pins.">>,
        #{path => [inspection], value => process}
    );
inspection(Other) ->
    _ = hls_protocol_inspection:mode(Other),
    ok.

-doc "Returns checked bridge endpoints, actor ownership, crossing classes and external groups. There is no identity or library inventory until emit/1 reads support and hashes emitted bytes. Treat the descriptor as read-only; it is suitable for routing and host-layout checks, not attachment.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{interface = Interface}) -> Interface.

-doc "Returns the retained transport placement for source, topology and receiver-layout inspection. Reuses the checked snapshot without recompiling or rendering; retain it unchanged.".
-spec transport(plan()) -> hls_protocol_transport:build().
transport(#plan{boundary = Build}) -> hls_protocol_boundary:transport(Build).

-doc "Plans and emits a framed partition without writing output. Equivalent to emit(plan(Build, Options)); source and placement remain fixed. Returns the final bridge/transport descriptors and manifest; support reads and identity hashing follow layout checks.".
-spec emit(hls_protocol_transport:build(), options()) -> output().
emit(Build, Options) -> emit(plan(Build, Options)).

%% Framed addresses are nonzero words, and a bridge cannot address itself.
-spec endpoints(hls_source_config:endpoint(), hls_source_config:endpoint()) -> ok.
endpoints(Host, Service) when
    is_integer(Host),
    is_integer(Service),
    Host > 0,
    Host < 65536,
    Service > 0,
    Service < 65536,
    Host =/= Service
->
    ok;
endpoints(Host, Service) ->
    hls_diagnostic:raise(
        bridge,
        invalid_bridge_endpoints,
        <<"Bridge host and service must be different addresses in 1..65535.">>,
        #{host => Host, service => Service}
    ).

%% Source-derived crossings must fit the fixed packet's link and class fields.
-spec wire_limits(hls_protocol_partition:crossing()) -> ok.
wire_limits(#{index := Index, slots := Slots}) when Index < 65536, Slots > 0, Slots < 256 -> ok;
wire_limits(#{index := Index, slots := Slots}) ->
    hls_diagnostic:raise(
        bridge,
        bridge_wire_limit,
        <<"A bridge crossing needs a 16-bit link index and between 1 and 255 class slots.">>,
        #{link => Index, slots => Slots, maximum_link => 65535, maximum_slots => 255}
    ).
