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

-export([contract/1, version/0]).

-define(VERSION, 1).
-define(HOST_ENDPOINT, 0).

-doc "Returns the example boundary version.".
-spec version() -> 1.
version() -> ?VERSION.

-doc "Derives the routed boundary for the given code distance.".
-spec contract(pos_integer()) -> map().
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

outputs(Externals, Relations, Families) ->
    [
        output(output_endpoint(Id), External, Relations, Families)
        || External = {Id, out, _Schemas} <- Externals
    ].

output_endpoint(data_measurements) -> 2;
output_endpoint(x_decoder_events) -> 4;
output_endpoint(z_decoder_events) -> 6.

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

producer_modules(External, Relations, Families) ->
    lists:usort([
        maps:get(module, maps:get(Source, Families))
        || Relation <- Relations,
           {Source, Recipients} <- [relation_recipients(Relation)],
           lists:member({external, External}, Recipients)
    ]).

relation_recipients({{Source, _Port}, Recipients}) ->
    {Source, Recipients};
relation_recipients({{Source, _Port}, _Delivery, Recipients}) ->
    {Source, Recipients}.

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

schemas(Names, [_ | _] = Modules) ->
    [schema(Name, Modules) || Name <- Names];
schemas(_Names, []) ->
    error(schema_modules).

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
