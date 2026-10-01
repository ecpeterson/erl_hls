%%%% hls_scheduler_plan
%%%%
%%%% Normalizes provisional homogeneous actor-sharing groups.

-module(hls_scheduler_plan).
-moduledoc """
Normalizes the first physical plan for sharing one actor implementation across
several logical instances.

The semantic topology remains authoritative for actor identity, routing, and
mailbox capacity. A scheduler group only chooses a physical realization: one
executor services every member of the group, while each logical actor retains
its own state and mailbox slots. Ungrouped actors retain their ordinary direct
realization.

This format groups exact actors, complete families, or statically interleaved
partitions of a family. Every member must use the same actor module, which is
the current compiler's provisional artifact identity. A later artifact
fingerprint can replace that test without changing the group/member
distinction. Family partitions divide the row-major logical instances among
several executors while leaving semantic family identity and routing intact.

Each storage choice is a required physical binding, not a hint. A backend must
either realize the corresponding state there or reject the plan. Actor data,
actor-local reduction state, and mailboxes remain distinct in the compiler's
logical interface; reduction state is packed alongside actor data in the same
per-instance state row. Mailboxes are a separate binding because safe shared
scheduling also needs per-instance bounded admission state.

A shared executor advances selected actors while preserving each actor's
ordered effects. Already accepted effects are never rolled back or sent again.
The scheduler can visit other eligible actors while one actor awaits an
effect credit, but finite result and routing buffers can eventually stall the
whole group under downstream backpressure. The actor-level `fail` directive
remains a terminal failure and is not this scheduler retry mechanism.

Actor selection does not prove progress for an application protocol which has
already committed a resource acquisition, or for a bounded destination mailbox
whose only free space can be consumed by requests that depend on a later
release. Those remain topology-level channel-dependency and reserved-progress
obligations.
""".

-export([normalize/2, placements/1]).
-export_type([plan/0, spec/0]).

%% Physical implementation selected for a bounded state or mailbox store.
-type storage() :: registers | block_ram.
%% An exact actor, complete family or interleaved family partition assigned to a group.
-type member_ref() ::
    {actor, term()} |
    {family, term()} |
    {family, term(), {interleaved, non_neg_integer(), pos_integer()}}.
-doc "Maps scheduler identities to bounded members, storage bindings and optional state specialization.".
-type spec() :: #{term() := #{
    members := [member_ref(), ...],
    state_storage := storage(),
    mailbox_storage := storage(),
    specialize_state => boolean(),
    admission_reductions => boolean() | exclusive_epoch
}}.
-doc "Normalized physical execution graph with logical identities retained for routing and debugging.".
-type plan() :: #{
    groups := [map()],
    direct_members := [member_ref()]
}.

-doc "Validates scheduler groups against one normalized semantic topology.".
-spec normalize(hls_topology:plan(), spec()) -> plan().
normalize(Topology = #{actors := _, families := _}, Specs)
        when is_map(Specs) ->
    MemberIndex = member_index(Topology),
    Declarations = [
        normalize_group(Id, Group, MemberIndex)
        || {Id, Group} <- lists:sort(maps:to_list(Specs))
    ],
    Interfaces = hls_actor_interface:from_modules(
        [Module || #{module := Module} <- Declarations]),
    Groups = hls_topology_constants:specialize(Topology,
        [layout_group(Group, maps:get(Module, Interfaces))
        || Group = #{module := Module} <- Declarations]),
    Grouped = lists:append([
        [member_reference(Member) || Member <- maps:get(members, Group)]
        || Group <- Groups
    ]),
    ok = require_unique(members, Grouped),
    ok = validate_grouped_members(Grouped, MemberIndex),
    All = lists:sort(maps:keys(MemberIndex)),
    #{
        groups => Groups,
        direct_members => [
            Reference
            || Reference <- All,
               not member_grouped(Reference, Grouped)
        ]
    };
normalize(_Topology, Specs) ->
    error({scheduler_groups, Specs}).

%% Validates one homogeneous group and expands its member references.
-spec normalize_group(term(),map(),map()) -> map().
normalize_group(Id, Spec, MemberIndex) when is_map(Spec) ->
    ok = validate_keys(Id, Spec),
    #{
        members := MemberSpecs,
        state_storage := StateStorage,
        mailbox_storage := MailboxStorage
    } = Spec,
    ok = validate_storage(Id, state, StateStorage),
    ok = validate_storage(Id, mailbox, MailboxStorage),
    Specialize = maps:get(specialize_state, Spec, false),
    Collection = maps:get(admission_reductions, Spec, false),
    case is_boolean(Collection) orelse Collection =:= exclusive_epoch of true -> ok; false -> error({admission_reductions, Id, Collection}) end,
    case is_boolean(Specialize) of true -> ok; false -> error({specialize_state, Id, Specialize}) end,
    Members0 = normalize_members(Id, MemberSpecs, MemberIndex),
    Modules = lists:usort([maps:get(module, Member) || Member <- Members0]),
    Module = case Modules of
        [Only] -> Only;
        _ -> error({heterogeneous_group, Id, Modules})
    end,
    Group = #{id => Id, module => Module, members => Members0,
        state_storage => StateStorage, mailbox_storage => MailboxStorage},
    WithCollection = case Collection of false -> Group; _ -> Group#{admission_reductions => Collection} end,
    case Specialize of true -> WithCollection#{specialize_state => true}; false -> WithCollection end;
normalize_group(Id, _Spec, _MemberIndex) ->
    error({scheduler_group, Id}).

%% Assign slots and preserve the actor interface's complete private-storage dimensions.
-spec layout_group(map(), map()) -> map().
layout_group(Group = #{members := Members0}, Interface) ->
    Capacity = maps:get(mailbox_capacity, Interface),
    true = lists:all(
        fun(#{mailbox_capacity := MemberCapacity}) ->
            MemberCapacity =:= Capacity
        end,
        Members0
    ),
    State = hls_actor_interface:state(Interface),
    ReductionStorageWidth =
        hls_actor_interface:reduction_storage_width(Interface),
    {Members, SlotCount} = assign_slots(Members0),
    EventStorage = maps:with([continuation_width, reply_storage_width], Interface),
    maps:merge(EventStorage, Group#{
        state => State,
        reduction_storage_width => ReductionStorageWidth,
        mailbox_capacity => Capacity,
        members => Members,
        slot_count => SlotCount,
        selection => round_robin,
        effect_progress => resumable,
        reservation => none,
        blocked => yield
    }).

%% Rejects unsupported or missing group settings.
-spec validate_keys(term(),map()) -> 'ok'.
validate_keys(Id, Spec) ->
    Required = [mailbox_storage, members, state_storage],
    Keys = maps:keys(Spec),
    case {Required -- Keys, Keys -- (Required ++ [specialize_state, admission_reductions])} of
        {[], []} -> ok;
        {Missing, Unknown} -> error({scheduler_group_keys,
            Id, Missing, Unknown})
    end.

%% Accepts only the supported register and block-RAM storage policies.
-spec validate_storage(term(),'mailbox' | 'state','block_ram' | 'registers') -> 'ok'.
validate_storage(_Id, _Kind, registers) -> ok;
validate_storage(_Id, _Kind, block_ram) -> ok;
validate_storage(Id, Kind, Storage) ->
    error({storage, Id, Kind, Storage}).

%% Expands group references into concrete members and rejects duplicate ownership.
-spec normalize_members(term(),[any(),...],map()) -> [map()].
normalize_members(Id, [_ | _] = MemberSpecs, MemberIndex) ->
    ok = require_unique({group, Id}, MemberSpecs),
    Members = [lookup_member(Member, MemberIndex)
        || Member <- lists:sort(MemberSpecs)],
    Logical = [{maps:get(kind, Member), maps:get(id, Member)}
        || Member <- Members],
    ok = require_unique({group, Id, logical_members}, Logical),
    Members;
normalize_members(Id, _MemberSpecs, _MemberIndex) ->
    error({members, Id}).

%% Resolves an actor or family reference against the normalized logical graph.
-spec lookup_member(term(),map()) -> map().
lookup_member(Reference, MemberIndex) ->
    case maps:find(Reference, MemberIndex) of
        {ok, Member} -> Member#{
            reference => Reference,
            instances => member_instances(Member)
        };
        error -> lookup_partition(Reference, MemberIndex)
    end.

%% Selects one nonempty interleaved partition of a family.
-spec lookup_partition({'family',term(),{'interleaved',term(),term()}},map()) -> map().
lookup_partition(
    Reference = {family, Id, {interleaved, Index, Count}},
    MemberIndex
) when Index >= 0, Count > 0, Index < Count ->
    case maps:find({family, Id}, MemberIndex) of
        {ok, Member} ->
            Instances = [
                Instance
                || Instance = #{linear_index := Linear} <-
                       member_instances(Member),
                   Linear rem Count =:= Index
            ],
            case Instances of
                [] -> error({empty_partition, Reference});
                [_ | _] -> Member#{
                    reference => Reference,
                    partition => #{
                        kind => interleaved,
                        index => Index,
                        count => Count
                    },
                    instances => Instances,
                    instance_count => length(Instances)
                }
            end;
        error -> error({unknown_member, Reference})
    end;
lookup_partition(Reference, _MemberIndex) ->
    error({unknown_member, Reference}).

%% Assigns dense RAM slots to the group's members in deterministic order.
-spec assign_slots([map()]) -> {[map()], non_neg_integer()}.
assign_slots(Members) ->
    {Reverse, SlotCount} = lists:foldl(
        fun(Member = #{instance_count := Count}, {Acc, Base}) ->
            Instances = [Instance#{local_index => Index}
                || {Index, Instance} <- lists:enumerate(0,
                    maps:get(instances, Member))],
            {[Member#{base_slot => Base, instances => Instances} | Acc],
                Base + Count}
        end,
        {[], 0},
        Members
    ),
    {lists:reverse(Reverse), SlotCount}.

%% Returns the logical reference represented by a normalized member.
-spec member_reference(map()) -> member_ref().
member_reference(#{reference := Reference}) -> Reference.

%% Enumerates the concrete identities belonging to one member reference.
-spec member_instances(map()) -> [map()].
member_instances(#{kind := actor}) ->
    [#{linear_index => 0}];
member_instances(#{kind := family, shape := [Width, Height]}) ->
    [
        #{coordinates => [X, Y], linear_index => X * Height + Y}
        || X <- lists:seq(0, Width - 1),
           Y <- lists:seq(0, Height - 1)
    ].

%% Checks disjoint coverage of actors assigned to physical groups.
-spec validate_grouped_members([any()],map()) -> 'ok'.
validate_grouped_members(Grouped, MemberIndex) ->
    lists:foreach(
        fun(Reference) ->
            validate_member_coverage(Reference, Grouped)
        end,
        maps:keys(MemberIndex)
    ).

%% Rejects overlaps between whole-family and partition assignments.
-spec validate_member_coverage({'actor',term()} | {'family',term()},[any()]) -> 'ok'.
validate_member_coverage({actor, _} = Reference, Grouped) ->
    ok = require_unique(members, [R || R <- Grouped, R =:= Reference]);
validate_member_coverage({family, Id} = Reference, Grouped) ->
    Full = [R || R <- Grouped, R =:= Reference],
    Partitions = [
        {Index, Count}
        || {family, Candidate, {interleaved, Index, Count}} <- Grouped,
           Candidate =:= Id
    ],
    case {Full, Partitions} of
        {[], []} -> ok;
        {[_], []} -> ok;
        {[], [_ | _]} -> validate_partition_coverage(Id, Partitions);
        _ -> error({overlapping_member, Reference})
    end.

%% Requires compatible partition counts and nonoverlapping partition indices.
-spec validate_partition_coverage(term(),[{term(),term()},...]) -> 'ok'.
validate_partition_coverage(Id, Partitions) ->
    Counts = lists:usort([Count || {_Index, Count} <- Partitions]),
    case Counts of
        [Count] ->
            Indices = lists:sort([Index || {Index, Count0} <- Partitions,
                Count0 =:= Count]),
            Expected = lists:seq(0, Count - 1),
            case Indices =:= Expected of
                true -> ok;
                false -> error({incomplete_partition, {family, Id},
                    Count, Indices})
            end;
        _ -> error({mixed_partition_counts, {family, Id}, Counts})
    end.

%% Tests whether a logical member is already owned by a shared group.
-spec member_grouped(term(),[any()]) -> boolean().
member_grouped(Reference, Grouped) ->
    lists:member(Reference, Grouped) orelse
        case Reference of
            {family, Id} -> lists:any(
                fun
                    ({family, Id0, {interleaved, _, _}}) -> Id0 =:= Id;
                    (_) -> false
                end,
                Grouped
            );
            {actor, _} -> false
        end.

%% Builds lookup entries for exact actors and declared families.
-spec member_index(map()) -> map().
member_index(#{actors := Actors, families := Families}) ->
    maps:from_list(
        [actor_member(Actor) || Actor <- Actors] ++
        [family_member(Family) || Family <- Families]
    ).

%% Represents one exact actor as a one-instance member.
-spec actor_member(map()) -> {{'actor',term()},map()}.
actor_member(#{id := Id, module := Module,
        mailbox_capacity := Capacity}) ->
    {{actor, Id}, #{
        kind => actor,
        id => Id,
        module => Module,
        instance_count => 1,
        mailbox_capacity => Capacity
    }}.

%% Represents a rectangular family with its concrete instance coordinates.
-spec family_member(map()) -> {{'family',term()},map()}.
family_member(#{id := Id, module := Module, shape := Shape,
        instance_count := Count, mailbox_capacity := Capacity}) ->
    {{family, Id}, #{
        kind => family,
        id => Id,
        module => Module,
        shape => Shape,
        instance_count => Count,
        mailbox_capacity => Capacity
    }}.

%% Rejects duplicate identities with the caller's diagnostic context.
-spec require_unique('members' | {'group',term()} | {'group',term(),'logical_members'},[any()]) -> 'ok'.
require_unique(Kind, Values) ->
    case Values -- lists:usort(Values) of
        [] -> ok;
        Duplicates -> error({duplicate, Kind, lists:usort(Duplicates)})
    end.

-doc "Maps logical actor identities to generated scheduler indices and RAM slots.".
-spec placements(plan()) -> #{term() => map()}.
placements(#{groups := Groups}) ->
    maps:from_list(lists:append([group_placements(Group, Index) ||
        {Index, Group} <- lists:enumerate(0, Groups)])).

%% Maps each group member to its physical executor and RAM slot.
-spec group_placements(map(),integer()) -> [{{term(),term()} | {term(),term(),term()},map()}].
group_placements(#{id := GroupId, members := Members}, Index) ->
    [{instance_id(Member, Instance), #{kind => scheduler, id => GroupId,
        index => Index, slot => Base + Local}} ||
        Member = #{base_slot := Base, instances := Instances} <- Members,
        Instance = #{local_index := Local} <- Instances].

%% Builds the logical actor identity of a normalized member instance.
-spec instance_id(map(),map()) -> {'actor',term()} | {'family',term(),term()}.
instance_id(#{kind := actor, id := Id}, _) -> {actor, Id};
instance_id(#{kind := family, id := Id}, #{coordinates := Coordinates}) ->
    {family, Id, Coordinates}.
