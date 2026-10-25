-module(hls_protocol_bridge).
-moduledoc "Builds a source partition with reset-owned framing, class credits and exact delivery acknowledgments. Hardware remains DSLX; the peer owns transport retirement and bounded routing.".
-export([plan/2, descriptor/1, write/2, write/3, emit/1, emit/2]).
-export_type([plan/0, result/0]).

%% Static bridge ownership is checked before the boundary or its parents are emitted.
-record(plan, {boundary :: hls_protocol_boundary:plan(), interface :: map()}).

-doc "A checked framed partition from plan/2. Retain unchanged in process with its source codecs loaded. Build identity and library hashes are added only during emission; no device or progress admission is granted.".
-opaque plan() :: #plan{}.

-doc "The emitted bridge manifest, host bridge descriptor and source transport descriptor, all from the same role build.".
-type result() :: #{manifest := map(), bridge := map(), transport := map()}.

-doc "Freshly builds a native_actors source partition with an explicit control => rectangle adapter and explicit activation, plus host/service endpoints in 1..65535. Writes bridge.etf, a bound manifest, DSLX and a mechanical pin adapter. Supports nonempty incoming/outgoing cuts and external endpoints, at most 256 combined credit/data/external contenders. Each incoming class has one credit; each outgoing pair retains one unacknowledged delivery. Sequence 0xffffffff is reserved. Callers must serialize frames, acknowledge only after reserving destination capacity and completing its forwarding write and retire every old transport before coordinated reset and new nonzero sessions. Identity detects mismatched builds, not malicious peers. Inspection, CDC, automatic recovery, capacity/progress admission and native device qualification are absent. An unchanged composition plan may also be written directly. Generation failures create no output; I/O failures retain partial output.".
-spec write(map() | file:filename() | plan(), file:filename()) -> map().
write(Config, Directory) ->
    #{manifest := Manifest} = hls_generated_files:write(emit(Config), Directory),
    Manifest.

-doc "Writes emit/2's planned bridge bundle to a fresh directory and returns its manifest/bridge/transport result. Generation precedes output creation; I/O failures retain partial output.".
-spec write(hls_protocol_transport:build(), map(), file:filename()) -> result().
write(Build, Options, Directory) ->
    hls_generated_files:write(emit(Build, Options), Directory).

-doc "Generates a bridge bundle from a trusted native_actors source config map or a filename containing one map. Source paths remain relative to the caller. Preparation loads sources and invokes trusted constructors; an unchanged plan/2 value skips preparation and layout checks. No output is written. Returns relative filenames with IO data and named manifest/bridge/transport descriptors.".
-spec emit(map() | file:filename() | plan()) -> hls_generated_files:output().
emit(#plan{boundary = BoundaryPlan,
        interface = Interface = #{host := Host, service := Service, control_adapter := Hardware}}) ->
    #{files := BoundaryFiles, result := #{boundary := Boundary, transport := Transport}} =
        hls_protocol_boundary:emit(BoundaryPlan),
    Libraries = [begin
        {ok, Bytes} = file:read_file(filename:join([code:priv_dir(hls_fabric), "xls/lib", File])),
        #{file => File, sha256 => hls_generated_files:hash(Bytes)}
    end || File <- [<<"protocol_bridge.x">>, <<"protocol_framing.x">>] ++ maps:get(bridge_libraries, Hardware)],
    Content = hls_protocol_identity:boundary(Transport, BoundaryFiles),
    Identity = crypto:hash(sha256, term_to_binary({source_partition_bridge, 4, Host, Service,
        Hardware, Boundary, Content, Libraries}, [deterministic])),
    Bridge = Interface#{identity => Identity, libraries => Libraries},
    #{files := BridgeFiles, result := Manifest} = xls_protocol_bridge:emit(Bridge, Boundary, BoundaryFiles),
    #{files => hls_generated_files:merge([BoundaryFiles, BridgeFiles,
        #{"bridge.etf" => term_to_binary(Bridge, [deterministic])}]),
      result => #{manifest => Manifest, bridge => Bridge, transport => Transport}};
emit(Config = #{native_actors := _}) ->
    emit(hls_protocol_transport:plan(Config), maps:with([host, service, control, activation, inspection], Config));
emit(Filename) when is_list(Filename); is_binary(Filename) -> emit(hls_source_config:read(Filename)).

-doc "Checks a framed partition before rendering its network, boundary or bridge. Requires host/service endpoints in 1..65535, rectangle control and explicit activation. Checks boundary control ports, nonempty incoming/outgoing cuts and external endpoints, crossing indices/slots and the combined 256-contender budget. Options cannot change the source or placement. No templates or support libraries are read here; the transport already owns lowered receivers.".
-spec plan(hls_protocol_transport:build(), map()) -> plan().
plan(Build, Config = #{host := Host, service := Service, control := _})
        when is_integer(Host), is_integer(Service), Host > 0, Host < 65536,
             Service > 0, Service < 65536, Host =/= Service ->
    case maps:keys(maps:without([host, service, control, activation, inspection], Config)) of
        [] -> ok;
        Unknown -> error({unsupported_bridge_options, lists:sort(Unknown)})
    end,
    #{ingress := Control, fabric := #{sources := Sources, crossings := Cross},
        bundle := #{topology := #{actors := Actors}}} = hls_protocol_transport:descriptor(Build),
    Hardware = hls_protocol_control:framed(Control, Config),
    BoundaryPlan = hls_protocol_boundary:plan(Build, (maps:with([inspection], Config))#{activation => explicit_start}),
    Boundary = #{externals := Externals} = hls_protocol_boundary:descriptor(BoundaryPlan),
    ok = hls_protocol_control:check_boundary(Hardware, Boundary),
    Incoming = [L || L = #{direction := incoming} <- Cross],
    Outgoing = [L || L = #{direction := outgoing} <- Cross],
    true = Incoming =/= [] andalso Outgoing =/= [] andalso Externals =/= [],
    true = lists:all(fun(#{index := I, slots := N}) -> I < 65536 andalso N > 0 andalso N < 256 end, Cross),
    Credits = [#{link => I, slot => K} || #{index := I, classes := Cs} <- Incoming, #{slot := K} <- Cs],
    true = length(Credits) + length(Outgoing) + length(Externals) =< 256,
    #plan{boundary = BoundaryPlan,
        interface = #{host => Host, service => Service, links => Cross, control => maps:get(kind, Hardware),
            control_adapter => Hardware, native_indices => [I || #{index := I} <- Sources],
            actors => length(Actors), externals => Externals,
            incoming => Incoming, outgoing => Outgoing, credits => Credits, eligible => false}}.

-doc "Returns checked bridge endpoints, actor ownership, crossing classes and external groups. There is no identity or library inventory until emit/1 reads support and hashes emitted bytes. Treat the descriptor as read-only; it is suitable for routing and host-layout checks, not attachment.".
-spec descriptor(plan()) -> map().
descriptor(#plan{interface = Interface}) -> Interface.

-doc "Plans and emits a framed partition without writing output. Equivalent to emit(plan(Build, Options)); source and placement remain fixed. Returns the final bridge/transport descriptors and manifest; support reads and identity hashing follow layout checks.".
-spec emit(hls_protocol_transport:build(), map()) -> hls_generated_files:output().
emit(Build, Options) -> emit(plan(Build, Options)).
