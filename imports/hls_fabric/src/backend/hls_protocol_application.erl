-module(hls_protocol_application).
-moduledoc "Builds a fresh source network with the shared framed application gateway and its exact host deployment binding.".
-export([emit/1, write/2]).

-doc "Compiles the same trusted source config as hls_protocol_boundary, plus device and host (1..65535), into a fresh application directory. Uses explicit_start; rejects another activation mode, absent rectangle ingress and absent external endpoints. Binds loaded host codecs to captured source schemas and rejects conflicting external selectors. Returns a deployment for hls_partition_stream and writes deployment.etf. The gateway orders setup before start; started acknowledges actual network activation. inspection => process adds the common endpoint-2 debug stream and network/inspection.json plus a trusted local inspection.etf catalog. Attachment identity detects mismatched builds, not malicious peers. native_actors is rejected because this gateway does not carry crossing links. Capacity, progress and native qualification remain unestablished; callers must drain events, honor source command preconditions and coordinate whole-application reset before replacement.".
-spec write(map() | file:filename(), file:filename()) -> map().
write(Config, Directory) ->
    hls_generated_files:write(emit(Config), Directory).

-doc "Generates the application bundle without writing output, returning relative filenames with IO data and the deployment binding. Accepts a trusted source config map or a filename containing one map; source paths remain relative to the caller. Preparation loads sources and invokes trusted constructors. Templates and support inputs are read; generation errors create no output.".
-spec emit(map() | file:filename()) -> hls_generated_files:output().
emit(Config=#{device:=Device,host:=Host}) when is_integer(Host),Host>0,Host<65536 ->
    case maps:is_key(native_actors,Config) of
        true->error(partition_application_gateway_unavailable);false->ok
    end,
    case maps:get(activation,Config,explicit_start) of
        explicit_start->ok;
        Mode->error({application_requires_explicit_start,Mode})
    end,
    Build = hls_protocol_transport:plan(Config),
    #{files := BoundaryFiles, result := #{boundary := Boundary, transport := #{bundle := Bundle}}} =
        hls_protocol_boundary:emit(Build,(maps:with([inspection],Config))#{activation=>explicit_start}),
    Deployment=deployment(Bundle,Boundary,Device,Host),
    Binding=maps:get(Device,maps:get(devices,Deployment)),
    Generated = hls_generated_files:merge([BoundaryFiles, #{
        "application/gateway.x" => xls_protocol_application:emit(Binding),
        "application/protocol_application_top.sv" => sv_protocol_application:emit(Binding, Boundary),
        "deployment.etf" => term_to_binary(Deployment, [deterministic])}]),
    Files=["deployment.etf","application/gateway.x","application/protocol_application_top.sv"]++
        case maps:get(inspection,Boundary) of none->[];_->["network/inspection.json","network/inspection.etf"] end,
    Manifest=#{top=>protocol_application_top,activation=>explicit_start,eligible=>false,
        inspection=>maps:get(inspection,Boundary),
        identity=>binary:encode_hex(maps:get(identity,Binding),lowercase),
        actors=>maps:get(actors,Boundary),externals=>maps:get(externals,Boundary),
        inputs=>[#{file=>list_to_binary(F),sha256=>hls_generated_files:hash(maps:get(F, Generated))}||F<-Files]},
    #{files => hls_generated_files:merge([Generated, #{"application/manifest.json" => json:encode(Manifest)}]),
      result => Deployment};
emit(Filename) when is_list(Filename); is_binary(Filename) -> emit(hls_source_config:read(Filename)).

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
