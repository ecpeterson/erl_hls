-module(hls_partition_ingress_plan).
-moduledoc "Attaches core-materialized ingress recipients to placed actors during hls_partition planning. Runtime geometry selection and packing consume the retained bindings in hls_partition_ingress; this module does not expand families or send commands.".

%% Placed ingress derivation.
-export([lower/3]).

-doc "Checks shared ingress encodings and attaches placed actors to core-expanded exact points.".
-spec lower(hls_logical_topology:materialized_plan(), [map()], map()) -> [map()].
lower(#{ingresses := Ingresses, actors := Exact, families := []}, Actors, Interfaces) ->
    Endpoints = #{
        actors => maps:from_list([
            {Id, A#{interface => maps:get(Module, Interfaces)}}
         || A = #{id := Id, module := Module} <- Exact
        ]),
        families => #{}
    },
    ActorIndex = maps:from_list([{RawId, Actor} || Actor = #{raw_id := RawId} <- Actors]),
    [
        Ingress#{
            bindings => [
                binding(Recipient, ActorIndex)
             || Recipient <- maps:get(recipients, Ingress)
            ]
        }
     || Ingress <- xls_topology_ingress:lower(Ingresses, Endpoints)
    ].

%% Preserve one core-validated global coordinate while adding physical ownership.
-spec binding(map(), map()) -> map().
binding(#{actor := Id, at := Point, targets := Targets}, Actors) ->
    (maps:get(Id, Actors))#{point => Point, targets => Targets}.
