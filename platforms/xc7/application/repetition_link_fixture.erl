-module(repetition_link_fixture).
-moduledoc "Generates the N=6 repetition line split evenly across two physical roles.".

-export([write/1]).

-define(SIZE, 6).

-doc "Writes scheduled role graphs, RAM shells, gateway wrappers and deployment artifacts.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Plan = #{families := Families} = hls_topology:normalize(
        phi_repetition_topology:topology(?SIZE)),
    Placement = maps:from_list([{{family, Family, [X, 0]}, device(X)}
        || #{id := Family} <- Families, X <- lists:seq(0, ?SIZE-1)]),
    Direct = hls_partition:normalize(Plan, Placement),
    Scheduled = hls_partition_schedule:shared_by_module(Direct, ?SIZE div 2),
    Partition = hls_partition_reduction:attach(Plan, Scheduled,
        #{phi => source_fragments}),
    Deployment = hls_partition_binding:deployment(Partition),
    Artifacts = actor_artifacts(Stage, Partition),
    Summaries = [write_device(Stage, Partition, Deployment, Artifacts, Device)
        || Device <- [0, 1]],
    save(Stage, "fixture.json", json:encode(#{size => ?SIZE,
        split => [?SIZE div 2, ?SIZE div 2],
        transport => serial, reductions => source_fragments, devices => Summaries})),
    ok.

%% The physical cut lies between cells 2/3 and the periodic wrap 5/0.
-spec device(non_neg_integer()) -> 0 | 1.
device(X) when X < ?SIZE div 2 -> 0;
device(_X) -> 1.

%% Compile every scheduled actor against the reduction ABI selected by the partition.
-spec actor_artifacts(file:filename(), map()) -> #{module() => xls_emitted:artifact()}.
actor_artifacts(Stage, Partition = #{actors := Actors}) ->
    Requirements = hls_partition_reduction:requirements(Partition),
    Dependency = code:lib_dir(hls_phi),
    maps:from_list([begin
        Source = filename:join([Dependency, "src", atom_to_list(Module) ++ ".erl"]),
        Options = (maps:get(Module, Requirements,
            #{shared_service => ordinary}))#{mailbox_debug => true},
        Artifact = xls_scheduler_actor:to_artifact(Source, Options),
        ok = xls_emitted:write(Artifact, filename:join(Stage, atom_to_list(Module) ++ ".x")),
        {Module, Artifact}
    end || Module <- lists:usort([Module || #{module := Module} <- Actors])]).

%% Bind one generated graph to its static gateway and external block-RAM implementation.
-spec write_device(file:filename(), map(), map(),
    #{module() => xls_emitted:artifact()}, 0 | 1) -> map().
write_device(Stage, Partition, Deployment, Artifacts, Device) ->
    Role = role(Device),
    Graph = list_to_atom("repetition_role_" ++ atom_to_list(Role) ++ "_graph"),
    Local = hls_partition:device(Partition, Device),
    ok = save(Stage, atom_to_list(Graph) ++ ".x", hls_partition_dslx:emit(
        Partition, Device, #{name => Graph, channel_depth => 1,
            actor_egress_depth => burst})),
    ok = save(Stage, "phi_device_" ++ integer_to_list(Device) ++ ".x",
        xls_partition_application:emit(Deployment, Device, Graph)),
    SchedulerCount = phi_partition_ram:write(Stage, Device, Local, Artifacts),
    Bound = single_device(Deployment, Device),
    Artifact = hls_deployment_artifact:new(partition_application, Bound),
    ok = save(Stage, "deployment-" ++ atom_to_list(Role) ++ ".etf",
        hls_deployment_artifact:encode(Artifact)),
    #{role => Role, device => Device, actors => length(maps:get(actors, Local)),
        schedulers => SchedulerCount,
        tx_lanes => length(maps:get(tx_lanes, Local)),
        rx_lanes => length(maps:get(rx_lanes, Local))}.

%% Retain global ingress geometry while removing recipients owned by the other role.
-spec single_device(map(), 0 | 1) -> map().
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

%% Board role names remain compatible with the established packaging flow.
-spec role(0 | 1) -> a | b.
role(0) -> a;
role(1) -> b.

%% Fail before compilation if any generated artifact is incomplete.
-spec save(file:filename(), file:filename(), iodata()) -> ok.
save(Stage, Name, Contents) ->
    file:write_file(filename:join(Stage, Name), Contents).
