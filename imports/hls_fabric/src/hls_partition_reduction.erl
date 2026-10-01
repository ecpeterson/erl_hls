-module(hls_partition_reduction).
-moduledoc "Closed source-fragment reductions distributed over the existing ordered actor lanes.".
-export([attach/3, requirements/1, inputs/2, group/2, queue_extra/2]).

-doc "Checks source-fragment eligibility on the complete logical topology, then binds its contributors to existing partition lanes. Requires all actors scheduled; preserves wire routes and identities. The public plan's coherent-window and ordinary-mail commutation assumptions still apply.".
-spec attach(hls_topology:plan(), map(), map()) -> map().
attach(Topology = #{families := Families, actors := Exact},
        Partition = #{actors := Actors, schedulers := Groups}, Requested) ->
    Identities = lists:sort([Id || #{identity := Id} <- Actors]),
    Identities = lists:sort([Id || #{actors := Members} <- Groups, #{identity := Id} <- Members]),
    %% The public proof describes closed logical families; its scheduler format
    %% cannot express arbitrary rectangular placement. Actual physical slots
    %% remain solely in Partition, whose complete scheduled coverage is checked above.
    Refs = [{family, F} || #{id := F} <- Families] ++ [{actor, Id} || #{id := Id} <- Exact],
    Specs = maps:from_list([{Ref, #{members => [Ref], state_storage => block_ram,
        mailbox_storage => block_ram}} || Ref <- Refs]),
    Schedule = hls_scheduler_plan:normalize(Topology, Specs),
    #{direct_members := []} = Schedule,
    Proof = #{placements := Placements} = hls_reduction_plan:normalize(Topology, Schedule, Requested),
    Selected = maps:from_list([{F, P} || P = #{family := F} <- Placements]),
    Destinations = maps:from_list([{Id, contributors(A, maps:get(F, Selected), Partition)}
        || A = #{identity := Id = {family, F, _}} <- maps:get(actors, Partition), maps:is_key(F, Selected)]),
    Partition#{reduction_plan => Proof, reduction_inputs => Destinations}.

%% Every captured lane contains only the proved prefix, possibly with several aliased ports in order.
-spec contributors(map(), map(), map()) -> [map()].
contributors(#{identity := Id = {family, F, _}}, #{fragments := Fragments, population := N}, #{lanes := Lanes}) ->
    Ports = [P || #{port := P} <- Fragments],
    Inputs = [begin
        true = lists:all(fun(P) -> lists:member(P, Ports) end, LanePorts),
        L#{multiplicity => length(LanePorts)}
    end || L = #{source := {family, SourceFamily, _}, destination := {actor, Target}, ports := LanePorts} <- Lanes,
        SourceFamily =:= F, Target =:= Id, lists:any(fun(P) -> lists:member(P, Ports) end, LanePorts)],
    N = lists:sum([Count || #{multiplicity := Count} <- Inputs]),
    Inputs.

-doc "Returns compiler artifact requirements; unselected modules use ordinary reductions.".
-spec requirements(map()) -> map().
requirements(#{reduction_plan := Proof}) -> hls_reduction_plan:artifact_requirements(Proof);
requirements(_) -> #{}.

-doc "Returns this actor's contribution lanes, including multiplicity for aliased ports.".
-spec inputs(map(), map()) -> [map()].
inputs(#{identity := Id}, Partition) -> maps:get(Id, maps:get(reduction_inputs, Partition, #{}), []).

-doc "Reports whether a scheduler's module requires aggregate-only execution.".
-spec group(map(), map()) -> boolean().
group(#{module := Module}, Partition) ->
    maps:get(Module, requirements(Partition), #{shared_service => ordinary}) =:= #{shared_service => aggregate_only}.

-doc "Returns the extra upstream slots replacing an unaliased fragment queue and its delivery register.".
-spec queue_extra(non_neg_integer(), map()) -> 0 | 3.
queue_extra(Lane, Partition) ->
    case [N || Inputs <- maps:values(maps:get(reduction_inputs, Partition, #{})),
               #{id := Id, multiplicity := N} <- Inputs, Id =:= Lane] of
        [1] -> 3;
        _ -> 0
    end.
