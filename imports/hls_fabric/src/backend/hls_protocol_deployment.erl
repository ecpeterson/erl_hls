-module(hls_protocol_deployment).
-moduledoc "Fresh source-bound framed deployments with typed application control and events. Placement belongs to the build configuration; routing follows derived actor ownership.".
-export([write/2]).

-doc "Builds each configured device from the same sources/topology, then checks complete disjoint ownership and crossing codecs. devices maps arbitrary device IDs to native_actors, host and service; limits supplies crossings, commands and events. Writes numbered role directories and deployment.etf for hls_protocol_stream:start_application/3. At least two proper source partitions are required, each with crossing inputs/outputs and rectangle control. All devices form one retirement/reset domain. Partial failed output is retained. This does not grant capacity, progress, timing or device admission.".
-spec write(map(),file:filename()) -> map().
write(Config=#{devices:=Devices,limits:=Limits=#{commands:=Commands,events:=Events}},Directory)
        when map_size(Devices)>=2,is_integer(Commands),Commands>0,is_integer(Events),Events>=2 ->
    ok=file:make_dir(Directory),
    Common=maps:without([devices,limits,native_actors,host,service],Config),
    Builds=[begin
        #{native_actors:=_,host:=_,service:=_}=Placement,
        true=maps:without([native_actors,host,service],Placement)=:=#{},
        Name="role"++integer_to_list(Index),Path=filename:join(Directory,Name),
        _=hls_protocol_bridge:write(maps:merge(Common,Placement),Path),
        {Device,Name,read(filename:join(Path,"bridge.etf")),read(filename:join(Path,"transport.etf"))}
    end||{Index,{Device,Placement}}<-lists:enumerate(0,lists:sort(maps:to_list(Devices)))],
    [{_,_,_,#{bundle:=Bundle=#{topology:=Topology=#{actors:=Actors}}}}|_]=Builds,
    %% Recompilation must retain the same normalized graph and external port order.
    [Topology=Other||{_,_,_,#{bundle:=#{topology:=Other}}}<-Builds],
    Sources=provenance(Bundle),
    [Sources=provenance(B)||{_,_,_,#{bundle:=B}}<-Builds],
    Bridges=maps:from_list([{Device,B}||{Device,_,B,_}<-Builds]),
    Plan=#{devices=>Bridges,actors=>length(Actors),limits=>Limits},
    Sessions=maps:from_list([{D,I}||{I,D}<-lists:enumerate(lists:sort(maps:keys(Devices)))]),
    _=hls_protocol_relay_queue:new(Plan,Sessions),
    Returns=[{H,S}||#{host:=H,service:=S}<-maps:values(Bridges)],
    true=length(Returns)=:=length(lists:usort(Returns)),
    Owners=maps:from_list([{maps:get(id,lists:nth(I+1,Actors)),D}
        ||{D,#{native_indices:=Indices}}<-maps:to_list(Bridges),I<-Indices]),
    Hosts=maps:map(fun(_,#{host:=H})->H end,Bridges),
    Application=hls_protocol_application_binding:bind(Bundle,Owners,Hosts),
    Deployment=Plan#{application=>Application,eligible=>false,
        directories=>maps:from_list([{D,Name}||{D,Name,_,_}<-Builds])},
    ok=file:write_file(filename:join(Directory,"deployment.etf"),term_to_binary(Deployment,[deterministic]),[exclusive]),
    Deployment.

%% Only outputs of this fresh build enter the host descriptor; never deserialize transport input.
-spec read(file:filename()) -> map().
read(Path)->{ok,Bytes}=file:read_file(Path),binary_to_term(Bytes).

%% Ignore fresh symbolic references but require identical preprocessed source and planner provenance.
-spec provenance(map()) -> map().
provenance(#{modules:=Modules})->
    maps:map(fun(_,#{plan:=Plan})->
        maps:with([source_sha256,artifact_sha256,planner_md5],xls_statem_plan:manifest(Plan))
    end,Modules).
