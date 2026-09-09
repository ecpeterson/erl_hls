%%%% hls_reduction_plan
%%%%
%%%% Topology proof for source-fragment reduction placement.

-module(hls_reduction_plan).
-moduledoc """
Builds placement facts for the explicitly selected source-fragment reduction
subset from normalized logical plans and public actor summaries.

The structural proof establishes a complete, fixed, inverse-closed exchange
and requires every captured schema to have a message-only, exhaustive
contribution dispatch. Guarded or refutable contributions may remain in an
ordinary actor, but their same-schema fallback cannot be routed through a
whole-schema source-fragment plane.
It cannot derive two application properties from callback expressions: actors
must traverse coherent reduction windows, and completion may commute with
unrelated mail. Each placement therefore reports those properties as
`semantic_assumptions`. Given them, inverse pairing bounds a fragment to the
current and one following reduction, reported as `fragment_capacity => 2`.
""".

-export([artifact_requirements/1, normalize/3]).
-export_type([plan/0]).

-type plan() :: #{
    placements := [map()],
    artifact_requirements := #{module() := #{
        shared_service := ordinary | aggregate_only
    }}
}.

-doc "Validates requested placements and derives their topology proof.".
-spec normalize(hls_topology:plan(), hls_scheduler_plan:plan(), map()) -> plan().
normalize(Topology, Scheduler, Requested) ->
    ok = validate_inputs(Topology, Scheduler, Requested),
    Families = maps:get(families, Topology),
    FamilyIndex = index_by_id(Families),
    Interfaces = module_interfaces(Families),
    Selections = validate_selections(Requested, FamilyIndex),
    ok = validate_scheduler_modules(Topology, Scheduler),
    Placements = [
        analyze_family(maps:get(FamilyId, FamilyIndex),
            maps:get(maps:get(module, maps:get(FamilyId, FamilyIndex)), Interfaces),
            Topology, Scheduler, Interfaces)
        || {FamilyId, source_fragments} <- Selections
    ],
    #{placements => Placements,
      artifact_requirements => derive_artifact_requirements(Scheduler, Requested)}.

-doc "Returns the shared-module requirements from a normalized plan.".
-spec artifact_requirements(plan()) -> map().
artifact_requirements(#{artifact_requirements := Requirements}) when is_map(Requirements) ->
    Requirements;
artifact_requirements(_Plan) ->
    error({invalid_reduction_plan, expected_artifact_requirements}).

analyze_family(#{id := FamilyId, module := Module, shape := Shape}, Interface,
        Topology, Scheduler, Interfaces) ->
    ok = require_2d(FamilyId, Shape),
    GroupIds = scheduled_groups(FamilyId, Module, Scheduler),
    Reductions = require_reductions(FamilyId, Interface),
    Sites = [analyze_site(FamilyId, Site, Interface, Topology)
        || Site <- maps:get(sites, Reductions)],
    ok = require_unique_schemas(FamilyId, Sites),
    {Population, Pattern} = common_pattern(FamilyId, Sites),
    Captured = lists:append([maps:get(captured, Site) || Site <- Sites]),
    Ports = lists:usort([maps:get(port, Effect) || Effect <- Captured]),
    ok = validate_port_uses(FamilyId, Interface, Captured, Ports),
    Relations = maps:get(route_relations, Topology),
    ok = validate_self_relations(FamilyId, Relations, Ports),
    Schemas = lists:usort([maps:get(contribution_schema, Site) || Site <- Sites]),
    ok = validate_contribution_closure(
        FamilyId, Shape, Schemas, Ports, Topology, Interfaces
    ),
    #{kind => source_fragments, family => FamilyId, module => Module, shape => Shape,
      scheduler_groups => GroupIds, population => Population,
      sites => [maps:without([captured, pattern], Site) || Site <- Sites],
      fragments => prove_fragments(FamilyId, Shape, Pattern), fragment_capacity => 2,
      semantic_assumptions => [coherent_window_sequence,
          unrelated_mail_commutes_with_completion]}.

require_2d(_FamilyId, [Width, Height]) when Width > 0, Height > 0 -> ok;
require_2d(FamilyId, Shape) ->
    error({source_fragment_requires_2d_family, FamilyId, Shape}).

require_reductions(FamilyId, Interface) ->
    case maps:get(reductions, Interface, none) of
        #{sites := [_ | _]} = Reductions -> Reductions;
        none -> error({source_fragment_requires_reductions, FamilyId});
        Other -> error({source_fragment_reductions, FamilyId, Other})
    end.

analyze_site(FamilyId, #{id := Id, phase := Phase, name := Name,
        population := Population, contributions := Contributions,
        source_transportable := SourceTransportable} = Site,
        Interface, Topology) ->
    Schema = case Contributions of
        [Only] -> Only;
        _ -> error({source_fragment_site_contributions, FamilyId, Id, Contributions})
    end,
    case SourceTransportable of
        true -> ok;
        false -> error({source_fragment_nontransportable_contribution,
            FamilyId, Id, Schema})
    end,
    case maps:get(source_capture_total, Site, false) of
        true -> ok;
        false -> error({source_fragment_nonexhaustive_contribution,
            FamilyId, Id, Schema})
    end,
    Size = maps:get(size, Population),
    Effects = phase_effects(FamilyId, Phase, Interface),
    Prefix = require_prefix(FamilyId, Phase, Schema, Size, Effects),
    Pattern = [effect_translation(FamilyId, Phase, Effect, Topology) || Effect <- Prefix],
    #{id => Id, phase => Phase, name => Name, population => Population,
      contribution_schema => Schema, pattern => Pattern, captured => Prefix}.

phase_effects(FamilyId, Phase, Interface) ->
    Effects = [Effect || Effect <- maps:get(entry_effects, Interface),
        maps:get(phase, Effect) =:= Phase],
    Orders = [maps:get(order, Effect) || Effect <- Effects],
    case duplicates(Orders) of
        [] -> lists:sort(fun(A, B) -> maps:get(order, A) < maps:get(order, B) end, Effects);
        Ds -> error({source_fragment_duplicate_effect_orders, FamilyId, Phase, Ds})
    end.

require_prefix(FamilyId, Phase, Schema, Size, Effects) ->
    Prefix = lists:sublist(Effects, Size),
    case length(Prefix) of
        Size -> ok;
        Actual -> error({source_fragment_short_prefix, FamilyId, Phase, Size, Actual})
    end,
    lists:foreach(fun({Ordinal, Effect}) ->
        prefix_effect(FamilyId, Phase, Ordinal, Schema, Effect)
    end, lists:enumerate(0, Prefix)),
    case lists:nthtail(Size, Effects) of
        [#{schema := Schema} | _] ->
            error({source_fragment_excess_prefix, FamilyId, Phase, Schema, Size});
        _ -> ok
    end,
    Prefix.

prefix_effect(FamilyId, Phase, Ordinal, Schema, #{schema := Schema} = Effect) ->
    case maps:get(conditional, Effect, false) of
        false -> ok;
        true -> error({source_fragment_conditional_prefix,
            FamilyId, Phase, Ordinal, maps:get(port, Effect)})
    end;
prefix_effect(FamilyId, Phase, Ordinal, Schema, Effect) ->
    error({source_fragment_prefix_schema,
        FamilyId, Phase, Ordinal, Schema, maps:get(schema, Effect)}).

effect_translation(FamilyId, Phase, #{port := Port}, Topology) ->
    Matches = [Relation || Relation <- maps:get(route_relations, Topology),
        maps:get(source, Relation) =:= {FamilyId, Port}],
    case Matches of
        [#{delivery := direct, recipients := [{family, FamilyId,
                {translate, [DX, DY] = Offset, wrap}}]}]
                when is_integer(DX), is_integer(DY) ->
            #{port => Port, offset => Offset};
        _ -> error({source_fragment_effect_relation, FamilyId, Phase, Port, Matches})
    end.

require_unique_schemas(FamilyId, Sites) ->
    Tagged = [{maps:get(contribution_schema, Site), maps:get(id, Site)} || Site <- Sites],
    Groups = lists:foldl(fun({Schema, Id}, Acc) ->
        maps:update_with(Schema, fun(Ids) -> [Id | Ids] end, [Id], Acc)
    end, #{}, Tagged),
    case [{Schema, lists:sort(Ids)} || {Schema, Ids} <- lists:sort(maps:to_list(Groups)),
            length(Ids) > 1] of
        [] -> ok;
        Ambiguous -> error({source_fragment_ambiguous_schemas, FamilyId, Ambiguous})
    end.

common_pattern(FamilyId, [First | Rest]) ->
    Population = maps:get(population, First),
    Expected = {Population, maps:get(pattern, First)},
    lists:foreach(fun(Site) ->
        Actual = {maps:get(population, Site), maps:get(pattern, Site)},
        case Actual =:= Expected of
            true -> ok;
            false -> error({source_fragment_inconsistent_site, FamilyId,
                maps:get(id, First), Expected, maps:get(id, Site), Actual})
        end
    end, Rest),
    {maps:get(size, Population), maps:get(pattern, First)}.

validate_port_uses(FamilyId, Interface, Captured, Ports) ->
    Keys = maps:from_list([{{maps:get(phase, E), maps:get(order, E)}, true}
        || E <- Captured]),
    lists:foreach(fun(Effect) ->
        Port = maps:get(port, Effect),
        Key = {maps:get(phase, Effect), maps:get(order, Effect)},
        case lists:member(Port, Ports) andalso not maps:is_key(Key, Keys) of
            true -> error({source_fragment_captured_port_reused, FamilyId,
                maps:get(phase, Effect), maps:get(order, Effect), Port,
                maps:get(schema, Effect)});
            false -> ok
        end
    end, maps:get(entry_effects, Interface)).

validate_self_relations(FamilyId, Relations, Ports) ->
    lists:foreach(fun(Relation = #{source := {SourceFamily, Port}}) ->
        case SourceFamily =:= FamilyId andalso targets_family(Relation, FamilyId)
                andalso not lists:member(Port, Ports) of
            true -> error({source_fragment_uncaptured_self_relation, FamilyId, Port});
            false -> ok
        end
    end, Relations).

validate_contribution_closure(
    FamilyId, Shape, Schemas, Ports, Topology, Interfaces
) ->
    lists:foreach(fun(Relation = #{source := {SourceFamily, Port}}) ->
        Captured = SourceFamily =:= FamilyId andalso lists:member(Port, Ports),
        case targets_family(Relation, FamilyId) andalso not Captured of
            true ->
                Module = family_module(SourceFamily, Topology),
                Emitted = hls_actor_interface:output_schemas(maps:get(Module, Interfaces), Port),
                no_intersection({source_fragment_uncaptured_contribution_relation,
                    FamilyId, {SourceFamily, Port}}, Schemas, Emitted);
            false -> ok
        end
    end, maps:get(route_relations, Topology)),
    validate_ingresses(FamilyId, Schemas, maps:get(ingresses, Topology)),
    validate_startup(FamilyId, Shape, Schemas, maps:get(startup, Topology)).

validate_ingresses(FamilyId, Schemas, Ingresses) ->
    lists:foreach(fun(#{id := IngressId, targets := Targets}) ->
        lists:foreach(fun(Target = #{id := TargetId, schemas := Offered}) ->
            case ingress_targets(Target, FamilyId) of
                true -> no_intersection({source_fragment_contribution_ingress,
                    FamilyId, IngressId, TargetId}, Schemas, Offered);
                false -> ok
            end
        end, Targets)
    end, Ingresses).

validate_startup(FamilyId, Shape, Schemas, Startup) ->
    lists:foreach(fun(#{target := Target, messages := Messages}) ->
        case is_family_instance(Target, FamilyId, Shape) of
            true -> lists:foreach(fun({Index, Message}) ->
                case message_schema(Message) of
                    unknown -> error({source_fragment_untyped_startup,
                        FamilyId, Target, Index, Message});
                    Schema -> case lists:member(Schema, Schemas) of
                        true -> error({source_fragment_contribution_startup,
                            FamilyId, Target, Index, Schema});
                        false -> ok
                    end
                end
            end, lists:enumerate(0, Messages));
            false -> ok
        end
    end, Startup).

no_intersection(ErrorPrefix, Left, Right) ->
    case lists:usort([Value || Value <- Left, lists:member(Value, Right)]) of
        [] -> ok;
        Values -> error(erlang:append_element(ErrorPrefix, Values))
    end.

targets_family(#{recipients := Recipients}, FamilyId) ->
    lists:any(fun
        ({family, Candidate, _}) -> Candidate =:= FamilyId;
        (_) -> false
    end, Recipients).

ingress_targets(#{recipients := Recipients}, FamilyId) ->
    lists:any(fun
        (#{family := Candidate}) -> Candidate =:= FamilyId;
        (_) -> false
    end, Recipients).

is_family_instance(Target, FamilyId, Shape) when is_tuple(Target) ->
    Coordinates = tl(tuple_to_list(Target)),
    tuple_size(Target) =:= length(Shape) + 1 andalso
        element(1, Target) =:= FamilyId andalso
        lists:all(fun({Coordinate, Size}) ->
            is_integer(Coordinate) andalso
                Coordinate >= 0 andalso Coordinate < Size
        end, lists:zip(Coordinates, Shape));
is_family_instance(_Target, _FamilyId, _Shape) -> false.

message_schema(Message) when is_tuple(Message), tuple_size(Message) > 0,
        is_atom(element(1, Message)) -> element(1, Message);
message_schema(_Message) -> unknown.

prove_fragments(FamilyId, Shape, Pattern) ->
    Indexed = lists:enumerate(0, Pattern),
    lists:foreach(fun({_Ordinal, #{offset := Offset}}) ->
        Normal = normalize_offset(Offset, Shape),
        case Offset =:= Normal of
            true -> ok;
            false -> error({source_fragment_non_normalized_offset, FamilyId, Offset, Normal})
        end,
        Inverse = normalize_offset(negate(Offset), Shape),
        Residues = [positive_mod(D + I, Size)
            || {D, I, Size} <- lists:zip3(Offset, Inverse, Shape)],
        case Residues =:= [0, 0] of
            true -> ok;
            false -> error({source_fragment_non_bijective_translation,
                FamilyId, Offset, Shape})
        end
    end, Indexed),
    Offsets = [maps:get(offset, Fragment) || {_I, Fragment} <- Indexed],
    Counts = counts(Offsets),
    lists:foreach(fun(Offset) ->
        Inverse = normalize_offset(negate(Offset), Shape),
        case maps:get(Offset, Counts) =:= maps:get(Inverse, Counts, 0) of
            true -> ok;
            false -> error({source_fragment_offsets_not_inverse_closed,
                FamilyId, Offset, Inverse, Offsets})
        end
    end, lists:sort(maps:keys(Counts))),
    [fragment(Ordinal, Item, Indexed, Shape) || {Ordinal, Item} <- Indexed].

fragment(Ordinal, #{port := Port, offset := Offset}, Indexed, Shape) ->
    Inverse = normalize_offset(negate(Offset), Shape),
    Rank = 1 + length([I || {I, #{offset := O}} <- Indexed, I < Ordinal, O =:= Offset]),
    InverseOrdinal = lists:nth(Rank, [I || {I, #{offset := O}} <- Indexed, O =:= Inverse]),
    #{ordinal => Ordinal, port => Port, offset => Offset,
      inverse_offset => Inverse, inverse_ordinal => InverseOrdinal}.

normalize_offset(Offset, Shape) when length(Offset) =:= length(Shape) ->
    [canonical_offset(Value, Size) || {Value, Size} <- lists:zip(Offset, Shape)];
normalize_offset(Offset, Shape) -> error({source_fragment_offset_shape, Offset, Shape}).

negate(Offset) -> [-Value || Value <- Offset].
canonical_offset(Value, Size) ->
    Residue = positive_mod(Value, Size),
    case Residue > Size div 2 of true -> Residue - Size; false -> Residue end.
positive_mod(Value, Modulus) -> ((Value rem Modulus) + Modulus) rem Modulus.

scheduled_groups(FamilyId, Module, Scheduler) ->
    References = lists:append([[{maps:get(id, Group), maps:get(reference, Member)}
        || Member <- maps:get(members, Group), maps:get(kind, Member) =:= family,
           maps:get(id, Member) =:= FamilyId] || Group <- maps:get(groups, Scheduler)]),
    case lists:member({family, FamilyId}, maps:get(direct_members, Scheduler)) of
        true -> error({source_fragment_family_not_fully_scheduled, FamilyId, direct});
        false -> ok
    end,
    ok = complete_coverage(FamilyId, References),
    lists:foreach(fun({GroupId, _}) ->
        [Group] = [G || G <- maps:get(groups, Scheduler), maps:get(id, G) =:= GroupId],
        case maps:get(module, Group) =:= Module of
            true -> ok;
            false -> error({source_fragment_scheduler_module,
                FamilyId, GroupId, Module, maps:get(module, Group)})
        end
    end, References),
    lists:usort([GroupId || {GroupId, _} <- References]).

complete_coverage(FamilyId, References) ->
    Refs = [Ref || {_GroupId, Ref} <- References],
    Full = [Ref || Ref = {family, Candidate} <- Refs, Candidate =:= FamilyId],
    Parts = [{I, N} || {family, Candidate, {interleaved, I, N}} <- Refs,
        Candidate =:= FamilyId],
    Complete = case {Full, Parts} of
        {[_], []} -> true;
        {[], [_ | _]} -> case lists:usort([N || {_I, N} <- Parts]) of
            [N] -> lists:sort([I || {I, _} <- Parts]) =:= lists:seq(0, N - 1);
            _ -> false
        end;
        _ -> false
    end,
    case Complete of
        true -> ok;
        false -> error({source_fragment_family_not_fully_scheduled,
            FamilyId, lists:sort(Refs)})
    end.

derive_artifact_requirements(Scheduler, Requested) ->
    GroupRequirements = [group_requirement(Group, Requested)
        || Group <- maps:get(groups, Scheduler)],
    ByModule = lists:foldl(fun({GroupId, Module, Requirement}, Acc) ->
        maps:update_with(Module, fun(Items) -> [{GroupId, Requirement} | Items] end,
            [{GroupId, Requirement}], Acc)
    end, #{}, GroupRequirements),
    maps:from_list([{Module, module_requirement(Module, Items)}
        || {Module, Items} <- lists:sort(maps:to_list(ByModule))]).

group_requirement(#{id := Id, module := Module, members := Members}, Requested) ->
    Requirements = lists:usort([case Member of
        #{kind := family, id := FamilyId} -> case maps:is_key(FamilyId, Requested) of
            true -> aggregate_only;
            false -> ordinary
        end;
        #{kind := actor} -> ordinary
    end || Member <- Members]),
    case Requirements of
        [Requirement] -> {Id, Module, Requirement};
        Mixed -> error({source_fragment_scheduler_group_conflict, Id, Mixed})
    end.

module_requirement(Module, Items) ->
    case lists:usort([Requirement || {_GroupId, Requirement} <- Items]) of
        [Requirement] -> #{shared_service => Requirement};
        _ -> error({source_fragment_module_artifact_conflict, Module, lists:sort(Items)})
    end.

validate_scheduler_modules(Topology, Scheduler) ->
    Modules = logical_modules(Topology),
    lists:foreach(fun(#{id := GroupId, module := GroupModule, members := Members}) ->
        lists:foreach(fun(#{kind := Kind, id := Id, module := MemberModule}) ->
            Expected = maps:get({Kind, Id}, Modules),
            case {MemberModule, GroupModule} of
                {Expected, Expected} -> ok;
                _ -> error({scheduler_group_module_mismatch, GroupId, {Kind, Id},
                    Expected, MemberModule, GroupModule})
            end
        end, Members)
    end, maps:get(groups, Scheduler)).

validate_inputs(#{version := 1, actors := Actors, families := Families,
        route_relations := Relations, ingresses := Ingresses, startup := Startup},
        #{groups := Groups, direct_members := Direct}, Requested)
        when is_list(Actors), is_list(Families), is_list(Relations),
             is_list(Ingresses), is_list(Startup), is_list(Groups),
             is_list(Direct), is_map(Requested) -> ok;
validate_inputs(_Topology, _Scheduler, _Requested) ->
    error({invalid_reduction_plan_inputs, expected_normalized_plans}).

validate_selections(Requested, FamilyIndex) ->
    lists:map(fun
        ({FamilyId, source_fragments} = Selection) -> case maps:is_key(FamilyId, FamilyIndex) of
            true -> Selection;
            false -> error({source_fragment_unknown_family, FamilyId})
        end;
        ({FamilyId, Placement}) ->
            error({unsupported_reduction_placement, FamilyId, Placement})
    end, lists:sort(maps:to_list(Requested))).

module_interfaces(Families) ->
    maps:from_list([{Module, hls_actor_interface:from_module(Module)}
        || Module <- lists:usort([maps:get(module, Family) || Family <- Families])]).

family_module(FamilyId, Topology) ->
    [#{module := Module}] = [Family || Family <- maps:get(families, Topology),
        maps:get(id, Family) =:= FamilyId],
    Module.

logical_modules(#{actors := Actors, families := Families}) ->
    maps:from_list([{{actor, maps:get(id, A)}, maps:get(module, A)} || A <- Actors] ++
        [{{family, maps:get(id, F)}, maps:get(module, F)} || F <- Families]).

index_by_id(Items) -> maps:from_list([{maps:get(id, Item), Item} || Item <- Items]).

counts(Values) -> lists:foldl(fun(Value, Acc) ->
    maps:update_with(Value, fun(Count) -> Count + 1 end, 1, Acc)
end, #{}, Values).

duplicates(Values) ->
    Counts = counts(Values),
    lists:sort([Value || {Value, Count} <- maps:to_list(Counts), Count > 1]).
