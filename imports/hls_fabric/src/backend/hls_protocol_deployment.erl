-module(hls_protocol_deployment).
-moduledoc "Fresh source-bound framed deployments with typed application control and events. Placement belongs to the build configuration; routing follows derived actor ownership.".
-export([emit/1, write/2]).

%% A role keeps its checked transport separate from the framed adapter's options.
-type role() :: #{device := term(), directory := string(), transport := hls_protocol_transport:build(), options := map()}.

-doc "Writes a fresh deployment and numbered role bundles from a trusted config map or filename. Each device supplies native_actors, host and service; limits bounds crossings, commands and events. Requires complete disjoint ownership, distinct return endpoints and rectangle control. Generation failures create no output; I/O failures retain partial output. All roles share one retirement/reset domain; the result remains ineligible for device admission.".
-spec write(map() | file:filename(), file:filename()) -> map().
write(Config, Directory) ->
    hls_generated_files:write(emit(Config), Directory).

-doc "Generates all role bundles and the host deployment without writing output. Accepts a trusted source config map or a filename containing one map; source paths remain relative to the caller. Prepares sources once, checks static cross-role routing before rendering bridges, and returns relative filenames with IO data plus the deployment. Preparation loads sources and invokes trusted constructors; template and support-library reads remain.".
-spec emit(map() | file:filename()) -> hls_generated_files:output().
emit(Config = #{devices := Devices, limits := Limits = #{commands := Commands, events := Events}})
        when map_size(Devices) >= 2, is_integer(Commands), Commands > 0, is_integer(Events), Events >= 2 ->
    Common = maps:without([devices, limits, native_actors, host, service], Config),
    Program = hls_protocol_transport:prepare(Common),
    Bundle = #{topology := #{actors := Actors}} = hls_protocol_transport:bundle(Program),
    ok = placement(Devices, Actors),
    Roles = [role(Device, Index, Placement, Common, Program)
        || {Index, {Device, Placement}} <- lists:enumerate(0, lists:sort(maps:to_list(Devices)))],
    RoutingDevices = maps:from_list([{Device, routing_device(Build)}
        || #{device := Device, transport := Build} <- Roles]),
    _ = hls_protocol_routing:plan(#{devices => RoutingDevices, actors => length(Actors), limits => Limits}),
    Outputs = [{Device, Name, hls_protocol_bridge:emit(Build, Options)}
        || #{device := Device, directory := Name, transport := Build, options := Options} <- Roles],
    Bridges = maps:from_list([{Device, Bridge}
        || {Device, _, #{result := #{bridge := Bridge}}} <- Outputs]),
    Plan = #{devices => Bridges, actors => length(Actors), limits => Limits},
    Owners = maps:from_list([{Id, D} || {D, #{native_actors := Ids}} <- maps:to_list(Devices), Id <- Ids]),
    Hosts = maps:map(fun(_, #{host := H}) -> H end, Bridges),
    Application = hls_protocol_application_binding:bind(Bundle, hls_protocol_transport:control(Program), Owners, Hosts),
    Deployment = Plan#{application => Application, eligible => false,
        directories => maps:from_list([{D, Name} || #{device := D, directory := Name} <- Roles])},
    Files = hls_generated_files:merge([hls_generated_files:prefix(Name, RoleFiles)
        || {_, Name, #{files := RoleFiles}} <- Outputs] ++
        [#{"deployment.etf" => term_to_binary(Deployment, [deterministic])}]),
    #{files => Files, result => Deployment};
emit(Filename) when is_list(Filename); is_binary(Filename) -> emit(hls_source_config:read(Filename)).

%% Reject missing, duplicate and unknown ownership together, before planning or writing a role.
-spec placement(map(), [map()]) -> ok.
placement(Devices, Actors) ->
    lists:foreach(fun endpoint/1, maps:values(Devices)),
    Known = lists:sort([Id || #{id := Id} <- Actors]),
    Owned = lists:sort(lists:append([Ids || #{native_actors := Ids} <- maps:values(Devices)])),
    case Owned =:= Known of
        true -> ok;
        false -> error({invalid_deployment_ownership, Known, Owned})
    end,
    Returns = [{Host, Service} || #{host := Host, service := Service} <- maps:values(Devices)],
    case length(Returns) =:= length(lists:usort(Returns)) of
        true -> ok;
        false -> error({duplicate_deployment_endpoints, Returns})
    end.

%% Device terms are user configuration; reject extra keys and malformed endpoint addresses.
-spec endpoint(map()) -> ok.
endpoint(Placement = #{native_actors := Ids, host := Host, service := Service})
        when map_size(Placement) =:= 3, is_list(Ids), Ids =/= [],
             is_integer(Host), Host > 0, Host < 65536,
             is_integer(Service), Service > 0, Service < 65536, Host =/= Service -> ok;
endpoint(Other) -> error({invalid_deployment_device, Other}).

%% Only placement changes between roles; all source facts come from the same program value.
-spec role(term(), non_neg_integer(), map(), map(), hls_protocol_transport:program()) -> role().
role(Device, Index, Placement = #{native_actors := Ids}, Common, Program) ->
    Options = (maps:with([arithmetic_groups], Common))#{native_actors => Ids},
    #{device => Device, directory => "role" ++ integer_to_list(Index),
      transport => hls_protocol_transport:plan(Program, Options),
      options => maps:with([host, service, control, activation, inspection], maps:merge(Common, Placement))}.

%% The framed bridge copies these same checked transport fields into its host descriptor.
-spec routing_device(hls_protocol_transport:build()) -> hls_protocol_routing:device().
routing_device(Build) ->
    #{fabric := #{sources := Sources, crossings := Crossings}} = hls_protocol_transport:descriptor(Build),
    #{native_indices => [I || #{index := I} <- Sources], links => Crossings}.
