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

This first format groups complete exact actors or complete families. Every
member must use the same actor module, which is the current compiler's
provisional artifact identity. A later artifact fingerprint can replace that
test without changing the group/member distinction. More parallelism is
expressed initially by splitting members into additional groups; spatial
partitions within one family are not yet described.

Each storage choice is a required physical binding, not a hint. A backend must
either realize the corresponding state there or reject the plan. Actor data
and mailboxes are separate bindings because safe shared scheduling needs both
per-instance callback state and per-instance bounded admission state.

A shared executor must never wait on an uncommitted transition while excluding
another actor in its group. Since callback evaluation is side-effect-free, it
may evaluate speculatively, but it must commit the new actor state, consume the
mailbox head, and expose the ordered effect burst only after that whole burst
can be accepted. If admission is unavailable, it leaves the actor unchanged
and tries another ready member; it may not retain a partial reservation while
doing so. The actor-level `fail` directive remains a terminal failure and is
not this scheduler retry mechanism.

This prevents the executor itself from creating head-of-line deadlock. It does
not prove progress for an application protocol which has already committed a
resource acquisition, or for a bounded destination mailbox whose only free
space can be consumed by requests that depend on a later release. Those remain
topology-level channel-dependency and reserved-progress obligations.
""".

-export([normalize/2]).
-export_type([plan/0, spec/0]).

-type storage() :: registers | block_ram.
-type member_ref() :: {actor, term()} | {family, term()}.
-type spec() :: #{atom() := #{
    members := [member_ref(), ...],
    state_storage := storage(),
    mailbox_storage := storage()
}}.
-type plan() :: #{
    groups := [map()],
    direct_members := [member_ref()]
}.

-doc "Validates scheduler groups against one normalized semantic topology.".
-spec normalize(hls_topology:plan(), spec()) -> plan().
normalize(Topology = #{actors := _, families := _}, Specs)
        when is_map(Specs) ->
    MemberIndex = member_index(Topology),
    Groups = [
        normalize_group(Id, Group, MemberIndex)
        || {Id, Group} <- lists:sort(maps:to_list(Specs))
    ],
    Grouped = lists:append([
        [member_reference(Member) || Member <- maps:get(members, Group)]
        || Group <- Groups
    ]),
    ok = require_unique(members, Grouped),
    All = lists:sort(maps:keys(MemberIndex)),
    #{
        groups => Groups,
        direct_members => All -- Grouped
    };
normalize(_Topology, Specs) ->
    error({scheduler_groups, Specs}).

normalize_group(Id, Spec, MemberIndex) when is_atom(Id), is_map(Spec) ->
    ok = validate_keys(Id, Spec),
    #{
        members := MemberSpecs,
        state_storage := StateStorage,
        mailbox_storage := MailboxStorage
    } = Spec,
    ok = validate_storage(Id, state, StateStorage),
    ok = validate_storage(Id, mailbox, MailboxStorage),
    Members0 = normalize_members(Id, MemberSpecs, MemberIndex),
    Modules = lists:usort([maps:get(module, Member) || Member <- Members0]),
    Module = case Modules of
        [Only] -> Only;
        _ -> error({heterogeneous_group, Id, Modules})
    end,
    Interface = hls_actor_interface:from_module(Module),
    Capacity = maps:get(mailbox_capacity, Interface),
    true = lists:all(
        fun(#{mailbox_capacity := MemberCapacity}) ->
            MemberCapacity =:= Capacity
        end,
        Members0
    ),
    State = hls_actor_interface:state(Interface),
    {Members, SlotCount} = assign_slots(Members0),
    #{
        id => Id,
        module => Module,
        state => State,
        mailbox_capacity => Capacity,
        members => Members,
        slot_count => SlotCount,
        selection => round_robin,
        commit => all_or_retry,
        blocked => yield,
        state_storage => StateStorage,
        mailbox_storage => MailboxStorage
    };
normalize_group(Id, _Spec, _MemberIndex) ->
    error({scheduler_group, Id}).

validate_keys(Id, Spec) ->
    Required = [mailbox_storage, members, state_storage],
    Keys = maps:keys(Spec),
    case {Required -- Keys, Keys -- Required} of
        {[], []} -> ok;
        {Missing, Unknown} -> error({scheduler_group_keys,
            Id, Missing, Unknown})
    end.

validate_storage(_Id, _Kind, registers) -> ok;
validate_storage(_Id, _Kind, block_ram) -> ok;
validate_storage(Id, Kind, Storage) ->
    error({storage, Id, Kind, Storage}).

normalize_members(Id, [_ | _] = MemberSpecs, MemberIndex) ->
    ok = require_unique({group, Id}, MemberSpecs),
    [lookup_member(Member, MemberIndex)
        || Member <- lists:sort(MemberSpecs)];
normalize_members(Id, _MemberSpecs, _MemberIndex) ->
    error({members, Id}).

lookup_member(Reference, MemberIndex) ->
    case maps:find(Reference, MemberIndex) of
        {ok, Member} -> Member;
        error -> error({unknown_member, Reference})
    end.

assign_slots(Members) ->
    {Reverse, SlotCount} = lists:foldl(
        fun(Member = #{instance_count := Count}, {Acc, Base}) ->
            {[Member#{base_slot => Base} | Acc], Base + Count}
        end,
        {[], 0},
        Members
    ),
    {lists:reverse(Reverse), SlotCount}.

member_reference(#{kind := Kind, id := Id}) -> {Kind, Id}.

member_index(#{actors := Actors, families := Families}) ->
    maps:from_list(
        [actor_member(Actor) || Actor <- Actors] ++
        [family_member(Family) || Family <- Families]
    ).

actor_member(#{id := Id, module := Module,
        mailbox_capacity := Capacity}) ->
    {{actor, Id}, #{
        kind => actor,
        id => Id,
        module => Module,
        instance_count => 1,
        mailbox_capacity => Capacity
    }}.

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

require_unique(Kind, Values) ->
    case Values -- lists:usort(Values) of
        [] -> ok;
        Duplicates -> error({duplicate, Kind, lists:usort(Duplicates)})
    end.
