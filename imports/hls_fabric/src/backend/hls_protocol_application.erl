-module(hls_protocol_application).
-moduledoc "Builds a fresh source network with the shared framed application gateway and its exact host deployment binding.".
-export([transport/1, plan/1, descriptor/1, emit/1, write/2]).
-export_type([plan/0, descriptor/0, result/0, output/0]).

%% The boundary owns source/layout checks; host bindings are validated against that same build.
-record(plan, {boundary :: hls_protocol_boundary:plan(),
    application :: hls_protocol_application_binding:application(hls_protocol_application_binding:gateway()),
    device :: hls_source_config:device()}).

-doc "A complete checked application composition, retained unchanged with its source codecs loaded. Emission adds generated-byte identities; this is not a saved-plan input or device admission.".
-opaque plan() :: #plan{}.

-doc "Source-checked host bindings and the static external boundary. Device attachment identities and the emitted inspection catalog are absent until emission.".
-type descriptor() :: #{partition := hls_protocol_application_binding:partition(),
    devices := #{hls_source_config:device() => hls_protocol_application_binding:gateway()},
    source_boundary := hls_protocol_boundary:descriptor(), eligible := false}.

-doc "Final application deployment with emitted boundary evidence and a hardware identity for its checked gateway.".
-type result() :: #{partition := hls_protocol_application_binding:partition(),
    devices := #{hls_source_config:device() => hls_protocol_application_binding:attached_gateway()},
    source_boundary := hls_protocol_boundary:manifest(), eligible := false}.

-doc "Generated application files paired with the exact final host deployment.".
-type output() :: hls_generated_files:output(result()).

-doc "Compiles the same trusted source config as hls_protocol_boundary, plus device and host (1..65535), into a fresh application directory. Uses explicit_start; rejects another activation mode, absent rectangle ingress and absent external endpoints. Binds loaded host codecs to captured source schemas and rejects conflicting external selectors. Returns a deployment for hls_partition_stream and writes deployment.etf. The gateway orders setup before start; started acknowledges actual network activation. inspection => process adds the common endpoint-2 debug stream and network/inspection.json plus a trusted local inspection.etf catalog. Attachment identity detects mismatched builds, not malicious peers. native_actors is rejected because this gateway does not carry crossing links. Capacity, progress and native qualification remain unestablished; callers must drain events, honor source command preconditions and coordinate whole-application reset before replacement.".
-spec write(hls_source_config:application() | file:filename() | plan(), file:filename()) -> result().
write(Config, Directory) ->
    hls_generated_files:write(emit(Config), Directory).

-doc "Checks a trusted application config or config filename through source, boundary and host binding without rendering hardware. Requires one whole native placement, explicit activation and compatible loaded host codecs. The returned plan owns the complete checked composition; source paths are relative to the caller and trusted constructors may have effects.".
-spec plan(hls_source_config:application() | file:filename()) -> plan().
plan(Config=#{device:=Device,host:=Host}) when is_integer(Host),Host>0,Host<65536 ->
    case maps:is_key(native_actors,Config) of
        true -> hls_diagnostic:raise(application, partition_application_gateway_unavailable,
            <<"The whole-application gateway cannot carry crossing links; select bridge, mixed or deployment for a partition.">>,
            #{field => [native_actors]});
        false -> ok
    end,
    case maps:get(activation,Config,explicit_start) of
        explicit_start->ok;
        Mode -> hls_diagnostic:raise(application, application_requires_explicit_start,
            <<"Framed applications require explicit_start activation.">>, #{field => [activation], value => Mode})
    end,
    Build = hls_protocol_transport:plan(Config),
    Transport = #{ingress := Control} = hls_protocol_transport:descriptor(Build),
    Hardware = hls_protocol_control:framed(Control, Config),
    BoundaryPlan = hls_protocol_boundary:plan(Build,
        (maps:with([inspection], Config))#{activation => explicit_start}),
    StaticBoundary = hls_protocol_boundary:descriptor(BoundaryPlan),
    Application = bind(Transport, StaticBoundary, Device, Host, Hardware),
    #plan{boundary = BoundaryPlan, application = Application, device = Device};
plan(Filename) when is_list(Filename); is_binary(Filename) -> plan(hls_source_config:read(Filename)).

-doc "Returns the checked application bindings and boundary before emission. It contains no attachment identity or generated-byte hashes; retain the descriptor as a read-only view of the plan.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{boundary = Boundary, application = Application}) ->
    Application#{source_boundary => hls_protocol_boundary:descriptor(Boundary), eligible => false}.

-doc "Renders a checked plan or plans a trusted config map/filename before rendering. Returns relative files and the final deployment, without output writes. A retained plan needs no source reread or host-binding check; keep its loaded source codecs unchanged. Templates and support inputs are read during emission.".
-spec emit(hls_source_config:application() | file:filename() | plan()) -> output().
emit(#plan{boundary = BoundaryPlan, application = Application, device = Device}) ->
    #{files := BoundaryFiles, result := #{boundary := Boundary, transport := Transport}} =
        hls_protocol_boundary:emit(BoundaryPlan),
    Deployment = deployment(Application, Transport, Boundary, BoundaryFiles, Device),
    Binding = #{control_adapter := Hardware} = maps:get(Device, maps:get(devices, Deployment)),
    GatewayFiles = hls_generated_files:prefix("application", xls_protocol_application:emit(Binding)),
    Generated = hls_generated_files:merge([BoundaryFiles, GatewayFiles, #{
        "application/protocol_application_top.sv" => sv_protocol_application:emit(Binding, Boundary),
        "deployment.etf" => term_to_binary(Deployment, [deterministic])}]),
    Files=maps:keys(GatewayFiles)++["deployment.etf","application/protocol_application_top.sv"]++
        case maps:get(inspection,Boundary) of none->[];_->["network/inspection.json","network/inspection.etf"] end,
    Manifest=#{frame_layout=>maps:get(frame_layout,Boundary),top=>protocol_application_top,activation=>explicit_start,eligible=>false,control_adapter=>Hardware,
        inspection=>maps:get(inspection,Boundary),
        identity=>binary:encode_hex(maps:get(identity,Binding),lowercase),
        actors=>maps:get(actors,Boundary),externals=>maps:get(externals,Boundary),
        inputs=>[#{file=>list_to_binary(F),sha256=>hls_generated_files:hash(maps:get(F, Generated))}||F<-Files]},
    #{files => hls_generated_files:merge([Generated, #{"application/manifest.json" => json:encode(Manifest)}]),
      result => Deployment};
emit(Config) -> emit(plan(Config)).

%% Validate host codecs and external numbering against the checked interface before rendering.
-spec bind(hls_protocol_transport:descriptor(), hls_protocol_boundary:descriptor(),
    hls_source_config:device(), hls_source_config:endpoint(), hls_protocol_control:hardware()) ->
    hls_protocol_application_binding:application(hls_protocol_application_binding:gateway()).
bind(#{whole_control := Control, bundle := Bundle = #{topology := #{actors := Actors, externals := Externals}}},
        Boundary = #{activation := explicit_start, externals := Outputs}, Device, Host, Hardware) ->
    ok = hls_protocol_control:check_boundary(Hardware, Boundary),
    Ids = [iolist_to_binary(io_lib:format("~0tp", [Id])) || #{id := Id} <- Externals],
    Ids = [Id || #{id := Id} <- Outputs],
    Owners = maps:from_list([{Id, Device} || #{id := Id} <- Actors]),
    Application = #{devices := #{Device := Binding}} =
        hls_protocol_application_binding:bind(Bundle, Control, Owners, #{Device => Host}),
    Application#{devices := #{Device => Binding#{control_adapter => Hardware}}}.

%% Identity covers the emitted boundary and exact source files after all bindings are checked.
-spec deployment(hls_protocol_application_binding:application(hls_protocol_application_binding:gateway()),
    hls_protocol_transport:descriptor(), hls_protocol_boundary:manifest(),
    hls_generated_files:files(), hls_source_config:device()) -> result().
deployment(Application = #{devices := Devices}, Transport, Boundary, Files, Device) ->
    Binding = maps:get(Device, Devices),
    Content = hls_protocol_identity:boundary(Transport, Files),
    Identity = crypto:hash(sha256, term_to_binary(
        {source_protocol_application, 4, Content, Boundary, Device, Binding}, [deterministic])),
    Application#{devices := #{Device => Binding#{identity => Identity}},
        source_boundary => Boundary, eligible => false}.

-doc "Returns the retained transport placement for source, topology and layout inspection. Treat it as read-only; this accessor does not prepare sources or render hardware.".
-spec transport(plan()) -> hls_protocol_transport:build().
transport(#plan{boundary = Child}) -> hls_protocol_boundary:transport(Child).
