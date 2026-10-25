-module(hls_protocol_deployment).
-moduledoc "Fresh source-bound framed deployments with typed application control and events. Placement belongs to the build configuration; routing follows derived actor ownership.".
-export([plan/1, descriptor/1, routing/1, transports/1, emit/1, write/2]).
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
    Crossings = length([L || #{links := Links} <- maps:values(Interfaces),
        L = #{direction := outgoing} <- Links]),
    case maps:get(crossings, Limits) of
        Maximum when Crossings =< Maximum -> ok;
        Maximum -> hls_diagnostic:raise(deployment, crossing_limit,
            <<"The deployment crossing limit is smaller than its source-derived routes.">>,
            #{path => [limits, crossings], actual => Crossings, maximum => Maximum})
    end,
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

-doc "Returns every role's retained transport placement for source, topology and receiver-layout inspection. All roles share one checked source snapshot; no compilation or rendering occurs.".
-spec transports(plan()) -> #{hls_source_config:device() => hls_protocol_transport:build()}.
transports(#plan{roles = Roles}) ->
    maps:from_list([{Device, hls_protocol_bridge:transport(Bridge)}
        || #{device := Device, bridge := Bridge} <- Roles]).

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

%% Keep roles attached to actor IDs until every ownership conflict is diagnosed.
-spec placement(#{hls_source_config:device() => hls_source_config:role()}, [hls_protocol_topology:actor()]) -> ok.
placement(Devices, Actors) ->
    Roles = lists:sort(maps:to_list(Devices)),
    lists:foreach(fun({Role, Placement}) ->
        hls_diagnostic:with_context(#{role => Role, path => [devices, Role]},
            fun() -> endpoint(Placement) end)
    end, Roles),
    Known = lists:sort([Id || #{id := Id} <- Actors]),
    Owners = lists:foldl(fun({Role, #{native_actors := Ids}}, Acc) ->
        lists:foldl(fun(Id, ByActor) ->
            maps:update_with(Id, fun(Previous) -> Previous ++ [Role] end, [Role], ByActor)
        end, Acc, Ids)
    end, #{}, Roles),
    case [{Id, Assigned} || {Id, Assigned} <- lists:sort(maps:to_list(Owners)), length(Assigned) > 1] of
        [] -> ok;
        [{DuplicateActor, DuplicateRoles} | _] -> hls_diagnostic:raise(deployment, duplicate_actor_owner,
            <<"Assign each actor to exactly one role; this actor is assigned more than once.">>,
            #{actor => DuplicateActor, roles => DuplicateRoles, path => [devices]})
    end,
    case lists:sort(maps:keys(Owners)) -- Known of
        [] -> ok;
        Unknown -> hls_diagnostic:raise(deployment, unknown_actor_owners,
            <<"Deployment roles name actors absent from the source topology.">>,
            #{actors => Unknown, ownership => maps:with(Unknown, Owners), path => [devices]})
    end,
    case Known -- maps:keys(Owners) of
        [] -> ok;
        Missing -> hls_diagnostic:raise(deployment, missing_actor_owners,
            <<"Assign every source actor to a deployment role.">>,
            #{actors => Missing, path => [devices]})
    end,
    Returns = lists:foldl(fun({Role, #{host := Host, service := Service}}, Acc) ->
        maps:update_with({Host, Service}, fun(Previous) -> Previous ++ [Role] end, [Role], Acc)
    end, #{}, Roles),
    case [{Address, Assigned} || {Address, Assigned} <- lists:sort(maps:to_list(Returns)), length(Assigned) > 1] of
        [] -> ok;
        [{{ReturnHost, ReturnService}, ReturnRoles} | _] -> hls_diagnostic:raise(deployment, duplicate_deployment_endpoints,
            <<"Each deployment role needs a distinct host/service endpoint pair.">>,
            #{host => ReturnHost, service => ReturnService, roles => ReturnRoles, path => [devices]})
    end.

%% Direct planner callers receive the same deliberate rejection as configuration loading.
-spec endpoint(hls_source_config:role()) -> ok.
endpoint(Placement = #{native_actors := Ids, host := Host, service := Service})
        when map_size(Placement) =:= 3, is_list(Ids), Ids =/= [],
             is_integer(Host), Host > 0, Host < 65536,
             is_integer(Service), Service > 0, Service < 65536, Host =/= Service -> ok;
endpoint(Other) -> hls_diagnostic:raise(deployment, invalid_deployment_device,
    <<"A role requires nonempty native_actors and different host/service addresses in 1..65535.">>,
    #{value => Other}).

%% Only placement changes between roles; diagnostic context follows that role's checks.
-spec role(hls_source_config:device(), non_neg_integer(), hls_source_config:role(),
    hls_source_config:network(), hls_protocol_transport:program()) -> role().
role(Device, Index, Placement = #{native_actors := Ids}, Common, Program) ->
    hls_diagnostic:with_context(#{role => Device, path => [devices, Device]}, fun() ->
        Options = (maps:with([arithmetic_groups], Common))#{native_actors => Ids},
        Build = hls_protocol_transport:plan(Program, Options),
        BridgeOptions = maps:with([host, service, control, activation, inspection], maps:merge(Common, Placement)),
        #{device => Device, directory => "role" ++ integer_to_list(Index),
          bridge => hls_protocol_bridge:plan(Build, BridgeOptions)}
    end).
