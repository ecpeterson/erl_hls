-module(link_probe_fixture).
-moduledoc "Generates the two role-specific actor partitions and host bindings.".

-export([write/2]).

-doc "Writes actor DSLX, per-role graphs/wrappers and versioned local deployment artifacts.".
-spec write(file:filename(), file:filename()) -> ok.
write(Stage, ActorSource) ->
    Plan = hls_topology:normalize(#{
        version => 1,
        actors => #{origin => hls_link_probe_actor, responder => hls_link_probe_actor},
        families => #{},
        ingresses => [{control, {rectangle, [2, 1]}, [{nodes, [launch],
            [{actor, origin, {at, [0, 0]}}, {actor, responder, {at, [1, 0]}}]}]}],
        externals => [{reports, out, [observed]}],
        routes => [
            {{origin, peer}, [{actor, responder}]},
            {{origin, report}, [{external, reports}]},
            {{responder, peer}, [{actor, origin}]},
            {{responder, report}, [{external, reports}]}
        ],
        route_relations => [],
        startup => []
    }),
    Placement = #{{actor, origin} => a, {actor, responder} => b},
    Partition = hls_partition:normalize(Plan, Placement),
    Deployment = hls_partition_binding:deployment(Partition),
    ok = save(Stage, "hls_link_probe_actor.x", xls_scheduler_actor:to_xls(ActorSource, #{})),
    lists:foreach(fun(Device) -> write_device(Stage, Partition, Deployment, Device) end, [a, b]),
    Summary = #{devices => [device_summary(Deployment, Device) || Device <- [a, b]],
        transport => serial, actor => hls_link_probe_actor},
    ok = save(Stage, "fixture.json", json:encode(Summary)),
    ok.

%% Bind one compiled graph to the device-specific gateway identity and host endpoint.
-spec write_device(file:filename(), map(), map(), a | b) -> ok.
write_device(Stage, Partition, Deployment, Device) ->
    Graph = list_to_atom("link_probe_" ++ atom_to_list(Device) ++ "_graph"),
    GraphSource = hls_partition_dslx:emit(Partition, Device,
        #{name => Graph, channel_depth => 1, actor_egress_depth => burst}),
    ok = save(Stage, atom_to_list(Graph) ++ ".x", GraphSource),
    ok = save(Stage, "link_application_" ++ atom_to_list(Device) ++ ".x",
        xls_partition_application:emit(Deployment, Device, Graph)),
    Local = single_device(Deployment, Device),
    Artifact = hls_deployment_artifact:new(partition_application, Local),
    save(Stage, "deployment-" ++ atom_to_list(Device) ++ ".etf",
        hls_deployment_artifact:encode(Artifact)).

%% Retain global ingress geometry while removing recipients owned by the other role.
-spec single_device(map(), a | b) -> map().
single_device(Deployment = #{partition := Partition, devices := Devices}, Device) ->
    Ingresses = [
        Ingress#{bindings := [
            Binding
         || Binding = #{device := Bound} <- maps:get(bindings, Ingress), Bound =:= Device
        ]}
     || Ingress <- maps:get(ingresses, Partition)
    ],
    Deployment#{
        partition := Partition#{ingresses := Ingresses},
        devices := maps:with([Device], Devices)
    }.

%% Retain only publication-safe identity data in the JSON build summary.
-spec device_summary(map(), a | b) -> map().
device_summary(#{devices := Devices}, Device) ->
    #{host := Host, control := Control, identity := Identity} = maps:get(Device, Devices),
    #{role => Device, host => Host, control => Control,
        identity_sha256 => binary:encode_hex(crypto:hash(sha256, Identity), lowercase)}.

%% Write one complete generated artifact under the caller-owned stage.
-spec save(file:filename(), file:filename(), iodata()) -> ok.
save(Stage, Name, Contents) -> file:write_file(filename:join(Stage, Name), Contents).
