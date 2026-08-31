%%%% xls_topology
%%%%
%%%% Normalizes the first deliberately small actor-topology representation.

-module(xls_topology).
-moduledoc """
Normalizes a provisional, closed actor topology expressed as ordinary Erlang
data.

Version 0 contains exact actor instances, external outputs, exact routes,
explicit multi-recipient delivery modes, and per-actor startup messages. It
intentionally has no lifecycle, placement, transport, numeric tags, or
generated-hardware concepts. Actor output names, their artifact ABI order, and
mailbox bounds are read from compiled actor modules rather than repeated in the
topology.

Actor declarations are a map from logical instance ID to actor module. IDs are
atoms, nonnegative integers, or nonempty tuples recursively
containing those values, so a regular family can use IDs such as `{phi, X, Y}`
without allocating an atom per instance. This solves instance identity and atom
allocation, but it does not compactly represent a family; parametric families
belong in a later rule-preserving representation. The normalized plan is a
sorted list for deterministic traversal; consumers build maps when they need
indexed lookup.

Every actor output must have exactly one disposition, every referenced
endpoint must exist, and live runtime identities are rejected. Normalization
sorts unordered input, preserves message order within each startup target, and
derives sender-to-recipient ordering lanes.

A singleton route is `{Source, [Recipient]}`. A route with two or more
recipients is `{Source, Delivery, Recipients}` so fanout cannot acquire an
implicit completion rule. Version 0 distinguishes four semantic completion
points:

  * `coupled`: the source event completes after every recipient accepts;
  * `buffered`: it completes after every bounded branch queue accepts;
  * `queued`: it completes after one common bounded egress queue accepts, and
    a downstream lossless distributor subsequently waits for every branch;
  * `best_effort`: explicitly selected branches may drop.

A backend may implement only a subset, but it must not silently rename one
completion point as another.

The current actor metadata does not identify the schemas accepted by each
callback or emitted by each output. Schema compatibility therefore remains a
later actor-lowering check; this module does not infer it from a wire codebook.
Reading attributes from loaded modules is temporary scaffolding for that future
actor catalog, not the intended long-term catalog boundary.
""".

-export([from_module/1, normalize/1]).
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

-doc "Validates and canonicalizes one version-0 topology term.".
-spec normalize(spec()) -> plan().
normalize(Spec) ->
    ok = ensure_static(Spec),
    ok = validate_top_level(Spec),
    0 = validate_version(maps:get(version, Spec)),

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
    Startup = normalize_startup(maps:get(startup, Spec), ActorIndex),

    #{
        version => 0,
        actors => Actors,
        externals => Externals,
        routes => Routes,
        startup => Startup,
        lanes => derive_lanes(Routes)
    }.

%%%
%%% Actor and external endpoints
%%%

validate_top_level(Spec) when is_map(Spec) ->
    Required = [actors, externals, routes, startup, version],
    Keys = maps:keys(Spec),
    case {Required -- Keys, Keys -- Required} of
        {[], []} -> ok;
        {Missing, Unknown} ->
            error({invalid_topology_keys, Missing, Unknown})
    end;
validate_top_level(_Spec) ->
    error({invalid_topology, expected_map}).

validate_version(0) -> 0;
validate_version(Version) -> error({unsupported_topology_version, Version}).

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
        {module, Module} -> actor_attributes(Id, Module);
        {error, Reason} ->
            error({topology_actor_unavailable, Id, Module, Reason})
    end.

actor_attributes(Id, Module) ->
    Attributes = Module:module_info(attributes),
    case lists:member(
        xls_statem,
        proplists:get_value(behavior, Attributes, [])
    ) of
        true -> ok;
        false -> error({not_an_xls_statem_actor, Id, Module})
    end,
    Outputs = attribute(Id, Module, xls_outputs, Attributes),
    case is_list(Outputs) andalso
            lists:all(fun erlang:is_atom/1, Outputs) of
        true -> require_unique(duplicate_actor_outputs, Outputs);
        false -> error({invalid_actor_outputs, Id, Module, Outputs})
    end,
    Capacity = case attribute(
        Id,
        Module,
        xls_mailbox_capacity,
        Attributes
    ) of
        [Value] when is_integer(Value), Value > 0 -> Value;
        Value -> error({invalid_actor_mailbox_capacity, Id, Module, Value})
    end,
    #{
        id => Id,
        module => Module,
        outputs => Outputs,
        mailbox_capacity => Capacity
    }.

attribute(Id, Module, Name, Attributes) ->
    case proplists:get_value(Name, Attributes, '$missing') of
        '$missing' -> error({missing_actor_attribute, Id, Module, Name});
        Value -> Value
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
        [] -> sort_by(fun(Route) -> maps:get(source, Route) end, Routes);
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

normalize_startup(Specs, ActorIndex) when is_list(Specs) ->
    Startup = [normalize_startup_item(Spec, ActorIndex) || Spec <- Specs],
    require_unique(
        duplicate_startup_targets,
        [maps:get(target, Item) || Item <- Startup]
    ),
    sort_by(fun(Item) -> maps:get(target, Item) end, Startup);
normalize_startup(Specs, _ActorIndex) ->
    error({invalid_topology_field, startup, Specs}).

normalize_startup_item({ActorId, Messages}, ActorIndex)
        when is_list(Messages), Messages =/= [] ->
    _ = require_actor(ActorId, ActorIndex, startup),
    #{target => ActorId, delivery => cast, messages => Messages};
normalize_startup_item(Spec, _ActorIndex) ->
    error({invalid_startup_spec, Spec}).

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
