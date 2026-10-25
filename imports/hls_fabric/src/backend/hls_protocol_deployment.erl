-module(hls_protocol_deployment).
-moduledoc "Fresh source-bound framed deployments with typed application control and events. Placement belongs to the build configuration; routing follows derived actor ownership.".
-export([plan/1, descriptor/1, routing/1, emit/1, write/2]).
-export_type([plan/0, descriptor/0, result/0, output/0]).

%% Every role is fully checked before any role renders composition hardware.
-type role() :: #{device := hls_source_config:device(), directory := string(), bridge := hls_protocol_bridge:plan()}.
%% Retain the validated graph and every role from one unchanged source program.
-record(plan, {roles :: [role()], routing :: hls_protocol_routing:plan(), descriptor :: descriptor()}).

-doc "A complete checked deployment: all role layouts, shared source bindings and routing. Retain unchanged in process with source codecs loaded; emission adds attachment identities.".
-opaque plan() :: #plan{}.

-doc "All static bridge interfaces, host bindings, budgets and role directories. Devices have no generated-byte identities or support-library hashes before emission.".
-type descriptor() :: #{devices := #{hls_source_config:device() => hls_protocol_bridge:descriptor()},
    actors := pos_integer(), limits := hls_source_config:limits(),
    application := hls_protocol_application_binding:application(), eligible := false,
    directories := #{hls_source_config:device() => string()}}.

-doc "The emitted deployment, retaining checked host bindings and limits while each role gains its exact bridge identity and support hashes.".
-type result() :: #{devices := #{hls_source_config:device() => hls_protocol_bridge:bridge()},
    actors := pos_integer(), limits := hls_source_config:limits(),
    application := hls_protocol_application_binding:application(), eligible := false,
    directories := #{hls_source_config:device() => string()}}.

-doc "Every numbered role bundle and the final deployment binding, before output I/O.".
-type output() :: hls_generated_files:output(result()).

-doc "Writes a fresh deployment and numbered role bundles from a trusted config map or filename. Each device supplies native_actors, host and service; limits bounds crossings, commands and events. Requires complete disjoint ownership, distinct return endpoints and rectangle control. Generation failures create no output; I/O failures retain partial output. All roles share one retirement/reset domain; the result remains ineligible for device admission.".
-spec write(hls_source_config:deployment() | file:filename() | plan(), file:filename()) -> result().
write(Config, Directory) ->
    hls_generated_files:write(emit(Config), Directory).

-doc "Checks all roles from one freshly prepared source program without rendering hardware. Accepts a trusted config map or filename; checks complete disjoint ownership, bridge layouts, crossing routes and host codecs before returning. Source constructors may have effects. Retain the plan unchanged with its loaded codecs; saved deployment terms are not planning inputs.".
-spec plan(hls_source_config:deployment() | file:filename()) -> plan().
plan(Config = #{devices := Devices, limits := Limits = #{commands := Commands, events := Events}})
        when map_size(Devices) >= 2, is_integer(Commands), Commands > 0, is_integer(Events), Events >= 2 ->
    Common = maps:without([devices, limits, native_actors, host, service], Config),
    Program = hls_protocol_transport:prepare(Common),
    Bundle = #{topology := #{actors := Actors}} = hls_protocol_transport:bundle(Program),
    ok = placement(Devices, Actors),
    Roles = [role(Device, Index, Placement, Common, Program)
        || {Index, {Device, Placement}} <- lists:enumerate(0, lists:sort(maps:to_list(Devices)))],
    Interfaces = maps:from_list([{Device, hls_protocol_bridge:descriptor(Bridge)}
        || #{device := Device, bridge := Bridge} <- Roles]),
    Routing = hls_protocol_routing:plan(#{devices => Interfaces, actors => length(Actors), limits => Limits}),
    Owners = maps:from_list([{Id, D} || {D, #{native_actors := Ids}} <- maps:to_list(Devices), Id <- Ids]),
    Hosts = maps:map(fun(_, #{host := H}) -> H end, Interfaces),
    Application = hls_protocol_application_binding:bind(Bundle, hls_protocol_transport:control(Program), Owners, Hosts),
    Descriptor = #{devices => Interfaces, actors => length(Actors), limits => Limits,
        application => Application, eligible => false,
        directories => maps:from_list([{D, Name} || #{device := D, directory := Name} <- Roles])},
    #plan{roles = Roles, routing = Routing, descriptor = Descriptor};
plan(Filename) when is_list(Filename); is_binary(Filename) -> plan(hls_source_config:read(Filename)).

-doc "Returns every checked static role, host binding and role directory. No role has an attachment identity until emission; this view is for build inspection rather than runtime attachment.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{descriptor = Descriptor}) -> Descriptor.

-doc "Returns the exact checked cross-role graph retained during planning. Its ownership/routes have no sessions or credits and can be reused for inspection without revalidating the deployment.".
-spec routing(plan()) -> hls_protocol_routing:plan().
routing(#plan{routing = Routing}) -> Routing.

-doc "Renders every checked role and the final deployment without writing output. A trusted config map/filename is planned first; a retained plan neither recompiles sources nor repeats host/routing checks. Templates and support libraries are read only during emission.".
-spec emit(hls_source_config:deployment() | file:filename() | plan()) -> output().
emit(#plan{roles = Roles, descriptor = Descriptor}) ->
    Outputs = [{Device, Name, hls_protocol_bridge:emit(BridgePlan)}
        || #{device := Device, directory := Name, bridge := BridgePlan} <- Roles],
    Bridges = maps:from_list([{Device, Bridge}
        || {Device, _, #{result := #{bridge := Bridge}}} <- Outputs]),
    Deployment = Descriptor#{devices := Bridges},
    Files = hls_generated_files:merge([hls_generated_files:prefix(Name, RoleFiles)
        || {_, Name, #{files := RoleFiles}} <- Outputs] ++
        [#{"deployment.etf" => term_to_binary(Deployment, [deterministic])}]),
    #{files => Files, result => Deployment};
emit(Config) -> emit(plan(Config)).

%% Reject missing, duplicate and unknown ownership together, before planning or writing a role.
-spec placement(#{hls_source_config:device() => hls_source_config:role()}, [hls_protocol_topology:actor()]) -> ok.
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
-spec endpoint(hls_source_config:role()) -> ok.
endpoint(Placement = #{native_actors := Ids, host := Host, service := Service})
        when map_size(Placement) =:= 3, is_list(Ids), Ids =/= [],
             is_integer(Host), Host > 0, Host < 65536,
             is_integer(Service), Service > 0, Service < 65536, Host =/= Service -> ok;
endpoint(Other) -> error({invalid_deployment_device, Other}).

%% Only placement changes between roles; all source facts come from the same program value.
-spec role(hls_source_config:device(), non_neg_integer(), hls_source_config:role(),
    hls_source_config:network(), hls_protocol_transport:program()) -> role().
role(Device, Index, Placement = #{native_actors := Ids}, Common, Program) ->
    Options = (maps:with([arithmetic_groups], Common))#{native_actors => Ids},
    Build = hls_protocol_transport:plan(Program, Options),
    BridgeOptions = maps:with([host, service, control, activation, inspection], maps:merge(Common, Placement)),
    #{device => Device, directory => "role" ++ integer_to_list(Index),
      bridge => hls_protocol_bridge:plan(Build, BridgeOptions)}.
