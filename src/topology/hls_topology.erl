%%%% hls_topology
%%%%
%%%% Normalizes the first deliberately small actor-topology representation.

-module(hls_topology).
-moduledoc """
Normalizes provisional, closed actor topologies expressed as ordinary Erlang
data.

The current format contains exact actor instances, actor families, external
outputs, routes, explicit multi-recipient delivery modes, and per-instance
startup messages. It intentionally has no lifecycle, placement, transport,
numeric tags, or generated-hardware concepts. Actor output names, their
artifact ABI order, mailbox bounds, schema layouts, phase-specific dispatches,
and phase-entry effects are read from the compiler's provisional
actor-interface summary rather than repeated in the topology.

Here an external output is only a typed boundary of the logical graph. The XLS
backends currently render it as a channel on the generated top proc. It does
not by itself select a PL-PS transport, register an `hls_fabric` route, or name
an Erlang process. A testbench or a later deployment shell/gateway must connect
that channel to a consumer explicitly; there is not yet a CPU topology
interpreter which makes that connection automatically.

The same format also supports rectangular actor families plus wrapped
translation relations. A family is a dictionary entry
whose fixed `shape` gives the bound of each positional index. A relation such
as `{translate, [0, -1], wrap}` maps one family member to its northern neighbor
without enumerating members or possible pairs. Startup may name bounded family
members explicitly; this keeps arbitrary per-instance values as ordinary
Erlang data without adding an initializer language. This first compact subset
has no general expression language, sparse exceptions, or placement rules.

Exact actor declarations are a map from logical instance ID to actor module.
IDs are atoms, nonnegative integers, or nonempty tuples recursively containing
those values. A family member uses the same representation, such as
`{phi, X, Y}`, without allocating an atom per instance. Normalized exact
sections and compact family sections are sorted for deterministic traversal;
consumers build maps when they need indexed lookup.

Every exact actor and family output must have exactly one disposition, every
referenced endpoint must exist, and live runtime identities are rejected.
Normalization sorts unordered input, preserves message order within each
startup target, and derives exact lanes or compact lane relations.

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

-export([
    from_module/1,
    normalize/1,
    routes_for_instance/3
]).
-export_type([plan/0, spec/0]).

-type spec() :: map().
-type plan() :: map().

-doc "Loads `Module:topology/0` and normalizes the returned term.".
-spec from_module(module()) -> plan().
from_module(Module) when is_atom(Module) ->
    case code:ensure_loaded(Module) of
        {module, Module} ->
            case erlang:function_exported(Module, topology, 0) of
                true -> normalize(Module:topology());
                false -> error({missing_topology_callback, Module, topology, 0})
            end;
        {error, Reason} ->
            error({topology_module_unavailable, Module, Reason})
    end;
from_module(Module) ->
    error({invalid_topology_module, Module}).

-doc "Validates and canonicalizes one supported topology term.".
-spec normalize(spec()) -> plan().
normalize(Spec) ->
    ok = ensure_static(Spec),
    case Spec of
        #{version := 1} -> normalize_current(Spec);
        #{version := Version} -> error({unsupported_version, Version});
        _ -> validate_top_level(Spec)
    end.

normalize_current(Spec) ->
    ok = validate_top_level(Spec),
    hls_topology_family:normalize(Spec, fun normalize_exact_sections/2).

normalize_exact_sections(Spec, FamilyIndex) ->
    Actors = normalize_actors(maps:get(actors, Spec)),
    ActorIndex = maps:from_list([
        {maps:get(id, Actor), Actor} || Actor <- Actors
    ]),
    Externals = normalize_externals(maps:get(externals, Spec)),
    ExternalIndex = maps:from_list([
        {maps:get(id, External), External} || External <- Externals
    ]),
    Routes = normalize_routes(
        maps:get(routes, Spec),
        ActorIndex,
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
        routes => Routes,
        startup => Startup,
        lanes => derive_lanes(Routes)
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

validate_top_level(Spec) when is_map(Spec) ->
    Required = [
        actors,
        externals,
        families,
        route_relations,
        routes,
        startup,
        version
    ],
    Keys = maps:keys(Spec),
    case {Required -- Keys, Keys -- Required} of
        {[], []} -> ok;
        {Missing, Unknown} ->
            error({invalid_topology_keys, Missing, Unknown})
    end;
validate_top_level(_Spec) ->
    error({invalid_topology, expected_map}).

normalize_actors(Specs) when is_map(Specs) ->
    Pairs = [normalize_actor_entry(Id, Module)
        || {Id, Module} <- maps:to_list(Specs)],
    normalize_actor_pairs(Pairs);
normalize_actors(Specs) ->
    error({invalid_topology_field, actors, Specs}).

normalize_actor_pairs(Pairs) ->
    sort_by(
        fun(Actor) -> maps:get(id, Actor) end,
        [actor_summary(Id, Module) || {Id, Module} <- Pairs]
    ).

normalize_actor_entry(Id, Module) when is_atom(Module) ->
    ok = validate_id(Id),
    {Id, Module};
normalize_actor_entry(Id, Module) ->
    error({invalid_actor_module, Id, Module}).

actor_summary(Id, Module) ->
    case code:ensure_loaded(Module) of
        {module, Module} ->
            Interface = hls_actor_interface:from_module(Module),
            #{
                id => Id,
                module => Module,
                outputs => maps:get(outputs, Interface),
                mailbox_capacity => maps:get(
                    mailbox_capacity,
                    Interface
                ),
                interface => Interface
            };
        {error, Reason} ->
            error({topology_actor_unavailable, Id, Module, Reason})
    end.

normalize_externals(Specs) when is_list(Specs) ->
    Externals = [normalize_external(Spec) || Spec <- Specs],
    require_unique(
        duplicate_external_ids,
        [maps:get(id, External) || External <- Externals]
    ),
    sort_by(fun(External) -> maps:get(id, External) end, Externals);
normalize_externals(Specs) ->
    error({invalid_topology_field, externals, Specs}).

normalize_external({Id, out, Schemas}) when is_list(Schemas), Schemas =/= [] ->
    ok = validate_id(Id),
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

normalize_routes(Specs, ActorIndex, ExternalIndex) when is_list(Specs) ->
    Routes = [
        normalize_route(Spec, ActorIndex, ExternalIndex) || Spec <- Specs
    ],
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
                ActorIndex,
                ExternalIndex
            ),
            Sorted;
        Missing -> error({unrouted_outputs, Missing})
    end;
normalize_routes(Specs, _ActorIndex, _ExternalIndex) ->
    error({invalid_topology_field, routes, Specs}).

normalize_route({Source, []}, _ActorIndex, _ExternalIndex) ->
    error({empty_route, Source});
normalize_route({Source, Recipients}, ActorIndex, ExternalIndex)
        when is_list(Recipients) ->
    case Recipients of
        [_] ->
            normalize_route(
                Source,
                direct,
                Recipients,
                ActorIndex,
                ExternalIndex
            );
        _ ->
            error({fanout_delivery_required, Source})
    end;
normalize_route({Source, _Delivery, []}, _ActorIndex, _ExternalIndex) ->
    error({empty_route, Source});
normalize_route({Source, Delivery, Recipients}, ActorIndex, ExternalIndex)
        when is_list(Recipients), length(Recipients) > 1 ->
    case lists:member(Delivery, [buffered, coupled, queued, best_effort]) of
        true ->
            normalize_route(
                Source,
                Delivery,
                Recipients,
                ActorIndex,
                ExternalIndex
            );
        false ->
            error({invalid_fanout_delivery, Source, Delivery})
    end;
normalize_route({Source, Delivery, Recipients}, _ActorIndex, _ExternalIndex)
        when is_list(Recipients) ->
    error({invalid_fanout, Source, Delivery, Recipients});
normalize_route(Spec, _ActorIndex, _ExternalIndex) ->
    error({invalid_route_spec, Spec}).

normalize_route(
    Source,
    Delivery,
    Recipients,
    ActorIndex,
    ExternalIndex
) ->
    NormalSource = normalize_source(Source, ActorIndex),
    NormalRecipients = [
        normalize_recipient(
            Recipient,
            NormalSource,
            ActorIndex,
            ExternalIndex
        )
        || Recipient <- Recipients
    ],
    case duplicates(NormalRecipients) of
        [] -> ok;
        Duplicates ->
            error({duplicate_route_recipients, NormalSource, Duplicates})
    end,
    #{
        source => NormalSource,
        delivery => Delivery,
        recipients => lists:sort(NormalRecipients)
    }.

normalize_source({ActorId, Port}, ActorIndex) when is_atom(Port) ->
    Actor = require_actor(ActorId, ActorIndex, route_source),
    case lists:member(Port, maps:get(outputs, Actor)) of
        true -> {ActorId, Port};
        false -> error({unknown_actor_output, ActorId, Port})
    end;
normalize_source(Source, _ActorIndex) ->
    error({invalid_route_source, Source}).

normalize_recipient(
    Recipient = {actor, ActorId},
    Source,
    ActorIndex,
    _ExternalIndex
) ->
    _ = require_actor(ActorId, ActorIndex, {route_recipient, Source}),
    Recipient;
normalize_recipient(
    Recipient = {external, ExternalId},
    Source,
    _ActorIndex,
    ExternalIndex
) ->
    case maps:is_key(ExternalId, ExternalIndex) of
        true -> Recipient;
        false -> error({unknown_external, ExternalId, {route_recipient, Source}})
    end;
normalize_recipient(Recipient, Source, _ActorIndex, _ExternalIndex) ->
    error({invalid_route_recipient, Source, Recipient}).

validate_route_interfaces(Routes, ActorIndex, ExternalIndex) ->
    lists:foreach(
        fun(Route) ->
            Source = {ActorId, Port} = maps:get(source, Route),
            SourceActor = maps:get(ActorId, ActorIndex),
            SourceInterface = maps:get(interface, SourceActor),
            Emitted = hls_actor_interface:output_schemas(
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
                        ActorIndex,
                        ExternalIndex
                    )
                end,
                maps:get(recipients, Route)
            )
        end,
        Routes
    ).

validate_route_recipient_interface(
    Source,
    SourceInterface,
    Emitted,
    Recipient = {actor, ActorId},
    ActorIndex,
    _ExternalIndex
) ->
    Destination = maps:get(ActorId, ActorIndex),
    DestinationInterface = maps:get(interface, Destination),
    Dispatched = hls_actor_interface:dispatched_schemas(
        DestinationInterface
    ),
    require_route_schemas(Source, Recipient, Emitted, Dispatched),
    lists:foreach(
        fun(Schema) ->
            SourceSchema = hls_actor_interface:schema(
                SourceInterface,
                Schema
            ),
            DestinationSchema = hls_actor_interface:schema(
                DestinationInterface,
                Schema
            ),
            SourceFields = maps:get(fields, SourceSchema),
            DestinationFields = maps:get(fields, DestinationSchema),
            case SourceFields =:= DestinationFields of
                true -> ok;
                false -> error({incompatible_route_schema_layout,
                    Source, Recipient, Schema,
                    SourceFields, DestinationFields})
            end
        end,
        Emitted
    );
validate_route_recipient_interface(
    Source,
    _SourceInterface,
    Emitted,
    Recipient = {external, ExternalId},
    _ActorIndex,
    ExternalIndex
) ->
    External = maps:get(ExternalId, ExternalIndex),
    require_route_schemas(
        Source,
        Recipient,
        Emitted,
        maps:get(schemas, External)
    ).

require_route_schemas(Source, Recipient, Emitted, Dispatched) ->
    case Emitted -- Dispatched of
        [] -> ok;
        Unsupported -> error({incompatible_route_schemas,
            Source, Recipient, Unsupported, Dispatched})
    end.

derive_lanes(Routes) ->
    LanePorts = lists:foldl(
        fun(Route, Acc0) ->
            {SourceActor, Port} = maps:get(source, Route),
            lists:foldl(
                fun(Recipient, Acc) ->
                    Key = {SourceActor, Recipient},
                    maps:update_with(Key, fun(Ports) -> [Port | Ports] end,
                        [Port], Acc)
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

normalize_startup_item({Target, Messages}, ActorIndex, FamilyIndex)
        when is_list(Messages), Messages =/= [] ->
    Actor = require_startup_target(Target, ActorIndex, FamilyIndex),
    ok = validate_startup_schemas(Target, Messages, Actor),
    #{target => Target, delivery => cast, messages => Messages};
normalize_startup_item(Spec, _ActorIndex, _FamilyIndex) ->
    error({invalid_startup_spec, Spec}).

require_startup_target(Target, ActorIndex, FamilyIndex) ->
    case maps:find(Target, ActorIndex) of
        {ok, Actor} -> Actor;
        error -> require_family_instance(Target, FamilyIndex)
    end.

require_family_instance(Target, FamilyIndex)
        when is_tuple(Target), tuple_size(Target) > 1 ->
    FamilyId = element(1, Target),
    Coordinates = tl(tuple_to_list(Target)),
    case maps:find(FamilyId, FamilyIndex) of
        {ok, Family = #{shape := Shape}}
                when length(Coordinates) =:= length(Shape) ->
            case lists:all(
                fun({Coordinate, Size}) ->
                    is_integer(Coordinate) andalso
                        Coordinate >= 0 andalso Coordinate < Size
                end,
                lists:zip(Coordinates, Shape)
            ) of
                true -> Family;
                false -> error({invalid_family_instance, Target, Shape})
            end;
        _ -> error({unknown_actor, Target, startup})
    end;
require_family_instance(Target, _FamilyIndex) ->
    error({unknown_actor, Target, startup}).

validate_startup_schemas(ActorId, Messages, Actor) ->
    Interface = maps:get(interface, Actor),
    Dispatched = hls_actor_interface:dispatched_schemas(
        Interface
    ),
    lists:foreach(
        fun({Index, Message}) ->
            case startup_schema(Message) of
                none -> ok;
                {ok, Schema} ->
                    case lists:member(Schema, Dispatched) of
                        true -> ok;
                        false -> error({incompatible_startup_schema,
                            ActorId, Index, Schema, Dispatched})
                    end
            end
        end,
        lists:enumerate(0, Messages)
    ).

startup_schema(Message) when is_tuple(Message), tuple_size(Message) > 0,
        is_atom(element(1, Message)) ->
    {ok, element(1, Message)};
startup_schema(_Message) ->
    none.

require_actor(ActorId, ActorIndex, Context) ->
    case maps:find(ActorId, ActorIndex) of
        {ok, Actor} -> Actor;
        error -> error({unknown_actor, ActorId, Context})
    end.

validate_id(Id) when is_atom(Id); is_integer(Id), Id >= 0 ->
    ok;
validate_id(Id) when is_tuple(Id), tuple_size(Id) > 0 ->
    lists:foreach(fun validate_id/1, tuple_to_list(Id));
validate_id(Id) ->
    error({invalid_topology_id, Id}).

require_unique(ErrorTag, Values) ->
    case duplicates(Values) of
        [] -> ok;
        Duplicates -> error({ErrorTag, Duplicates})
    end.

duplicates(Values) ->
    Counts = lists:foldl(
        fun(Value, Acc) ->
            maps:update_with(Value, fun(Count) -> Count + 1 end, 1, Acc)
        end,
        #{},
        Values
    ),
    lists:sort([Value || {Value, Count} <- maps:to_list(Counts), Count > 1]).

sort_by(Key, Values) ->
    lists:sort(fun(A, B) -> Key(A) < Key(B) end, Values).

ensure_static(Term) ->
    case live_value(Term) of
        none -> ok;
        Kind -> error({live_topology_value, Kind})
    end.

live_value(Term) when is_pid(Term) -> pid;
live_value(Term) when is_port(Term) -> port;
live_value(Term) when is_reference(Term) -> reference;
live_value(Term) when is_function(Term) -> function;
live_value([Head | Tail]) -> first_live([Head, Tail]);
live_value(Term) when is_tuple(Term) -> first_live(tuple_to_list(Term));
live_value(Term) when is_map(Term) ->
    first_live(lists:append([
        [Key, Value] || {Key, Value} <- maps:to_list(Term)
    ]));
live_value(_Term) -> none.

first_live([]) -> none;
first_live([Term | Rest]) ->
    case live_value(Term) of
        none -> first_live(Rest);
        Kind -> Kind
    end.
