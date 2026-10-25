-module(hls_protocol_bridge).
-moduledoc "Builds a source partition with reset-owned framing, class credits and exact delivery acknowledgments. Hardware remains DSLX; the peer owns transport retirement and bounded routing.".
-export([write/2, write/3, emit/1, emit/2]).
-export_type([result/0]).

-doc "The emitted bridge manifest, host bridge descriptor and source transport descriptor, all from the same role build.".
-type result() :: #{manifest := map(), bridge := map(), transport := map()}.

-doc "Freshly builds a native_actors source partition with an explicit control => rectangle adapter and explicit activation, plus host/service endpoints in 1..65535. Writes bridge.etf, a bound manifest, DSLX and a mechanical pin adapter. Supports nonempty incoming/outgoing cuts and external endpoints, at most 256 combined credit/data/external contenders. Each incoming class has one credit; each outgoing pair retains one unacknowledged delivery. Sequence 0xffffffff is reserved. Callers must serialize frames, acknowledge only after reserving destination capacity and completing its forwarding write and retire every old transport before coordinated reset and new nonzero sessions. Identity detects mismatched builds, not malicious peers. Inspection, CDC, automatic recovery, capacity/progress admission and native device qualification are absent. Generation failures create no output; I/O failures retain partial output.".
-spec write(map() | file:filename(), file:filename()) -> map().
write(Config, Directory) ->
    #{manifest := Manifest} = hls_generated_files:write(emit(Config), Directory),
    Manifest.

-doc "Writes emit/2's planned bridge bundle to a fresh directory and returns its manifest/bridge/transport result. Generation precedes output creation; I/O failures retain partial output.".
-spec write(hls_protocol_transport:build(), map(), file:filename()) -> result().
write(Build, Options, Directory) ->
    hls_generated_files:write(emit(Build, Options), Directory).

-doc "Generates a bridge bundle from a trusted native_actors source config map or a filename containing one map. Source paths remain relative to the caller. Preparation loads sources and invokes trusted constructors; no output is written. Returns relative filenames with IO data and named manifest/bridge/transport descriptors.".
-spec emit(map() | file:filename()) -> hls_generated_files:output().
emit(Config = #{native_actors := _}) ->
    emit(hls_protocol_transport:plan(Config), maps:with([host, service, control, activation, inspection], Config));
emit(Filename) when is_list(Filename); is_binary(Filename) -> emit(hls_source_config:read(Filename)).

-doc "Generates a planned partition through its boundary and framed bridge without writing output. Options supplies host/service, rectangle control and network modes; the unchanged in-process Build fixes source and native placement. Returns relative filenames with IO data and named bridge/transport descriptors with the manifest. Template and support-library reads remain; retain the loaded source codecs.".
-spec emit(hls_protocol_transport:build(), map()) -> hls_generated_files:output().
emit(Build, Config = #{host := Host, service := Service, control := _})
        when is_integer(Host),is_integer(Service),Host>0,Host<65536,Service>0,Service<65536,Host=/=Service ->
    case maps:keys(maps:without([host, service, control, activation, inspection], Config)) of
        [] -> ok;
        Unknown -> error({unsupported_bridge_options, lists:sort(Unknown)})
    end,
    #{ingress := Control} = hls_protocol_transport:descriptor(Build),
    Hardware = hls_protocol_control:framed(Control, Config),
    %% A whole-network plan cannot be silently treated as a framed partition.
    #{fabric := #{crossings := _}} = hls_protocol_transport:descriptor(Build),
    #{files := BoundaryFiles,
      result := #{boundary := Boundary = #{externals := Externals}, transport := Plan}} =
        hls_protocol_boundary:emit(Build,(maps:with([inspection],Config))#{activation=>explicit_start}),
    ok = hls_protocol_control:check_boundary(Hardware, Boundary),
    #{fabric:=#{sources:=Sources,crossings:=Cross},bundle:=#{topology:=#{actors:=Actors}}}=Plan,
    Incoming=[L||L=#{direction:=incoming}<-Cross],Outgoing=[L||L=#{direction:=outgoing}<-Cross],
    true=Incoming=/=[] andalso Outgoing=/=[] andalso Externals=/=[],
    true=lists:all(fun(#{index:=I,slots:=N})->I<65536 andalso N>0 andalso N<256 end,Cross),
    Credits=[#{link=>I,slot=>K}||#{index:=I,classes:=Cs}<-Incoming,#{slot:=K}<-Cs],
    true=length(Credits)+length(Outgoing)+length(Externals)=<256,
    Libraries=[begin {ok,Bytes0}=file:read_file(filename:join([code:priv_dir(hls_fabric),"xls/lib",File])),
        #{file=>File,sha256=>binary:encode_hex(crypto:hash(sha256,Bytes0),lowercase)}
        end||File<-[<<"protocol_bridge.x">>,<<"protocol_framing.x">>] ++ maps:get(bridge_libraries, Hardware)],
    Content=hls_protocol_identity:boundary(Plan,BoundaryFiles),
    Identity=crypto:hash(sha256,term_to_binary({source_partition_bridge,4,Host,Service,Hardware,Boundary,Content,
        Libraries},[deterministic])),
    Bridge=#{identity=>Identity,host=>Host,service=>Service,links=>Cross,control=>maps:get(kind,Hardware),control_adapter=>Hardware,libraries=>Libraries,
        native_indices=>[I||#{index:=I}<-Sources],actors=>length(Actors),externals=>Externals,
        incoming=>Incoming,outgoing=>Outgoing,credits=>Credits,eligible=>false},
    #{files := BridgeFiles, result := Manifest} = xls_protocol_bridge:emit(Bridge, Boundary, BoundaryFiles),
    #{files => hls_generated_files:merge([BoundaryFiles, BridgeFiles,
        #{"bridge.etf" => term_to_binary(Bridge, [deterministic])}]),
      result => #{manifest => Manifest, bridge => Bridge, transport => Plan}}.
