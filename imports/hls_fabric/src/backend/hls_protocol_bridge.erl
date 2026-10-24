-module(hls_protocol_bridge).
-moduledoc "Builds a source partition with reset-owned framing, class credits and exact delivery acknowledgments. Hardware remains DSLX; the peer owns transport retirement and bounded routing.".
-export([write/2, emit/3]).
-export_type([result/0]).

-doc "The emitted bridge manifest, host bridge descriptor and source transport descriptor, all from the same role build.".
-type result() :: #{manifest := map(), bridge := map(), transport := map()}.

-doc "Freshly builds a native_actors source partition with an explicit control => rectangle adapter and explicit activation, plus host/service endpoints in 1..65535. Writes bridge.etf, a bound manifest, DSLX and a mechanical pin adapter. Supports nonempty incoming/outgoing cuts and external endpoints, at most 256 combined credit/data/external contenders. Each incoming class has one credit; each outgoing pair retains one unacknowledged delivery. Sequence 0xffffffff is reserved. Callers must serialize frames, acknowledge only after reserving destination capacity and completing its forwarding write and retire every old transport before coordinated reset and new nonzero sessions. Identity detects mismatched builds, not malicious peers. Inspection, CDC, automatic recovery, capacity/progress admission and native device qualification are absent. Failed builds retain partial output.".
-spec write(map(),file:filename()) -> map().
write(Config = #{native_actors := _},Directory) ->
    #{manifest := Manifest} = emit(hls_protocol_transport:plan(Config), maps:with([host, service, control, activation, inspection], Config), Directory),
    Manifest.

-doc "Emits a planned partition through its boundary and framed bridge. Config supplies host/service, rectangle control and network modes; Build fixes source and native placement. Retain the unchanged in-process build and loaded source codecs. Returns bridge/transport descriptors with the manifest, avoiding intermediate-file reads. Requires a fresh directory; partial failed output is retained.".
-spec emit(hls_protocol_transport:build(), map(), file:filename()) -> result().
emit(Build,Config=#{host:=Host,service:=Service},Directory)
        when is_integer(Host),is_integer(Service),Host>0,Host<65536,Service>0,Service<65536,Host=/=Service ->
    case maps:keys(maps:without([host, service, control, activation, inspection], Config)) of
        [] -> ok;
        Unknown -> error({unsupported_bridge_options, lists:sort(Unknown)})
    end,
    explicit_start=maps:get(activation,Config,explicit_start),
    rectangle=maps:get(control,Config),
    %% A whole-network plan cannot be silently treated as a framed partition.
    #{fabric := #{crossings := _}} = hls_protocol_transport:descriptor(Build),
    #{boundary := Boundary = #{inputs := Inputs, externals := Externals}, transport := Plan} =
        hls_protocol_boundary:emit(Build,(maps:with([inspection],Config))#{activation=>explicit_start},Directory),
    true=lists:member(#{name=><<"ingress_data">>,width=>194},Inputs),
    #{fabric:=#{sources:=Sources,crossings:=Cross},bundle:=#{topology:=#{actors:=Actors}}}=Plan,
    Incoming=[L||L=#{direction:=incoming}<-Cross],Outgoing=[L||L=#{direction:=outgoing}<-Cross],
    true=Incoming=/=[] andalso Outgoing=/=[] andalso Externals=/=[],
    true=lists:all(fun(#{index:=I,slots:=N})->I<65536 andalso N>0 andalso N<256 end,Cross),
    Credits=[#{link=>I,slot=>K}||#{index:=I,classes:=Cs}<-Incoming,#{slot:=K}<-Cs],
    true=length(Credits)+length(Outgoing)+length(Externals)=<256,
    Libraries=[begin {ok,Bytes0}=file:read_file(filename:join(code:priv_dir(hls_fabric),"xls/lib/"++File)),
        #{file=>list_to_binary(File),sha256=>binary:encode_hex(crypto:hash(sha256,Bytes0),lowercase)}
        end||File<-["protocol_bridge.x","protocol_framing.x","protocol_rectangle.x"]],
    Identity=crypto:hash(sha256,term_to_binary({source_partition_bridge,2,Host,Service,rectangle,Boundary,Plan,
        Libraries},[deterministic])),
    Bridge=#{identity=>Identity,host=>Host,service=>Service,links=>Cross,control=>rectangle,libraries=>Libraries,
        native_indices=>[I||#{index:=I}<-Sources],actors=>length(Actors),externals=>Externals,
        incoming=>Incoming,outgoing=>Outgoing,credits=>Credits,eligible=>false},
    Manifest=xls_protocol_bridge:write(Bridge,Boundary,Directory),
    ok=file:write_file(filename:join(Directory,"bridge.etf"),term_to_binary(Bridge,[deterministic]),[exclusive]),
    #{manifest => Manifest, bridge => Bridge, transport => Plan}.
