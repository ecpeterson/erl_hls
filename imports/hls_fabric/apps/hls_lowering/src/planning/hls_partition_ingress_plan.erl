-module(hls_partition_ingress_plan).
-moduledoc "Lowers topology ingress into placed host recipients during hls_partition planning. Runtime geometry selection and packing consume the retained bindings in hls_partition_ingress; this module does not send commands.".

%% Placed ingress derivation.
-export([lower/3]).

-doc "Checks shared ingress encodings and expands logical selections to placed actor points.".
-spec lower(hls_topology:plan(), [map()], map()) -> [map()].
lower(#{ingresses := Ingresses, actors := Exact, families := Families}, Actors, Interfaces) ->
    Endpoints = maps:from_list([
        {Kind,
            maps:from_list([
                {Id, A#{interface => maps:get(Module, Interfaces)}}
             || A = #{id := Id, module := Module} <- Entries
            ])}
     || {Kind, Entries} <- [{actors, Exact}, {families, Families}]
    ]),
    [
        Ingress#{
            bindings => lists:append([
                bindings(R, Actors)
             || R <- maps:get(recipients, Ingress)
            ])
        }
     || Ingress <- xls_topology_ingress:lower(Ingresses, Endpoints)
    ].

%% Preserve global embedded coordinates; placement changes only delivery ownership.
-spec bindings(map(), [map()]) -> [map()].
bindings(#{family := Family, scale := [SX, SY], offset := [OX, OY], targets := Targets}, Actors) ->
    [
        A#{point => [OX + SX * X, OY + SY * Y], targets => Targets}
     || A = #{identity := {family, Id, [X, Y]}} <- Actors, Id =:= Family
    ];
bindings(#{actor := Actor, at := Point, targets := Targets}, Actors) ->
    [
        A#{point => Point, targets => Targets}
     || A = #{identity := {actor, Id}} <- Actors, Id =:= Actor
    ].
