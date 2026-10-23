-module(hls_protocol_application).
-moduledoc "Builds a fresh source network with the shared framed application gateway and its exact host deployment binding.".
-export([write/2]).

-doc "Compiles the same trusted source config as hls_protocol_boundary, plus device and host (1..65535), into a fresh application directory. Uses explicit_start; rejects another activation mode, absent rectangle ingress and absent external endpoints. Binds loaded host codecs to captured source schemas and rejects conflicting external selectors. Returns a deployment for hls_partition_stream and writes deployment.etf. The gateway orders setup before start; started acknowledges actual network activation. Attachment identity detects mismatched builds, not malicious peers. Capacity, progress and native qualification remain unestablished; callers must drain events, honor source command preconditions and coordinate whole-application reset before replacement.".
-spec write(map(),file:filename()) -> map().
write(Config=#{device:=Device,host:=Host},Directory) when is_integer(Host),Host>0,Host<65536 ->
    case maps:get(activation,Config,explicit_start) of
        explicit_start->ok;
        Mode->error({application_requires_explicit_start,Mode})
    end,
    Boundary=hls_protocol_boundary:write(Config#{activation=>explicit_start},Directory),
    {ok,Bytes}=file:read_file(filename:join(Directory,"transport.etf")),
    %% Only the just-emitted local build is read, never a caller-supplied saved plan.
    #{bundle:=Bundle}=binary_to_term(Bytes),
    Deployment=deployment(Bundle,Boundary,Device,Host),
    Stage=filename:join(Directory,"application"),ok=file:make_dir(Stage),
    Binding=maps:get(Device,maps:get(devices,Deployment)),
    ok=xls_protocol_application:write(Binding,Stage),
    ok=sv_protocol_application:write(Binding,Boundary,Stage),
    ok=file:write_file(filename:join(Directory,"deployment.etf"),term_to_binary(Deployment,[deterministic]),[exclusive]),
    Files=["deployment.etf","application/gateway.x","application/protocol_application_top.sv"],
    Manifest=#{top=>protocol_application_top,activation=>explicit_start,eligible=>false,
        identity=>binary:encode_hex(maps:get(identity,Binding),lowercase),
        actors=>maps:get(actors,Boundary),externals=>maps:get(externals,Boundary),
        inputs=>[#{file=>list_to_binary(F),sha256=>digest(filename:join(Directory,F))}||F<-Files]},
    ok=file:write_file(filename:join(Stage,"manifest.json"),json:encode(Manifest),[exclusive]),
    Deployment.

%% Bind topology identity and source schemas to the exact emitted endpoint order.
-spec deployment(map(),map(),term(),1..65535) -> map().
deployment(Bundle=#{topology:=Topology=#{actors:=Actors,routes:=Routes,externals:=Externals},modules:=Modules},
        Boundary=#{activation:=explicit_start,externals:=Outputs,inputs:=Inputs},Device,Host) ->
    true=lists:member(#{name=><<"ingress_data">>,width=>194},Inputs),
    Ids=[iolist_to_binary(io_lib:format("~0tp",[Id]))||#{id:=Id}<-Externals],
    Ids=[Id||#{id:=Id}<-Outputs],
    Interfaces=hls_actor_interface:from_modules(maps:keys(Modules)),
    maps:foreach(fun(M,A)->check_codec(M,A,maps:get(M,Interfaces)) end,Modules),
    ok=check_externals(Topology,Modules,Interfaces),
    Bound=[A#{identity=>{actor,Id},device=>Device}||A=#{id:=Id}<-Actors],
    Ingresses=hls_partition_ingress:lower(Topology,Bound,Interfaces),
    PortRoutes=[R#{source:={{actor,Id},Port}}||R=#{source:={Id,Port}}<-Routes],
    Ports=[E#{port=>"external_"++integer_to_list(I)}||{I,E}<-lists:enumerate(0,Externals)],
    Partition=#{actors=>Bound,routes=>PortRoutes,ingresses=>Ingresses},
    Raw=hls_partition_wire:binding(Partition,Device,Host,#{ingresses=>Ingresses,externals=>Ports}),
    Binding=(maps:remove(identity,Raw))#{activation=>explicit_start},
    Identity=crypto:hash(sha256,term_to_binary({source_protocol_application,2,Bundle,Boundary,Device,Binding},[deterministic])),
    #{partition=>Partition,devices=>#{Device=>Binding#{identity=>Identity}},
      source_boundary=>Boundary,eligible=>false}.

%% Field names/order, types, selectors and packed width must match fresh compiler records.
-spec check_codec(module(),map(),map()) -> ok.
check_codec(Module,#{spec:=#{message_names:=Names},plan:=#{records:=Records}},Interface) ->
    lists:foreach(fun({Op,Name})->
        #{selector:=Op,fields:=Fields}=hls_actor_interface:schema(Interface,Name),
        Op=Module:pack_tag(Name),
        [SourceFields]=[Fs||{attribute,_,record,{N,Fs}}<-Records,N=:=Name],
        Layout=[{element(3,element(3,F)),hls_type:descriptor(T)}||{typed_record_field,F,T}<-SourceFields],
        Layout=[{N,T}||#{name:=N,type:=T}<-Fields],
        Width=lists:sum([hls_type:width(T)||{_,T}<-Layout]),
        Width=Module:pack_width(Name)
    end,lists:enumerate(3,Names)).

%% A host event selector cannot ambiguously identify different producers' record layouts.
-spec check_externals(map(),map(),map()) -> ok.
check_externals(#{actors:=Actors,routes:=Routes,externals:=Externals},Modules,Interfaces) ->
    ById=maps:from_list([{Id,M}||#{id:=Id,module:=M}<-Actors]),
    lists:foreach(fun(#{id:=External})->
        Domains=lists:append([begin
            M=maps:get(Id,ById),Tags=hls_actor_interface:output_schemas(maps:get(M,Interfaces),Port),
            hls_protocol_schema:domains(maps:get(M,Modules),Tags)
        end||#{source:={Id,Port},recipients:=Recipients}<-Routes,lists:member({external,External},Recipients)]),
        _=lists:foldl(fun(D=#{value:=V},Seen)->
            Op=(V bsr 24) band 255,
            case maps:find(Op,Seen) of
                error->Seen#{Op=>D};
                {ok,D}->Seen;
                {ok,_}->error({ambiguous_application_event,External,Op})
            end
        end,#{},Domains),ok
    end,Externals).

%% Bind exact emitted inputs before the separate compiler invocation.
-spec digest(file:filename()) -> binary().
digest(File) ->
    {ok,Bytes}=file:read_file(File),binary:encode_hex(crypto:hash(sha256,Bytes),lowercase).
