-module(hls_spacetime_schedule).
-moduledoc """
Pure scheduler-request policy for proposed implementation plans.

Actors are grouped only by proposed target and compiled module. The result requests homogeneous
sharing but assigns no RAM layout, slot width, generated source or target timing.
""".

-export([shared_by_module/3]).

-doc "Balances each target/module bucket across the fewest groups with at most `MaxActors` members. Every topology instance must have one placement.".
-spec shared_by_module(
    hls_logical_topology:plan(), hls_implementation_plan:placement(), pos_integer()
) -> [hls_implementation_plan:schedule()].
shared_by_module(Topology, Placement, MaxActors) when
    is_integer(MaxActors), MaxActors > 0
->
    Instances = hls_logical_topology:instances(Topology),
    Buckets = lists:foldl(
        fun(#{identity := Identity, actor := #{module := Module}}, Acc) ->
            Target = maps:get(Identity, Placement),
            maps:update_with({Target, Module}, fun(Ids) -> [Identity | Ids] end, [Identity], Acc)
        end,
        #{},
        Instances
    ),
    Extra = maps:keys(Placement) -- [Identity || #{identity := Identity} <- Instances],
    case Extra of
        [] -> ok;
        _ -> error({unknown_placement_members, lists:sort(Extra)})
    end,
    lists:sort(
        maps:fold(
            fun({Target, Module}, Identities, Acc) ->
                Groups = groups(lists:sort(Identities), MaxActors),
                Acc ++
                    [
                        #{
                            id => {schedule, Target, Module, Index},
                            target => Target,
                            module => Module,
                            members => Members
                        }
                     || {Index, Members} <- lists:enumerate(0, Groups)
                    ]
            end,
            [],
            Buckets
        )
    );
shared_by_module(_Topology, _Placement, MaxActors) ->
    error({invalid_scheduler_capacity, MaxActors}).

%% Preserve canonical member order while splitting one homogeneous bucket.
-spec groups([hls_actor_identity:id(), ...], pos_integer()) ->
    [[hls_actor_identity:id(), ...], ...].
groups(Identities, MaxActors) -> groups(Identities, MaxActors, []).

%% Produce fixed-size prefixes and one nonempty remainder.
-spec groups([hls_actor_identity:id()], pos_integer(), [[hls_actor_identity:id(), ...]]) ->
    [[hls_actor_identity:id(), ...], ...].
groups([], _MaxActors, Acc) ->
    lists:reverse(Acc);
groups(Identities, MaxActors, Acc) ->
    {Group, Rest} = lists:split(min(MaxActors, length(Identities)), Identities),
    groups(Rest, MaxActors, [Group | Acc]).
