%%%% phi_memory_boundary
%%%%
%%%% Example-local deployment contract for the phi memory bridge.

-module(phi_memory_boundary).
-moduledoc """
Derives the phi memory bridge contract from `phi_noise_topology`.

The compact topology and generated actor codecs remain authoritative for the
spatial ingress, target selectors, message schemas, producer modules, and
external order. This profile adds the physical facts which topology semantics
do not supply: boundary version one, host endpoint zero, and stable endpoint
allocation beginning with the ingress at one. Both the host codec and the DSLX
gateway generator consume this contract. Application endpoints three and five
remain reserved for the visualization-only announcement streams removed from
the lossless boundary.

This module deliberately reads the compact source term rather than loading the
topology compiler in the deployed ERTS node. Development tests compare its
canonical ordering and shapes with `hls_topology:normalize/1`.

Each schema descriptor records the actor-owned selector and packed width. The
derivation rejects a multicast target whose recipient artifacts disagree on
either fact, and an external whose possible producer artifacts disagree.
""".

%% Host and gateway boundary contract.
-export([contract/1, version/0]).

%% Topology-derived wire facts shared by the host codec and gateway renderer.
-export_type([contract/0, schema/0, target/0, output/0]).

-doc "Actor selector, checked whole-word payload width, and one representative codec provider.".
-type schema() :: #{
    name := atom(),
    module := module(),
    selector := byte(),
    width := pos_integer(),
    payload_words := pos_integer()
}.
-doc "One data/noise multicast target and the compatible schemas accepted by all its actor modules.".
-type target() :: #{
    id := data | noise,
    index := 0..3,
    modules := [module()],
    schemas := [schema()]
}.
-doc "One lossless external stream with a fixed source endpoint and compatible producer schemas.".
-type output() :: #{
    id := phi_memory_experiment:stream(),
    stream := phi_memory_experiment:stream(),
    endpoint := 2 | 4 | 6,
    modules := [module()],
    schemas := [schema()]
}.
-doc "Version-one routed boundary derived for a selected Phi/noise distance.".
-type contract() :: #{
    version := 1,
    host_endpoint := 0,
    ingress := #{
        id := control_router,
        endpoint := 1,
        shape := [pos_integer()],
        targets := [target()]
    },
    outputs := [output()]
}.

%% Compact family declarations supply the module that owns each generated codec.
-type families() :: #{atom() => #{module := module(), shape := [pos_integer()]}}.
%% This example uses translated family neighbors and named external recipients.
-type relation() :: {{atom(), atom()}, [
    {family, atom(), {translate, [integer()], wrap}} | {external, atom()}
]}.
%% Rectangle targets embed family coordinates into the physical data-qubit grid.
-type raw_target() :: {data | noise, [atom()], [{family, atom(), {embed, [integer()], [integer()]}}]}.

-define(VERSION, 1).
-define(HOST_ENDPOINT, 0).

-doc "Returns the example boundary version.".
-spec version() -> 1.
version() -> ?VERSION.

-doc "Derives the routed boundary for the given code distance.".
-spec contract(pos_integer()) -> contract().
contract(Distance) ->
    #{
        ingresses := [Ingress],
        externals := Externals,
        families := Families,
        route_relations := Relations
    } = phi_noise_topology:topology(Distance, 0),
    Contract = #{
        version => ?VERSION,
        host_endpoint => ?HOST_ENDPOINT,
        ingress => ingress(Ingress, Families),
        outputs => outputs(
            lists:keysort(1, Externals),
            Relations,
            Families
        )
    },
    ok = validate_command_selectors(Contract),
    Contract.

%% Assign the one gateway endpoint and sort target names before allocating their two-bit indices.
-spec ingress({control_router, {rectangle, [pos_integer()]}, [raw_target()]}, families()) ->
    #{id := control_router, endpoint := 1, shape := [pos_integer()], targets := [target()]}.
ingress({Id, {rectangle, Shape}, Targets}, Families) ->
    #{
        id => Id,
        endpoint => 1,
        shape => Shape,
        targets => [
            target(Index, Target, Families)
         || {Index, Target} <-
                lists:enumerate(0, lists:keysort(1, Targets))
        ]
    }.

%% Resolve recipient modules and require their schema selectors and widths to agree; reject a fifth target.
-spec target(non_neg_integer(), raw_target(), families()) -> target().
target(
    Index,
    {Target, Schemas, Recipients},
    Families
) when Index < 4 ->
    Modules = lists:usort([
        maps:get(module, maps:get(Family, Families))
     || {family, Family, _Embedding} <- Recipients
    ]),
    #{
        id => Target,
        index => Index,
        modules => Modules,
        schemas => schemas(lists:sort(Schemas), Modules)
    };
target(_Index, {Target, _Schemas, _Recipients}, _Families) ->
    error({target, Target}).

%% Retain only output externals and attach their fixed application endpoint assignments.
-spec outputs([{phi_memory_experiment:stream(), out, [atom()]}], [relation()], families()) ->
    [output()].
outputs(Externals, Relations, Families) ->
    [
        output(output_endpoint(Id), External, Relations, Families)
     || External = {Id, out, _Schemas} <- Externals
    ].

%% Keep the lossless stream endpoints stable while leaving announcement endpoints three and five reserved.
-spec output_endpoint(phi_memory_experiment:stream()) -> 2 | 4 | 6.
output_endpoint(data_measurements) -> 2;
output_endpoint(x_decoder_events) -> 4;
output_endpoint(z_decoder_events) -> 6.

%% Bind each external schema to all possible producer modules before exposing it to the host.
-spec output(2 | 4 | 6, {phi_memory_experiment:stream(), out, [atom()]}, [relation()], families()) ->
    output().
output(
    Endpoint,
    {Id, out, Schemas},
    Relations,
    Families
) ->
    Modules = producer_modules(Id, Relations, Families),
    #{
        id => Id,
        stream => Id,
        endpoint => Endpoint,
        modules => Modules,
        schemas => schemas(lists:sort(Schemas), Modules)
    }.

%% Find the unique actor modules whose compact relations reach the named external.
-spec producer_modules(atom(), [relation()], families()) -> [module()].
producer_modules(External, Relations, Families) ->
    lists:usort([
        maps:get(module, maps:get(Source, Families))
     || Relation <- Relations,
        {Source, Recipients} <- [relation_recipients(Relation)],
        lists:member({external, External}, Recipients)
    ]).

%% This profile derives producers from the example's implicit-delivery relations.
-spec relation_recipients({{atom(), atom()}, [term()]}) -> {atom(), [term()]}.
relation_recipients({{Source, _Port}, Recipients}) ->
    {Source, Recipients}.

%% Reject selector reuse across ingress targets, since the wire command carries no separate target index.
-spec validate_command_selectors(contract()) -> ok.
validate_command_selectors(#{ingress := #{targets := Targets}}) ->
    Selectors = [
        {maps:get(selector, Schema), maps:get(name, Schema)}
     || #{schemas := Schemas} <- Targets,
        Schema <- Schemas
    ],
    case length(Selectors) =:= length(lists:ukeysort(1, Selectors)) of
        true -> ok;
        false -> error({selectors, Selectors})
    end.

%% Resolve each requested schema against a nonempty producer set; an unowned schema is invalid.
-spec schemas([atom()], [module()]) -> [schema()].
schemas(Names, [_ | _] = Modules) ->
    [schema(Name, Modules) || Name <- Names];
schemas(_Names, []) ->
    error(schema_modules).

%% Require identical selectors and positive whole-word payload widths no greater than three words across all modules.
-spec schema(atom(), nonempty_list(module())) -> schema().
schema(Name, [Module | Rest]) ->
    Selector = Module:pack_tag(Name),
    Width = Module:pack_width(Name),
    true = Width > 0 andalso Width rem 32 =:= 0 andalso Width =< 96,
    lists:foreach(
        fun(Other) ->
            Selector = Other:pack_tag(Name),
            Width = Other:pack_width(Name)
        end,
        Rest
    ),
    #{
        name => Name,
        module => Module,
        selector => Selector,
        width => Width,
        payload_words => Width div 32
    }.
