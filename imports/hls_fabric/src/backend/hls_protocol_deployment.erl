-module(hls_protocol_deployment).
-moduledoc "Fresh source-bound framed deployments with typed application control and events. Placement belongs to the build configuration; routing follows derived actor ownership.".
-export([write/2]).

%% A role keeps its checked transport separate from the framed adapter's options.
-type role() :: #{device := term(), directory := string(), transport := hls_protocol_transport:build(), options := map()}.

-doc "Prepares one source program for all devices, checks complete disjoint ownership and distinct return endpoints, then plans every role before creating output. devices maps arbitrary device IDs to native_actors, host and service; limits supplies crossings, commands and events. Writes numbered role directories and deployment.etf for hls_protocol_stream:start_application/3. At least two proper partitions are required, each with crossing inputs/outputs and rectangle control. Crossing codecs and relay limits are checked after bridge emission. All devices form one retirement/reset domain. Later adapter or I/O failures retain partial output. This does not grant capacity, progress, timing or device admission.".
-spec write(map(), file:filename()) -> map().
write(Config = #{devices := Devices, limits := Limits = #{commands := Commands, events := Events}}, Directory)
        when map_size(Devices) >= 2, is_integer(Commands), Commands > 0, is_integer(Events), Events >= 2 ->
    Common = maps:without([devices, limits, native_actors, host, service], Config),
    Program = hls_protocol_transport:prepare(Common),
    Bundle = #{topology := #{actors := Actors}} = hls_protocol_transport:bundle(Program),
    ok = placement(Devices, Actors),
    Roles = [role(Device, Index, Placement, Common, Program)
        || {Index, {Device, Placement}} <- lists:enumerate(0, lists:sort(maps:to_list(Devices)))],
    ok = file:make_dir(Directory),
    Bridges = maps:from_list([begin
        #{bridge := Bridge} = hls_protocol_bridge:emit(Build, Options, filename:join(Directory, Name)),
        {Device, Bridge}
    end || #{device := Device, directory := Name, transport := Build, options := Options} <- Roles]),
    Plan = #{devices => Bridges, actors => length(Actors), limits => Limits},
    Sessions = maps:from_list([{D, I} || {I, D} <- lists:enumerate(lists:sort(maps:keys(Devices)))]),
    _ = hls_protocol_relay_queue:new(Plan, Sessions),
    Owners = maps:from_list([{Id, D} || {D, #{native_actors := Ids}} <- maps:to_list(Devices), Id <- Ids]),
    Hosts = maps:map(fun(_, #{host := H}) -> H end, Bridges),
    Application = hls_protocol_application_binding:bind(Bundle, Owners, Hosts),
    Deployment = Plan#{application => Application, eligible => false,
        directories => maps:from_list([{D, Name} || #{device := D, directory := Name} <- Roles])},
    ok = file:write_file(filename:join(Directory, "deployment.etf"), term_to_binary(Deployment, [deterministic]), [exclusive]),
    Deployment.

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
