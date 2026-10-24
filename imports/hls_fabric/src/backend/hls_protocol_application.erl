-module(hls_protocol_application).
-moduledoc "Builds a fresh source network with the shared framed application gateway and its exact host deployment binding.".
-export([write/2]).

-doc "Compiles the same trusted source config as hls_protocol_boundary, plus device and host (1..65535), into a fresh application directory. Uses explicit_start; rejects another activation mode, absent rectangle ingress and absent external endpoints. Binds loaded host codecs to captured source schemas and rejects conflicting external selectors. Returns a deployment for hls_partition_stream and writes deployment.etf. The gateway orders setup before start; started acknowledges actual network activation. inspection => process adds the common endpoint-2 debug stream and network/inspection.json plus a trusted local inspection.etf catalog. Attachment identity detects mismatched builds, not malicious peers. native_actors is rejected because this gateway does not carry crossing links. Capacity, progress and native qualification remain unestablished; callers must drain events, honor source command preconditions and coordinate whole-application reset before replacement.".
-spec write(map(),file:filename()) -> map().
write(Config=#{device:=Device,host:=Host},Directory) when is_integer(Host),Host>0,Host<65536 ->
    case maps:is_key(native_actors,Config) of
        true->error(partition_application_gateway_unavailable);false->ok
    end,
    case maps:get(activation,Config,explicit_start) of
        explicit_start->ok;
        Mode->error({application_requires_explicit_start,Mode})
    end,
    Build = hls_protocol_transport:plan(Config),
    #{boundary := Boundary, transport := #{bundle := Bundle}} =
        hls_protocol_boundary:emit(Build,(maps:with([inspection],Config))#{activation=>explicit_start},Directory),
    Deployment=deployment(Bundle,Boundary,Device,Host),
    Stage=filename:join(Directory,"application"),ok=file:make_dir(Stage),
    Binding=maps:get(Device,maps:get(devices,Deployment)),
    ok=xls_protocol_application:write(Binding,Stage),
    ok=sv_protocol_application:write(Binding,Boundary,Stage),
    ok=file:write_file(filename:join(Directory,"deployment.etf"),term_to_binary(Deployment,[deterministic]),[exclusive]),
    Files=["deployment.etf","application/gateway.x","application/protocol_application_top.sv"]++
        case maps:get(inspection,Boundary) of none->[];_->["network/inspection.json","network/inspection.etf"] end,
    Manifest=#{top=>protocol_application_top,activation=>explicit_start,eligible=>false,
        inspection=>maps:get(inspection,Boundary),
        identity=>binary:encode_hex(maps:get(identity,Binding),lowercase),
        actors=>maps:get(actors,Boundary),externals=>maps:get(externals,Boundary),
        inputs=>[#{file=>list_to_binary(F),sha256=>digest(filename:join(Directory,F))}||F<-Files]},
    ok=file:write_file(filename:join(Stage,"manifest.json"),json:encode(Manifest),[exclusive]),
    Deployment.

%% Bind the same source-checked codecs used by framed deployments to one gateway identity.
-spec deployment(map(),map(),term(),1..65535) -> map().
deployment(Bundle=#{topology:=#{actors:=Actors,externals:=Externals}},
        Boundary=#{activation:=explicit_start,externals:=Outputs,inputs:=Inputs},Device,Host) ->
    true=lists:member(#{name=><<"ingress_data">>,width=>194},Inputs),
    Ids=[iolist_to_binary(io_lib:format("~0tp",[Id]))||#{id:=Id}<-Externals],
    Ids=[Id||#{id:=Id}<-Outputs],
    Owners=maps:from_list([{Id,Device}||#{id:=Id}<-Actors]),
    Application=#{devices:=#{Device:=Binding}}=hls_protocol_application_binding:bind(Bundle,Owners,#{Device=>Host}),
    Identity=crypto:hash(sha256,term_to_binary({source_protocol_application,2,Bundle,Boundary,Device,Binding},[deterministic])),
    Application#{devices:=#{Device=>Binding#{identity=>Identity}},source_boundary=>Boundary,eligible=>false}.

%% Bind exact emitted inputs before the separate compiler invocation.
-spec digest(file:filename()) -> binary().
digest(File) ->
    {ok,Bytes}=file:read_file(File),binary:encode_hex(crypto:hash(sha256,Bytes),lowercase).
