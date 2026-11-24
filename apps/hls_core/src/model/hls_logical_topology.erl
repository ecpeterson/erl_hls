%%%% hls_logical_topology
%%%%
%%%% Normalizes the first deliberately small actor-topology representation.

-module(hls_logical_topology).
-moduledoc """
Normalizes provisional, closed actor topologies expressed as ordinary Erlang
data.

The current format contains exact actor instances, actor families, external
outputs, bounded rectangle-addressed ingress, routes, explicit multi-recipient
delivery modes, and per-instance startup messages. It intentionally has no
lifecycle, placement, transport, numeric tags, or generated-hardware concepts.
Actor output names, their artifact ABI order, mailbox bounds, schema layouts,
dispatched schemas, and emitted schemas come from retained
`hls_process_interface` values rather than being repeated in the topology.
The checked plan retains that exact catalog so later physical adapters can add
selectors and frame constraints without reacquiring logical schemas.

Here an external output is only a typed boundary of the logical graph. The XLS
backends currently render it as a channel on the generated top proc. It does
not by itself select a PL-PS transport, register an `hls_fabric` route, or name
an Erlang process. A testbench or deployment shell must connect that channel
to a consumer explicitly. The telemetry example has a narrow CPU realization
of its two-actor graph; there is not yet a general CPU topology interpreter.

A rectangle ingress similarly names one externally addressable router service,
not a set of actor destinations. Its envelope first reaches that service; only
then does the router interpret the target and rectangle as an internal bounded
multicast. Rectangle coordinates name stable logical services rather than
actor incarnations. Acceptance by that router is bounded network admission,
not simultaneous mailbox admission at every selected actor. This compact
format does not make a multicast atomic with respect to restart: a lifecycle
implementation must flush affected fanout or protect leaf delivery with
generations when actors can restart independently. The eventual external
gateway is responsible for validating the complete envelope, including frame
lengths and constrained payload fields, and defining any retry or duplicate
policy.

The same format also supports rectangular actor families plus wrapped
translation relations. A family is a dictionary entry
whose fixed `shape` gives the bound of each positional index. A relation such
as `{translate, [0, -1], wrap}` maps one family member to its northern neighbor
without enumerating members or possible pairs. Startup may name bounded family
members explicitly; this keeps arbitrary per-instance values as ordinary
Erlang data without adding an initializer language. This first compact subset
has no general expression language, sparse exceptions, or placement rules.

Exact actor declarations are a map from logical instance ID to actor module.
IDs are atoms, integers, or nonempty tuples recursively containing
those values. A family member uses the same representation, such as
`{phi, X, Y}`, without allocating an atom per instance. Normalized exact
sections and compact family sections are sorted for deterministic traversal;
consumers build maps when they need indexed lookup.

Every exact actor and family output must have exactly one disposition, every
referenced endpoint must exist, and live runtime identities are rejected.
Normalization sorts unordered input, preserves message order within each
startup target, and derives exact lanes or compact lane relations.

An exact source route may target a bounded family member using the same
`{actor, {FamilyId, X, Y}}` identity used by startup. Family relations may target
an exact actor using `{actor, ActorId}`; that recipient is the same for every
source member. These crossings preserve the exact actor's identity and leave
family relations compact. Exact routes cannot override an individual family
member's outputs: those remain covered by the family's route relations.

A singleton route is `{Source, [Recipient]}`. A route with two or more
recipients is `{Source, Delivery, Recipients}` so fanout cannot acquire an
implicit completion rule. The format distinguishes four semantic completion
points:

  * `coupled`: the source event completes after every recipient accepts;
  * `buffered`: it completes after every bounded branch queue accepts;
  * `queued`: it completes after one common bounded egress queue accepts, and
    a downstream lossless distributor subsequently waits for every branch;
  * `best_effort`: explicitly selected branches may drop.

A backend may implement only a subset, but it must not silently rename one
completion point as another.

Route validation uses the union of schemas which the current lowerer proves can
be emitted through a source port and dispatched by a recipient. Family
relations validate those facts once per artifact relation rather than once per
member. A dispatch is not a claim that every payload passes callback patterns
and guards. Numeric tag compatibility remains a physical-backend concern.
""".

%% Process-free logical topology preparation and normalization.
-export([interface_modules/1, interfaces/1, normalize/2]).

%% Normalized instance-route lookup.
-export([routes_for_instance/3]).
%% Shared instance enumeration, lane derivation, and bounded materialization.
-export([instances/1, lanes/1, materialize/2]).
%% Shared type contracts.
-export_type([
    actor/0,
    compact_plan/0,
    destination/0,
    external/0,
    id/0,
    ingress/0,
    interface_catalog/0,
    instance/0,
    materialized_plan/0,
    plan/0,
    route/0,
    spec/0
]).

-doc "An unchecked version-1 compact logical-topology term.".
-type spec() :: map().

-doc "A recursive logical identity shared by compact and materialized topology.".
-type id() :: hls_logical_identity:id().

-doc "A logical actor or external destination, never a process or transport endpoint.".
-type destination() :: hls_logical_identity:destination().

-doc "One exact actor declaration with its source module, output ABI, and mailbox bound.".
-type actor() :: #{
    id := id(), module := module(), outputs := [atom()], mailbox_capacity := pos_integer()
}.

-doc "One complete source-port disposition with explicit fanout completion semantics.".
-type route() :: #{
    source := {id(), atom()},
    recipients := [destination()],
    delivery := direct | coupled | buffered | queued | best_effort
}.

-doc "One declared logical output endpoint and its accepted schema names.".
-type external() :: #{id := id(), direction := out, schemas := [atom()]}.

-doc "One bounded rectangle ingress; compact recipients may still denote embedded families.".
-type ingress() :: map().

-doc "The exact source-independent interfaces required by one checked logical topology.".
-type interface_catalog() :: #{module() => hls_process_interface:interface()}.

-doc "One bounded logical actor paired with its stable observation identity.".
-type instance() :: #{identity := hls_actor_identity:id(), actor := actor()}.

-doc "A normalized compact topology which retains bounded family relations.".
-type compact_plan() :: map().

-doc "The historical compact-plan name retained for source type compatibility.".
-type plan() :: compact_plan().

-doc "A fully expanded source topology with exact actors, routes, lanes, and ingress recipients.".
-type materialized_plan() :: #{
    version := 1,
    actors := [actor()],
    families := [],
    routes := [route()],
    route_relations := [],
    lane_relations := [],
    ingresses := [ingress()],
    externals := [external()],
    interfaces := interface_catalog(),
    instances := [instance()],
    startup := [#{target := id(), delivery := cast, messages := [term()]}],
    lanes := [#{source := id(), destination := destination(), source_ports := [atom()]}]
}.

-doc "Validates compact declarations and returns the distinct modules whose process-free interfaces are required.".
-spec interface_modules(spec()) -> [module()].
interface_modules(Spec) ->
    ok = ensure_static(Spec),
    case Spec of
        #{version := 1, actors := ActorSpecs, families := FamilySpecs} ->
            ok = validate_top_level(Spec),
            ActorPairs = normalize_actors(ActorSpecs),
            lists:usort(
                [Module || {_Id, Module} <- ActorPairs] ++
                    hls_topology_family:interface_modules(FamilySpecs)
            );
        #{version := Version} ->
            error({unsupported_version, Version});
        _ ->
            validate_top_level(Spec)
    end.

-doc "Validates and canonicalizes one compact topology using a complete process-interface catalog.".
-spec normalize(spec(), interface_catalog()) -> compact_plan().
normalize(Spec, Interfaces) ->
    Modules = interface_modules(Spec),
    ok = validate_interface_catalog(Modules, Interfaces),
    normalize_current(Spec, Interfaces).

-doc "Returns the validated source-independent interface catalog retained by a compact or materialized plan.".
-spec interfaces(compact_plan() | materialized_plan()) -> interface_catalog().
interfaces(#{interfaces := Interfaces}) ->
    Interfaces.

%% Normalize a validated version-1 term without acquiring compiler state.
-spec normalize_current(spec(), interface_catalog()) -> compact_plan().
normalize_current(Spec, Interfaces) ->
    ok = validate_top_level(Spec),
    ActorPairs = normalize_actors(maps:get(actors, Spec)),
    hls_topology_family:normalize(
        Spec,
        Interfaces,
        fun(Current, FamilyIndex, RetainedInterfaces) ->
            Actors = [
                actor_summary(Id, Module, maps:get(Module, RetainedInterfaces))
             || {Id, Module} <- ActorPairs
            ],
            normalize_exact_sections(Current, FamilyIndex, Actors, RetainedInterfaces)
        end
    ).

%% Normalize exact actors, external endpoints, routes, startup, and exact lanes.
-spec normalize_exact_sections(map(), map(), [map()], interface_catalog()) -> map().
normalize_exact_sections(Spec, FamilyIndex, Actors, Interfaces) ->
    ActorIndex = maps:from_list([{maps:get(id, Actor), Actor} || Actor <- Actors]),
    Externals = normalize_externals(maps:get(externals, Spec)),
    ExternalIndex = maps:from_list([{maps:get(id, External), External} || External <- Externals]),
    Routes = normalize_routes(
        maps:get(routes, Spec),
        #{actors => ActorIndex, families => FamilyIndex},
        ExternalIndex
    ),
    Startup = normalize_startup(
        maps:get(startup, Spec),
        ActorIndex,
        FamilyIndex
    ),

    #{
        version => 1,
        actors => [maps:remove(interface, Actor) || Actor <- Actors],
        externals => Externals,
        interfaces => Interfaces,
        routes => Routes,
        startup => Startup,
        lanes => lanes(Routes)
    }.

-doc "Resolves one family's compact rules for one bounded member.".
-spec routes_for_instance(plan(), term(), [non_neg_integer()]) -> [map()].
routes_for_instance(Plan = #{families := _}, FamilyId, Coordinates) ->
    hls_topology_family:routes_for_instance(Plan, FamilyId, Coordinates);
routes_for_instance(Plan, _FamilyId, _Coordinates) ->
    error({invalid_topology_plan, Plan}).

%%%
%%% Actor and external endpoints
%%%

%% Validate every supplied interface before requiring an exact module catalog.
-spec validate_interface_catalog([module()], term()) -> ok.
validate_interface_catalog(Modules, Interfaces) when is_map(Interfaces) ->
    maps:foreach(
        fun(Key, Interface) ->
            ok = hls_process_interface:validate(Interface),
            case hls_process_interface:module(Interface) of
                Key -> ok;
                Actual -> error({process_interface_module_mismatch, Key, Actual})
            end
        end,
        Interfaces
    ),
    Expected = lists:sort(Modules),
    Actual = lists:sort(maps:keys(Interfaces)),
    case {Expected -- Actual, Actual -- Expected} of
        {[], []} -> ok;
        {Missing, Extra} -> error({process_interface_catalog, Missing, Extra})
    end;
validate_interface_catalog(_Modules, Interfaces) ->
    error({invalid_process_interface_catalog, Interfaces}).

%% Require the exact version-1 source vocabulary before interpreting any section.
-spec validate_top_level(term()) -> ok.
validate_top_level(Spec) when is_map(Spec) ->
    Required = [
        actors,
        externals,
        families,
        ingresses,
        route_relations,
        routes,
        startup,
        version
    ],
    Keys = maps:keys(Spec),
    case {Required -- Keys, Keys -- Required} of
        {[], []} -> ok;
        {Missing, Unknown} -> error({invalid_topology_keys, Missing, Unknown})
    end;
validate_top_level(_Spec) ->
    error({invalid_topology, expected_map}).

%% Validate and deterministically order exact actor declarations.
-spec normalize_actors(term()) -> [{id(), module()}].
normalize_actors(Specs) when is_map(Specs) ->
    lists:sort([
        normalize_actor_entry(Id, Module)
     || {Id, Module} <- maps:to_list(Specs)
    ]);
normalize_actors(Specs) ->
    error({invalid_topology_field, actors, Specs}).

%% Validate one exact logical actor and its computation module.
-spec normalize_actor_entry(term(), term()) -> {id(), module()}.
normalize_actor_entry(Id, Module) when is_atom(Module) ->
    ok = hls_logical_identity:validate(Id),
    {Id, Module};
normalize_actor_entry(Id, Module) ->
    error({invalid_actor_module, Id, Module}).

%% Retain the process-free interface only while checking communication compatibility.
-spec actor_summary(id(), module(), hls_process_interface:interface()) -> map().
actor_summary(
    Id,
    Module,
    Interface = #{
        outputs := Outputs,
        mailbox_capacity := Capacity
    }
) ->
    #{
        id => Id,
        module => Module,
        outputs => Outputs,
        mailbox_capacity => Capacity,
        interface => Interface
    }.

%% Validate, deduplicate, and deterministically order external endpoints.
-spec normalize_externals(term()) -> [external()].
normalize_externals(Specs) when is_list(Specs) ->
    Externals = [normalize_external(Spec) || Spec <- Specs],
    require_unique(
        duplicate_external_ids,
        [maps:get(id, External) || External <- Externals]
    ),
    sort_by(fun(External) -> maps:get(id, External) end, Externals);
normalize_externals(Specs) ->
    error({invalid_topology_field, externals, Specs}).

%% Normalize one output-only external endpoint and its schema union.
-spec normalize_external(term()) -> external().
normalize_external({Id, out, Schemas}) when is_list(Schemas), Schemas =/= [] ->
    ok = hls_logical_identity:validate(Id),
    case lists:all(fun erlang:is_atom/1, Schemas) of
        true -> require_unique(duplicate_external_schemas, Schemas);
        false -> error({invalid_external_schemas, Id, Schemas})
    end,
    #{id => Id, direction => out, schemas => lists:sort(Schemas)};
normalize_external({Id, Direction, _Schemas}) ->
    error({unsupported_external_endpoint, Id, Direction});
normalize_external(Spec) ->
    error({invalid_external_spec, Spec}).

%%%
%%% Routes and ordered lanes
%%%

-spec normalize_routes(term(), map(), map()) -> [route()].
normalize_routes(Specs, Endpoints = #{actors := ActorIndex}, ExternalIndex) when is_list(Specs) ->
    Routes = [normalize_route(Spec, Endpoints, ExternalIndex) || Spec <- Specs],
    Sources = [maps:get(source, Route) || Route <- Routes],
    require_unique(duplicate_route_sources, Sources),
    Expected = lists:sort([
        {maps:get(id, Actor), Port}
     || Actor <- maps:values(ActorIndex),
        Port <- maps:get(outputs, Actor)
    ]),
    case Expected -- lists:sort(Sources) of
        [] ->
            Sorted = sort_by(
                fun(Route) -> maps:get(source, Route) end,
                Routes
            ),
            ok = validate_route_interfaces(
                Sorted,
                Endpoints,
                ExternalIndex
            ),
            Sorted;
        Missing ->
            error({unrouted_outputs, Missing})
    end;
normalize_routes(Specs, _Endpoints, _ExternalIndex) ->
    error({invalid_topology_field, routes, Specs}).

%% Decode one compact route form and require explicit semantics for fanout.
-spec normalize_route(term(), map(), map()) -> route().
normalize_route({Source, []}, _Endpoints, _ExternalIndex) ->
    error({empty_route, Source});
normalize_route({Source, Recipients}, Endpoints, ExternalIndex) when
    is_list(Recipients)
->
    case Recipients of
        [_] ->
            normalize_route(
                Source,
                direct,
                Recipients,
                Endpoints,
                ExternalIndex
            );
        _ ->
            error({fanout_delivery_required, Source})
    end;
normalize_route({Source, _Delivery, []}, _Endpoints, _ExternalIndex) ->
    error({empty_route, Source});
normalize_route({Source, Delivery, Recipients}, Endpoints, ExternalIndex) when
    is_list(Recipients), length(Recipients) > 1
->
    case lists:member(Delivery, [buffered, coupled, queued, best_effort]) of
        true ->
            normalize_route(
                Source,
                Delivery,
                Recipients,
                Endpoints,
                ExternalIndex
            );
        false ->
            error({invalid_fanout_delivery, Source, Delivery})
    end;
normalize_route({Source, Delivery, Recipients}, _Endpoints, _ExternalIndex) when
    is_list(Recipients)
->
    error({invalid_fanout, Source, Delivery, Recipients});
normalize_route(Spec, _Endpoints, _ExternalIndex) ->
    error({invalid_route_spec, Spec}).

%% Resolve and deduplicate the endpoints of one route.
-spec normalize_route(term(), atom(), [term()], map(), map()) -> route().
normalize_route(
    Source,
    Delivery,
    Recipients,
    Endpoints,
    ExternalIndex
) ->
    NormalSource = normalize_source(Source, Endpoints),
    NormalRecipients = [
        normalize_recipient(
            Recipient,
            NormalSource,
            Endpoints,
            ExternalIndex
        )
     || Recipient <- Recipients
    ],
    case duplicates(NormalRecipients) of
        [] -> ok;
        Duplicates -> error({duplicate_route_recipients, NormalSource, Duplicates})
    end,
    #{
        source => NormalSource,
        delivery => Delivery,
        recipients => lists:sort(NormalRecipients)
    }.

%% Resolve one exact source actor and declared output port.
-spec normalize_source(term(), map()) -> {id(), atom()}.
normalize_source({ActorId, Port}, #{actors := ActorIndex}) when is_atom(Port) ->
    Actor = require_actor(ActorId, ActorIndex, route_source),
    case lists:member(Port, maps:get(outputs, Actor)) of
        true -> {ActorId, Port};
        false -> error({unknown_actor_output, ActorId, Port})
    end;
normalize_source(Source, _Endpoints) ->
    error({invalid_route_source, Source}).

%% Resolve one logical actor or external route recipient.
-spec normalize_recipient(term(), term(), map(), map()) -> destination().
normalize_recipient(
    Recipient = {actor, ActorId},
    Source,
    Endpoints,
    _ExternalIndex
) ->
    _ = hls_topology_endpoint:actor(ActorId, Endpoints, {route_recipient, Source}),
    Recipient;
normalize_recipient(
    Recipient = {external, ExternalId},
    Source,
    _Endpoints,
    ExternalIndex
) ->
    case maps:is_key(ExternalId, ExternalIndex) of
        true -> Recipient;
        false -> error({unknown_external, ExternalId, {route_recipient, Source}})
    end;
normalize_recipient(Recipient, Source, _Endpoints, _ExternalIndex) ->
    error({invalid_route_recipient, Source, Recipient}).

%% Validate schemas and layouts on every exact route edge.
-spec validate_route_interfaces([route()], map(), map()) -> ok.
validate_route_interfaces(Routes, Endpoints = #{actors := ActorIndex}, ExternalIndex) ->
    lists:foreach(
        fun(Route) ->
            Source = {ActorId, Port} = maps:get(source, Route),
            SourceActor = maps:get(ActorId, ActorIndex),
            SourceInterface = maps:get(interface, SourceActor),
            Emitted = hls_process_interface:output_schemas(
                SourceInterface,
                Port
            ),
            lists:foreach(
                fun(Recipient) ->
                    validate_route_recipient_interface(
                        Source,
                        SourceInterface,
                        Emitted,
                        Recipient,
                        Endpoints,
                        ExternalIndex
                    )
                end,
                maps:get(recipients, Route)
            )
        end,
        Routes
    ).

%% Check one exact route recipient against the source's emitted schema union.
-spec validate_route_recipient_interface(
    term(),
    hls_process_interface:interface(),
    [atom()],
    destination(),
    map(),
    map()
) -> ok.
validate_route_recipient_interface(
    Source,
    SourceInterface,
    Emitted,
    Recipient = {actor, ActorId},
    Endpoints,
    _ExternalIndex
) ->
    #{interface := DestinationInterface} = hls_topology_endpoint:actor(
        ActorId, Endpoints, {route_recipient, Source}
    ),
    hls_topology_endpoint:validate_route(
        Source, Recipient, SourceInterface, Emitted, DestinationInterface
    );
validate_route_recipient_interface(
    Source,
    _SourceInterface,
    Emitted,
    Recipient = {external, ExternalId},
    _Endpoints,
    ExternalIndex
) ->
    External = maps:get(ExternalId, ExternalIndex),
    hls_topology_endpoint:require_schemas(
        Source,
        Recipient,
        Emitted,
        maps:get(schemas, External)
    ).

-doc "Derives deterministic producer lanes by grouping route ports on source and destination.".
-spec lanes([route()]) ->
    [#{source := id(), destination := destination(), source_ports := [atom()]}].
lanes(Routes) ->
    LanePorts = lists:foldl(
        fun(Route, Acc0) ->
            {SourceActor, Port} = maps:get(source, Route),
            lists:foldl(
                fun(Recipient, Acc) ->
                    Key = {SourceActor, Recipient},
                    maps:update_with(
                        Key,
                        fun(Ports) -> [Port | Ports] end,
                        [Port],
                        Acc
                    )
                end,
                Acc0,
                maps:get(recipients, Route)
            )
        end,
        #{},
        Routes
    ),
    [
        #{
            source => SourceActor,
            destination => Destination,
            source_ports => lists:sort(Ports)
        }
     || {{SourceActor, Destination}, Ports} <-
            lists:sort(maps:to_list(LanePorts))
    ].

%%%
%%% Startup and shared validation
%%%

-spec normalize_startup(term(), map(), map()) -> [map()].
normalize_startup(Specs, ActorIndex, FamilyIndex) when is_list(Specs) ->
    Startup = [
        normalize_startup_item(Spec, ActorIndex, FamilyIndex)
     || Spec <- Specs
    ],
    require_unique(
        duplicate_startup_targets,
        [maps:get(target, Item) || Item <- Startup]
    ),
    sort_by(fun(Item) -> maps:get(target, Item) end, Startup);
normalize_startup(Specs, _ActorIndex, _FamilyIndex) ->
    error({invalid_topology_field, startup, Specs}).

%% Resolve one startup target and retain its declared message order.
-spec normalize_startup_item(term(), map(), map()) -> map().
normalize_startup_item({Target, Messages}, ActorIndex, FamilyIndex) when
    is_list(Messages), Messages =/= []
->
    Actor = require_startup_target(Target, ActorIndex, FamilyIndex),
    ok = validate_startup_schemas(Target, Messages, Actor),
    #{target => Target, delivery => cast, messages => Messages};
normalize_startup_item(Spec, _ActorIndex, _FamilyIndex) ->
    error({invalid_startup_spec, Spec}).

%% Resolve an exact actor or bounded family member used as a startup target.
-spec require_startup_target(term(), map(), map()) -> map().
require_startup_target(Target, ActorIndex, FamilyIndex) ->
    hls_topology_endpoint:actor(
        Target,
        #{actors => ActorIndex, families => FamilyIndex},
        startup
    ).

%% Check tuple-tagged startup messages against the target's dispatch union.
-spec validate_startup_schemas(id(), [term()], map()) -> ok.
validate_startup_schemas(ActorId, Messages, Actor) ->
    Interface = maps:get(interface, Actor),
    Dispatched = hls_process_interface:dispatched_schemas(
        Interface
    ),
    lists:foreach(
        fun({Index, Message}) ->
            case startup_schema(Message) of
                none ->
                    ok;
                {ok, Schema} ->
                    case lists:member(Schema, Dispatched) of
                        true ->
                            ok;
                        false ->
                            error({incompatible_startup_schema, ActorId, Index, Schema, Dispatched})
                    end
            end
        end,
        lists:enumerate(0, Messages)
    ).

%% Infer a record-like message schema when the tuple has an atom tag.
-spec startup_schema(term()) -> none | {ok, atom()}.
startup_schema(Message) when
    is_tuple(Message),
    tuple_size(Message) > 0,
    is_atom(element(1, Message))
->
    {ok, element(1, Message)};
startup_schema(_Message) ->
    none.

%% Return one exact actor or raise the established unknown-actor error.
-spec require_actor(id(), map(), term()) -> map().
require_actor(ActorId, ActorIndex, Context) ->
    case maps:find(ActorId, ActorIndex) of
        {ok, Actor} -> Actor;
        error -> error({unknown_actor, ActorId, Context})
    end.

%% Require unique terms and report the deterministic duplicate set under `ErrorTag`.
-spec require_unique(atom(), [term()]) -> ok.
require_unique(ErrorTag, Values) ->
    case duplicates(Values) of
        [] -> ok;
        Duplicates -> error({ErrorTag, Duplicates})
    end.

%% Return each duplicated term once in Erlang term order.
-spec duplicates([term()]) -> [term()].
duplicates(Values) ->
    Counts = lists:foldl(
        fun(Value, Acc) ->
            maps:update_with(Value, fun(Count) -> Count + 1 end, 1, Acc)
        end,
        #{},
        Values
    ),
    lists:sort([Value || {Value, Count} <- maps:to_list(Counts), Count > 1]).

%% Sort terms by a derived key without changing the terms themselves.
-spec sort_by(fun((term()) -> term()), [term()]) -> [term()].
sort_by(Key, Values) ->
    lists:sort(fun(A, B) -> Key(A) < Key(B) end, Values).

%% Reject runtime identities anywhere in an otherwise static topology term.
-spec ensure_static(term()) -> ok.
ensure_static(Term) ->
    case live_value(Term) of
        none -> ok;
        Kind -> error({live_topology_value, Kind})
    end.

%% Return the first kind of live runtime value nested in one term.
-spec live_value(term()) -> none | pid | port | reference | function.
live_value(Term) when is_pid(Term) -> pid;
live_value(Term) when is_port(Term) -> port;
live_value(Term) when is_reference(Term) -> reference;
live_value(Term) when is_function(Term) -> function;
live_value([Head | Tail]) ->
    first_live([Head, Tail]);
live_value(Term) when is_tuple(Term) -> first_live(tuple_to_list(Term));
live_value(Term) when is_map(Term) ->
    first_live(lists:append([[Key, Value] || {Key, Value} <- maps:to_list(Term)]));
live_value(_Term) ->
    none.

%% Scan terms in deterministic traversal order for a live runtime value.
-spec first_live([term()]) -> none | pid | port | reference | function.
first_live([]) ->
    none;
first_live([Term | Rest]) ->
    case live_value(Term) of
        none -> first_live(Rest);
        Kind -> Kind
    end.

%%%
%%% Bounded materialization
%%%

-doc "Returns retained instances from a materialized plan, or enumerates a checked compact topology up to 65536 actors. Observation identities distinguish exact tuple IDs from family coordinates.".
-spec instances(compact_plan()) -> [instance()].
instances(#{instances := Instances}) ->
    Instances;
instances(Plan) ->
    {Instances, _FamilyMap} = prepare_instances(Plan, 65536),
    Instances.

-doc "Expands checked bounded families of any nonempty rank and their routes up to `Limit`, retaining ordered instance provenance, logical identities, startup, external schemas, and two-dimensional rectangle-ingress coordinates. Materialization does not establish protocol eligibility or hardware admission.".
-spec materialize(compact_plan(), pos_integer()) -> materialized_plan().
materialize(
    Plan = #{routes := Routes, ingresses := Ingresses},
    Limit
) when is_integer(Limit), Limit > 0, Limit =< 65536 ->
    {Instances, FamilyMap} = prepare_instances(Plan, Limit),
    Actors = [Actor || #{actor := Actor} <- Instances],
    Ids = [maps:get(id, Actor) || Actor <- Actors],
    Expanded =
        Routes ++
            lists:append([
                routes_for_instance(Plan, FamilyId, Coordinates)
             || #{identity := {family, FamilyId, Coordinates}} <- Instances
            ]),
    Sources = [Source || #{source := Source} <- Expanded],
    need(
        length(Sources) =:= length(lists:usort(Sources)),
        {duplicate_source_port, Sources}
    ),
    MaterializedIngresses = [
        hls_diagnostic:with_context(
            #{ingress => ingress_id(Ingress)},
            fun() -> materialize_ingress(Ingress, FamilyMap, Ids) end
        )
     || Ingress <- Ingresses
    ],
    Plan#{
        actors := Actors,
        families := [],
        instances => Instances,
        routes := Expanded,
        ingresses := MaterializedIngresses,
        route_relations := [],
        lane_relations := [],
        lanes => lanes(Expanded)
    };
materialize(_Plan, Limit) ->
    reject_materialization({invalid_actor_limit, Limit}).

%% Validate the bounded actor namespace once and retain both logical and observation identities.
-spec prepare_instances(compact_plan(), pos_integer()) -> {[instance()], map()}.
prepare_instances(#{actors := Exact, families := Families}, Limit) ->
    Count = length(Exact) + lists:sum([family_size(Family) || Family <- Families]),
    need(Count =< Limit, {actor_limit, Count, Limit}),
    FamilyMap = maps:from_list([{maps:get(id, Family), Family} || Family <- Families]),
    need(
        map_size(FamilyMap) =:= length(Families),
        {duplicate_family, [maps:get(id, Family) || Family <- Families]}
    ),
    Instances =
        [
            #{identity => {actor, maps:get(id, Actor)}, actor => Actor}
         || Actor <- Exact
        ] ++
            lists:append([family_instances(Family) || Family <- Families]),
    Ids = [maps:get(id, Actor) || #{actor := Actor} <- Instances],
    need(length(Ids) =:= length(lists:usort(Ids)), {duplicate_actor, Ids}),
    {Instances, FamilyMap}.

%% Count a supported family before allocating actor or recipient arrays.
-spec family_size(map()) -> pos_integer().
family_size(#{shape := [_ | _] = Shape} = Family) ->
    case lists:all(fun(Size) -> is_integer(Size) andalso Size > 0 end, Shape) of
        true ->
            lists:foldl(fun(Size, Product) -> Size * Product end, 1, Shape);
        false ->
            reject_family_shape(Family)
    end;
family_size(Family) ->
    reject_family_shape(Family).

%% Reject an empty or nonpositive family shape with the materialization diagnostic.
-spec reject_family_shape(map()) -> no_return().
reject_family_shape(Family) ->
    reject_materialization(
        {unsupported_family_shape, maps:get(id, Family, unknown),
            maps:get(shape, Family, undefined)}
    ).

%% Pair each bounded family member with its coordinate-bearing observation identity.
-spec family_instances(map()) -> [instance()].
family_instances(Family = #{id := Id, shape := Shape}) ->
    [
        #{
            identity => {family, Id, Coordinates},
            actor => maps:without(
                [shape, instance_count], Family#{id := list_to_tuple([Id | Coordinates])}
            )
        }
     || Coordinates <- coordinates(Shape)
    ].

%% Enumerate a Cartesian shape with the first coordinate outermost and the last innermost.
-spec coordinates([pos_integer()]) -> [[non_neg_integer()]].
coordinates([]) ->
    [[]];
coordinates([Size | Rest]) ->
    [[Index | Tail] || Index <- lists:seq(0, Size - 1), Tail <- coordinates(Rest)].

%% Expand family ingress recipients while retaining explicit coordinates and schema declarations.
-spec materialize_ingress(map(), map(), [id()]) -> ingress().
materialize_ingress(
    Ingress = #{id := Id, kind := rectangle, shape := [Width, Height], targets := Targets},
    Families,
    Actors
) ->
    Ingress#{
        targets := [
            begin
                Recipients = lists:append([
                    materialize_ingress_recipient(Recipient, Families)
                 || Recipient <- maps:get(recipients, Target)
                ]),
                Assigned = [Actor || #{actor := Actor} <- Recipients],
                need(
                    length(Assigned) =:= length(lists:usort(Assigned)),
                    {duplicate_ingress_recipient, Id, maps:get(id, Target)}
                ),
                lists:foreach(
                    fun(#{actor := Actor, at := [X, Y]}) ->
                        need(lists:member(Actor, Actors), {unknown_ingress_actor, Id, Actor}),
                        need(
                            X >= 0 andalso X < Width andalso Y >= 0 andalso Y < Height,
                            {ingress_coordinate, Id, Actor, [X, Y]}
                        )
                    end,
                    Recipients
                ),
                Target#{recipients := Recipients}
            end
         || Target <- Targets
        ]
    };
materialize_ingress(Ingress, _Families, _Actors) ->
    reject_materialization({unsupported_ingress, Ingress}).

%% Name malformed ingress diagnostics without assuming the input is already a map.
-spec ingress_id(term()) -> term().
ingress_id(Ingress) when is_map(Ingress) ->
    maps:get(id, Ingress, unknown);
ingress_id(_Ingress) ->
    unknown.

%% Expand one exact or family ingress binding into exact actor coordinates.
-spec materialize_ingress_recipient(map(), map()) -> [#{actor := id(), at := [integer()]}].
materialize_ingress_recipient(Recipient = #{actor := _, at := [_, _]}, _Families) ->
    [Recipient];
materialize_ingress_recipient(
    Recipient = #{family := Id, scale := [ScaleX, ScaleY], offset := [OffsetX, OffsetY]},
    Families
) ->
    case maps:find(Id, Families) of
        {ok, #{shape := [Width, Height]}} ->
            [
                #{
                    actor => {Id, X, Y},
                    at => [ScaleX * X + OffsetX, ScaleY * Y + OffsetY]
                }
             || X <- lists:seq(0, Width - 1), Y <- lists:seq(0, Height - 1)
            ];
        {ok, _Family} ->
            reject_materialization({unsupported_ingress_recipient, Recipient});
        error ->
            reject_materialization({unknown_ingress_family, Id})
    end;
materialize_ingress_recipient(Recipient, _Families) ->
    reject_materialization({unsupported_ingress_recipient, Recipient}).

%% Convert a failed materialization condition into the established diagnostic shape.
-spec need(boolean(), term()) -> ok.
need(true, _Reason) -> ok;
need(false, Reason) -> reject_materialization(Reason).

%% Raise only declared source-shape failures as structured topology diagnostics.
-spec reject_materialization(term()) -> no_return().
reject_materialization(Reason) ->
    {Code, Message, Context} = materialization_diagnostic(Reason),
    hls_diagnostic:raise(topology, Code, Message, Context#{reason => Reason}).

%% Map materialization failures to stable diagnostic codes and structured context.
-spec materialization_diagnostic(term()) -> {atom(), binary(), map()}.
materialization_diagnostic({actor_limit, Count, Limit}) ->
    {actor_limit, <<"The expanded topology exceeds the configured actor limit.">>, #{
        actual => Count, maximum => Limit
    }};
materialization_diagnostic({invalid_actor_limit, Limit}) ->
    {invalid_actor_limit, <<"The actor limit must be an integer from 1 through 65536.">>, #{
        value => Limit, path => [actor_limit]
    }};
materialization_diagnostic({duplicate_family, Ids}) ->
    {duplicate_family, <<"Topology family IDs must be unique.">>, #{families => Ids}};
materialization_diagnostic({duplicate_actor, Ids}) ->
    {duplicate_actor, <<"Explicit and expanded actor IDs must be unique.">>, #{actors => Ids}};
materialization_diagnostic({duplicate_source_port, Sources}) ->
    {duplicate_source_port, <<"Each actor output port must have one route declaration.">>, #{
        sources => Sources
    }};
materialization_diagnostic({unsupported_family_shape, Id, Shape}) ->
    {unsupported_family_shape, <<"Protocol families require one or more positive dimensions.">>, #{
        family => Id, shape => Shape
    }};
materialization_diagnostic({duplicate_ingress_recipient, Ingress, Target}) ->
    {duplicate_ingress_recipient, <<"An ingress target may address each actor only once.">>, #{
        ingress => Ingress, target => Target
    }};
materialization_diagnostic({unknown_ingress_actor, Ingress, Actor}) ->
    {unknown_ingress_actor, <<"An ingress recipient must name an actor in the expanded topology.">>,
        #{ingress => Ingress, actor => Actor}};
materialization_diagnostic({ingress_coordinate, Ingress, Actor, At}) ->
    {ingress_coordinate, <<"Ingress coordinates must lie within the declared rectangle.">>, #{
        ingress => Ingress, actor => Actor, coordinate => At
    }};
materialization_diagnostic({unsupported_ingress, Ingress}) ->
    {unsupported_ingress, <<"Protocol ingress requires a rectangle with explicit targets.">>, #{
        value => Ingress
    }};
materialization_diagnostic({unknown_ingress_family, Id}) ->
    {unknown_ingress_family, <<"An ingress family recipient must name a declared family.">>, #{
        family => Id
    }};
materialization_diagnostic({unsupported_ingress_recipient, Recipient}) ->
    {unsupported_ingress_recipient,
        <<"Use an actor coordinate or a family with scale and offset for each ingress recipient.">>,
        #{value => Recipient}}.
